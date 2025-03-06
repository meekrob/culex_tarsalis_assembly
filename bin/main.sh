#!/bin/bash


# main.sh - Master control script for mosquito RNA-seq pipeline
# This script identifies input files, sets up directories, and manages job dependencies

#SBATCH --job-name=main
#SBATCH --output=./logs/main_%j.out
#SBATCH --error=./logs/main_%j.err

# Get start time for timing
start_time=$(date +%s)

# Source conda
source ~/.bashrc

# Parse command line arguments
reference_transcriptome=""
debug_mode=false

while getopts "R:d" opt; do
  case $opt in
    R)
      reference_transcriptome="$OPTARG"
      ;;
    d)
      debug_mode=true
      ;;
    \?)
      echo "Invalid option: -$OPTARG" >&2
      exit 1
      ;;
  esac
done

shift $((OPTIND-1))

# Define base directories
current_dir=$(pwd)
data_base="${1:-${current_dir}/data}"
result_base="${2:-${current_dir}/results}"
logs_base="${current_dir}/logs"
temp_dir="${current_dir}/temp"

# Create output directories
mkdir -p "$result_base"
mkdir -p "$logs_base"
mkdir -p "$temp_dir"

# Define specific output directories
trimmed_dir="${result_base}/01_trimmed"
merged_dir="${result_base}/02_merged"
assembly_dir="${result_base}/03_assembly"
busco_dir="${result_base}/04_busco"
rnaquast_dir="${result_base}/04_rnaquast"
viz_dir="${result_base}/05_visualization"

# Create these directories
mkdir -p "$trimmed_dir"
mkdir -p "$merged_dir"
mkdir -p "$assembly_dir"
mkdir -p "$busco_dir"
mkdir -p "$rnaquast_dir"
mkdir -p "$viz_dir"

# Create specific log directories
trim_logs="${logs_base}/01_trimming"
merge_logs="${logs_base}/02_merge"
assembly_logs="${logs_base}/03_assembly"
busco_logs="${logs_base}/04_busco"
rnaquast_logs="${logs_base}/04_rnaquast"
viz_logs="${logs_base}/05_visualization"

# Create log directories
mkdir -p "$trim_logs"
mkdir -p "$merge_logs"
mkdir -p "$assembly_logs"
mkdir -p "$busco_logs"
mkdir -p "$rnaquast_logs"
mkdir -p "$viz_logs"

# Create summary file
summary_file="${logs_base}/pipeline_summary.csv"
echo "Step,Sample,Metric,Value" > "$summary_file"

# Display run info
echo "====== Mosquito RNA-Seq Pipeline ======"
echo "Data directory: $data_base"
echo "Results directory: $result_base"
echo "Logs directory: $logs_base"
if [[ -n "$reference_transcriptome" && -f "$reference_transcriptome" ]]; then
    echo "Reference transcriptome: $reference_transcriptome"
fi
if [[ "$debug_mode" == true ]]; then
    echo "Running in DEBUG mode - will skip steps with existing outputs"
fi
echo "======================================"

# Step 1: Identify read pairs
echo "Identifying read pairs..."

# Find all fastq files in the data directory
find "$data_base" -type f -name "*.fastq.gz" -o -name "*.fq.gz" > "$temp_dir/all_fastq_files.txt"

# Handle empty file list
if [[ ! -s "$temp_dir/all_fastq_files.txt" ]]; then
    echo "Error: No fastq files found in $data_base"
    exit 1
fi

# Set up arrays to store the samples and files
samples=()
r1_files_array=()
r2_files_array=()

# Process the file list to pair reads
while IFS= read -r filepath; do
    filename=$(basename "$filepath")
    
    # Extract sample name and read number (R1/R2)
    if [[ "$filename" =~ (.*)_R1[_.].*\.f(ast)?q(\.gz)? ]]; then
        # This is an R1 file
        sample="${BASH_REMATCH[1]}"
        r1_file="$filepath"
        
        # Look for the matching R2 file
        r2_pattern="${sample}_R2"
        r2_file=$(grep "$r2_pattern" "$temp_dir/all_fastq_files.txt" | head -n 1)
        
        if [[ -n "$r2_file" ]]; then
            echo "Found pair for sample $sample:"
            echo "  R1: $r1_file"
            echo "  R2: $r2_file"
            
            samples+=("$sample")
            r1_files_array+=("$r1_file")
            r2_files_array+=("$r2_file")
        else
            echo "Warning: No matching R2 file found for $r1_file"
        fi
    fi
done < "$temp_dir/all_fastq_files.txt"

# Check if any samples were found
if [[ ${#samples[@]} -eq 0 ]]; then
    echo "Error: No valid paired-end samples found in $data_base"
    exit 1
fi

echo "Found ${#samples[@]} paired samples to process"

# Step 2: Submit trimming jobs
echo "Submitting trimming jobs..."

# Create lists for merged files
r1_trimmed_list="$temp_dir/r1_trimmed.txt"
r2_trimmed_list="$temp_dir/r2_trimmed.txt"
> "$r1_trimmed_list"
> "$r2_trimmed_list"

# Array to store trimming job IDs
trim_job_ids=()

for ((i=0; i<${#samples[@]}; i++)); do
    sample="${samples[$i]}"
    r1="${r1_files_array[$i]}"
    r2="${r2_files_array[$i]}"
    
    # Output files for trimming
    trim_r1="${trimmed_dir}/${sample}_R1_trimmed.fastq.gz"
    trim_r2="${trimmed_dir}/${sample}_R2_trimmed.fastq.gz"
    
    # Add to trimmed files list for merging
    echo "$trim_r1" >> "$r1_trimmed_list"
    echo "$trim_r2" >> "$r2_trimmed_list"
    
    # Submit trimming job
    trim_cmd="sbatch --parsable --job-name=trim_${sample} --output=${trim_logs}/trim_${sample}_%j.out --error=${trim_logs}/trim_${sample}_%j.err"
    trim_job_id=$(eval $trim_cmd bin/01_trimming.sh "$r1" "$r2" "$trim_r1" "$trim_r2" "$sample" "$trim_logs" "$summary_file" "$debug_mode")
    
    if [[ -n "$trim_job_id" ]]; then
        trim_job_ids+=($trim_job_id)
        echo "Submitted trimming job for $sample: $trim_job_id"
    else
        echo "Error: Failed to submit trimming job for $sample"
        exit 1
    fi
done

# Step 3: Submit merging job
echo "Submitting merging job..."

# Set output files for merging
merged_r1="${merged_dir}/merged_R1.fastq.gz"
merged_r2="${merged_dir}/merged_R2.fastq.gz"

# Create dependency for merge job
merge_dependency=""
if [[ ${#trim_job_ids[@]} -gt 0 ]]; then
    merge_dependency="--dependency=afterany:"$(IFS=:; echo "${trim_job_ids[*]}")
fi

# Submit merge job
merge_cmd="sbatch --parsable --job-name=merge ${merge_dependency} --output=${merge_logs}/merge_%j.out --error=${merge_logs}/merge_%j.err"
merge_job_id=$(eval $merge_cmd bin/02_merge.sh "$r1_trimmed_list" "$r2_trimmed_list" "$merged_r1" "$merged_r2" "$merge_logs" "$debug_mode")

if [[ -n "$merge_job_id" ]]; then
    echo "Submitted merging job: $merge_job_id"
else
    echo "Error: Failed to submit merging job"
    exit 1
fi

# Step 4: Submit assembly job
echo "Submitting assembly job..."

# Submit assembly job
assembly_cmd="sbatch --parsable --job-name=assembly --output=${assembly_logs}/assembly_%j.out --error=${assembly_logs}/assembly_%j.err --dependency=afterok:${merge_job_id}"
assembly_job_id=$(eval $assembly_cmd bin/03_assembly.sh "$merged_r1" "$merged_r2" "$assembly_dir" "$assembly_logs" "$debug_mode" "$summary_file")

if [[ -n "$assembly_job_id" ]]; then
    echo "Submitted assembly job: $assembly_job_id"
else
    echo "Error: Failed to submit assembly job"
    exit 1
fi

# Step 5: Submit BUSCO and rnaQuast jobs
echo "Submitting quality assessment jobs..."

# Submit BUSCO job
busco_cmd="sbatch --parsable --job-name=busco --output=${busco_logs}/busco_%j.out --error=${busco_logs}/busco_%j.err --dependency=afterok:${assembly_job_id}"
busco_job_id=$(eval $busco_cmd bin/04_busco.sh "$assembly_dir/transcripts.fasta" "$busco_dir" "$busco_logs" "$debug_mode")

if [[ -n "$busco_job_id" ]]; then
    echo "Submitted BUSCO job: $busco_job_id"
else
    echo "Error: Failed to submit BUSCO job"
    exit 1
fi

# Submit rnaQuast job
rnaquast_cmd="sbatch --parsable --job-name=rnaquast --output=${rnaquast_logs}/rnaquast_%j.out --error=${rnaquast_logs}/rnaquast_%j.err --dependency=afterok:${assembly_job_id}"
rnaquast_job_id=$(eval $rnaquast_cmd bin/04_rnaquast.sh "$assembly_dir/transcripts.fasta" "$rnaquast_dir" "$rnaquast_logs" "$debug_mode")

if [[ -n "$rnaquast_job_id" ]]; then
    echo "Submitted rnaQuast job: $rnaquast_job_id"
else
    echo "Error: Failed to submit rnaQuast job"
    exit 1
fi

# Step 6: Submit visualization job
echo "Submitting visualization job..."

# Submit visualization job
viz_cmd="sbatch --parsable --job-name=visualize --output=${viz_logs}/viz_%j.out --error=${viz_logs}/viz_%j.err --dependency=afterok:${busco_job_id}:${rnaquast_job_id}"
viz_job_id=$(eval $viz_cmd bin/05_visualize.sh "$busco_dir" "$rnaquast_dir" "$viz_dir" "" "" "$viz_logs" "$summary_file" "$debug_mode")

if [[ -n "$viz_job_id" ]]; then
    echo "Submitted visualization job: $viz_job_id"
else
    echo "Error: Failed to submit visualization job"
    exit 1
fi

echo "All jobs submitted. Pipeline will run with the following job IDs:"
echo "  Trimming: ${trim_job_ids[*]}"
echo "  Merging: $merge_job_id"
echo "  Assembly: $assembly_job_id"
echo "  BUSCO: $busco_job_id"
echo "  rnaQuast: $rnaquast_job_id"
echo "  Visualization: $viz_job_id"

# Calculate total runtime
end_time=$(date +%s)
total_runtime=$((end_time - start_time))
echo "Pipeline setup completed in $total_runtime seconds"
echo "Check job status with: squeue -u $USER"
