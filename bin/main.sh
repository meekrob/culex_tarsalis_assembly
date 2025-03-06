#!/bin/bash


# main.sh - Master control script for mosquito RNA-seq pipeline
# This script identifies input files, sets up directories, and manages job dependencies


# Source conda
source ~/.bashrc

# Source parameters file
source config/parameters.txt

# Check if the conda environment exists and create it only if needed
if ! conda info --envs | grep -q "cellSquito"; then
    echo "Creating cellSquito conda environment..."
    conda env create -f config/cellSquito.yml -n cellSquito
else
    echo "cellSquito conda environment already exists"
fi

# Define directories (adjust these as needed)
raw_reads_dir="${1:-/data/raw_reads}"         # Directory with raw fastq files
result_base="${2:-/results}"                  # Base directory for all results
draft_transcriptome="${3:-input/draft_transcriptome/draft.fasta}"  # Path to draft transcriptome (optional)

# Create more specific output directories
trimmed_dir="${result_base}/01_trimmed"         # Directory for fastp output
merged_dir="${result_base}/02_merged"           # Directory for merged reads
assembly_dir="${result_base}/03_assembly"       # Output directory for rnaSpades
quality_dir="${result_base}/04_quality"         # Parent directory for quality results
busco_dir="${quality_dir}/busco"                # Output directory for busco
rnaquast_dir="${quality_dir}/rnaquast"          # Output directory for rnaquast
draft_busco_dir="${quality_dir}/draft_busco"    # BUSCO results for draft transcriptome
draft_rnaquast_dir="${quality_dir}/draft_rnaquast"  # rnaQuast results for draft
viz_dir="${result_base}/05_visualization"       # Output directory for visualizations
logs_dir="${result_base}/logs"                  # Directory for all log files

# Create output directories
mkdir -p "$trimmed_dir" "$merged_dir" "$assembly_dir" "$busco_dir" "$rnaquast_dir" \
         "$draft_busco_dir" "$draft_rnaquast_dir" "$viz_dir" "$logs_dir"

# Create temporary directory for file lists
tmp_dir="${result_base}/tmp"
mkdir -p "$tmp_dir"

echo "===== Mosquito RNA-Seq Pipeline ====="
echo "Raw reads directory: $raw_reads_dir"
echo "Results directory: $result_base"
echo "Log files: $logs_dir"
if [[ -f "$draft_transcriptome" ]]; then
    echo "Draft transcriptome: $draft_transcriptome"
fi
echo "======================================="

### Step 1: Parse Raw Reads and Identify Pairs
echo "Identifying read pairs..."

# Find all R1 files and extract sample names
# example name: Cxt-r2-35_R1_001.fastq.gz
# example name: Cx-Adult_R1.fastq.gz 

# Update pattern to handle both .fastq and .fastq.gz files
R1_files=($(ls ${raw_reads_dir}/*_R1*.fastq* 2>/dev/null))
samples=()
r1_files_array=()
r2_files_array=()

# Enhanced documentation for read pairing logic
echo "Pairing read files based on naming patterns..."
for r1_file in "${R1_files[@]}"; do
    # Extract the filename without the path
    filename=$(basename "$r1_file")
    
    # Extract sample name by removing R1 part and extensions
    # This handles both patterns: *_R1_001.fastq.gz and *_R1.fastq.gz
    sample_name=$(echo "$filename" | sed -E 's/(.*)_R1(.*)\.(fastq|fastq\.gz)$/\1/')
    
    # Construct expected R2 filename pattern
    if [[ "$filename" == *"_R1_"* ]]; then
        # For pattern: *_R1_001.fastq.gz
        r2_pattern="${sample_name}_R2"$(echo "$filename" | sed -E 's/.*(_R1)(.*)$/\2/')
    else
        # For pattern: *_R1.fastq.gz
        r2_pattern="${sample_name}_R2."$(echo "$filename" | sed -E 's/.*\.(fastq.*)$/\1/')
    fi
    
    # Check if R2 file exists
    r2_file=$(ls ${raw_reads_dir}/${r2_pattern} 2>/dev/null)
    
    if [[ -f "$r2_file" ]]; then
        samples+=("$sample_name")
        r1_files_array+=("$r1_file")
        r2_files_array+=("$r2_file")
    else
        echo "Warning: No matching R2 file found for $r1_file"
    fi
done

# Print samples and file pairs for verification
echo "Found ${#samples[@]} paired read files:"
for ((i=0; i<${#samples[@]}; i++)); do
    echo "Sample: ${samples[$i]}"
    echo "  R1: $(basename "${r1_files_array[$i]}")"
    echo "  R2: $(basename "${r2_files_array[$i]}")"
done

# Check if any read pairs were found
if [[ ${#samples[@]} -eq 0 ]]; then
    echo "Error: No read pairs found in $raw_reads_dir"
    exit 1
fi

### Step 2: Submit jobs
# Create file lists for later job submissions
r1_trimmed_list="${tmp_dir}/r1_trimmed_files.txt"
r2_trimmed_list="${tmp_dir}/r2_trimmed_files.txt"
> $r1_trimmed_list  # Clear the file if it exists
> $r2_trimmed_list  # Clear the file if it exists

# Array to store job IDs for dependency management
trim_job_ids=()

# Step 2.1: Submit trimming jobs for each pair
echo "Submitting trimming jobs..."
for ((i=0; i<${#samples[@]}; i++)); do
    sample="${samples[$i]}"
    r1="${r1_files_array[$i]}"
    r2="${r2_files_array[$i]}"
    
    # Set output files for trimming
    trim_r1="${trimmed_dir}/${sample}_R1_trimmed.fastq"
    trim_r2="${trimmed_dir}/${sample}_R2_trimmed.fastq"
    
    # Add to the list of trimmed files for merging
    echo "$trim_r1" >> $r1_trimmed_list
    echo "$trim_r2" >> $r2_trimmed_list
    
    echo "Submitting trimming job for sample $sample"
    # Submit trimming job with logs directory
    job_id=$(sbatch --parsable bin/01_trimming.sh "$r1" "$r2" "$trim_r1" "$trim_r2" "$sample" "$logs_dir")
    trim_job_ids+=($job_id)
    echo "  Job ID: $job_id"
done

# Step 2.2: Submit merging job (depends on all trimming jobs)
echo "Preparing to submit merging job..."
# Create dependency string for merge job to wait for all trimming jobs
trim_dependency=$(IFS=:; echo "afterok:${trim_job_ids[*]}")

# Set output for merged files
merged_r1="${merged_dir}/merged_R1.fastq"
merged_r2="${merged_dir}/merged_R2.fastq"

echo "Submitting merging job with dependency: $trim_dependency"
merge_job_id=$(sbatch --parsable --dependency=$trim_dependency bin/02_merge.sh "$r1_trimmed_list" "$r2_trimmed_list" "$merged_r1" "$merged_r2")
echo "  Merge job ID: $merge_job_id"

# Step 2.3: Submit assembly job (depends on merge job)
echo "Preparing to submit assembly job..."
echo "Submitting assembly job with dependency: afterok:$merge_job_id"
assembly_job_id=$(sbatch --parsable --dependency=afterok:$merge_job_id bin/03_assembly.sh "$merged_r1" "$merged_r2" "$assembly_dir")
echo "  Assembly job ID: $assembly_job_id"

# Step 2.4: Submit quality assessment jobs (depend on assembly job)
echo "Preparing to submit quality assessment jobs..."

# Set assembly output file path
assembly_fasta="${assembly_dir}/transcripts.fasta"

# Submit BUSCO job
echo "Submitting BUSCO job with dependency: afterok:$assembly_job_id"
busco_job_id=$(sbatch --parsable --dependency=afterok:$assembly_job_id bin/04_busco.sh "$assembly_fasta" "$busco_dir" "./busco_downloads" "new_assembly")
echo "  BUSCO job ID: $busco_job_id"

# Submit rnaQuast job
echo "Submitting rnaQuast job with dependency: afterok:$assembly_job_id"
rnaquast_job_id=$(sbatch --parsable --dependency=afterok:$assembly_job_id bin/04_rnaquast.sh "$assembly_fasta" "$rnaquast_dir" "$merged_r1" "$merged_r2")
echo "  rnaQuast job ID: $rnaquast_job_id"

# Draft transcriptome analysis (if available)
draft_busco_job_id=""
draft_rnaquast_job_id=""
if [[ -n "$draft_transcriptome" && -f "$draft_transcriptome" ]]; then
    echo "Found draft transcriptome: $draft_transcriptome"
    echo "Submitting BUSCO job for draft transcriptome"
    draft_busco_job_id=$(sbatch --parsable bin/04_busco.sh "$draft_transcriptome" "$draft_busco_dir" "./busco_downloads" "draft_assembly")
    echo "  Draft BUSCO job ID: $draft_busco_job_id"

    echo "Submitting rnaQuast job for draft transcriptome"
    draft_rnaquast_job_id=$(sbatch --parsable bin/04_rnaquast.sh "$draft_transcriptome" "$draft_rnaquast_dir" "$merged_r1" "$merged_r2")
    echo "  Draft rnaQuast job ID: $draft_rnaquast_job_id"
fi

# Step 2.5: Submit visualization job (depends on all quality assessment jobs)
echo "Preparing to submit visualization job..."
# Create dependency string for visualization - include draft jobs if they exist
if [[ -n "$draft_busco_job_id" && -n "$draft_rnaquast_job_id" ]]; then
    quality_dependency="afterok:$busco_job_id:$rnaquast_job_id:$draft_busco_job_id:$draft_rnaquast_job_id"
    # Pass both new and draft directories
    viz_job_id=$(sbatch --parsable --dependency=$quality_dependency bin/05_visualize.sh "$busco_dir" "$rnaquast_dir" "$viz_dir" "$draft_busco_dir" "$draft_rnaquast_dir")
else
    quality_dependency="afterok:$busco_job_id:$rnaquast_job_id"
    viz_job_id=$(sbatch --parsable --dependency=$quality_dependency bin/05_visualize.sh "$busco_dir" "$rnaquast_dir" "$viz_dir")
fi
echo "  Visualization job ID: $viz_job_id"

# Print job summary
echo "===== Job Summary ====="
echo "Trimming jobs: ${trim_job_ids[*]}"
echo "Merging job: $merge_job_id"
echo "Assembly job: $assembly_job_id"
echo "BUSCO job: $busco_job_id"
echo "rnaQuast job: $rnaquast_job_id"
if [[ -n "$draft_busco_job_id" ]]; then
    echo "Draft BUSCO job: $draft_busco_job_id"
fi
if [[ -n "$draft_rnaquast_job_id" ]]; then
    echo "Draft rnaQuast job: $draft_rnaquast_job_id"
fi
echo "Visualization job: $viz_job_id"
echo "======================="

echo "Pipeline submitted successfully. Check job status with 'squeue -u $USER'"
echo "Results will be available in: $result_base"
echo "Log files will be in: $logs_dir"
