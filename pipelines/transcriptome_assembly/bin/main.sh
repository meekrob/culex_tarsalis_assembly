#!/bin/bash


# main.sh - Master control script for mosquito RNA-seq pipeline
# This script identifies input files, sets up directories, and manages job dependencies

#SBATCH --job-name=transcriptome
#SBATCH --partition=day-long-cpu
#SBATCH --output=transcriptome_%j.out
#SBATCH --error=transcriptome_%j.err
#SBATCH --time=24:00:00
#SBATCH --mem=8G
#SBATCH --cpus-per-task=1

# Get start time for timing
start_time=$(date +%s)

# Source conda
source ~/.bashrc

# Detect repository root more reliably
# When running under SLURM, rely on current working directory
REPO_ROOT=$(pwd)
echo "Working directory: $REPO_ROOT"

# Parse command line arguments
debug_mode=false

while getopts "d" opt; do
  case $opt in
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

# Define standardized directories directly
DATA_DIR="${REPO_ROOT}/data"
RESULTS_DIR="${REPO_ROOT}/results"
LOGS_DIR="${REPO_ROOT}/logs"
TEMP_DIR="${REPO_ROOT}/temp"
RAW_READS_DIR="${DATA_DIR}/raw_reads"

# Define directory paths
data_base="${1:-${RAW_READS_DIR}}"
result_base="${2:-${RESULTS_DIR}/transcriptome_assembly}"
logs_base="${LOGS_DIR}/transcriptome_assembly"
temp_dir="${TEMP_DIR}/transcriptome_assembly"

# Create directories manually
echo "Creating pipeline directories..."
mkdir -p "${DATA_DIR}"
mkdir -p "${RESULTS_DIR}"
mkdir -p "${LOGS_DIR}"
mkdir -p "${TEMP_DIR}"
mkdir -p "${RAW_READS_DIR}"

mkdir -p "${result_base}"
mkdir -p "${logs_base}"
mkdir -p "${temp_dir}"

# Move SLURM output files to logs directory
trap "mv transcriptome_*.out transcriptome_*.err ${logs_base}/ 2>/dev/null || true" EXIT

# Create step-specific subdirectories
mkdir -p "${result_base}/01_trimmed"
mkdir -p "${result_base}/02_merged"
mkdir -p "${result_base}/03_pairs"
mkdir -p "${result_base}/04_normalized/bbnorm"
mkdir -p "${result_base}/04_normalized/trinity"
mkdir -p "${result_base}/05_assembly/bbnorm"
mkdir -p "${result_base}/05_assembly/trinity"
mkdir -p "${result_base}/06_busco/bbnorm"
mkdir -p "${result_base}/06_busco/trinity"

mkdir -p "${logs_base}/01_trimming"
mkdir -p "${logs_base}/02_merge"
mkdir -p "${logs_base}/03_pairs"
mkdir -p "${logs_base}/04_normalization/bbnorm"
mkdir -p "${logs_base}/04_normalization/trinity"
mkdir -p "${logs_base}/05_assembly/bbnorm"
mkdir -p "${logs_base}/05_assembly/trinity"
mkdir -p "${logs_base}/06_busco/bbnorm"
mkdir -p "${logs_base}/06_busco/trinity"

# Create summary file
summary_file="${logs_base}/pipeline_summary.csv"
touch "$summary_file"
echo "Step,Sample,Metric,Value" > "$summary_file"

# Check disk space
required_space=$((50 * 1024 * 1024)) # 50GB in KB
available_space=$(df -k "$result_base" | tail -1 | awk '{print $4}')
if [[ $available_space -lt $required_space ]]; then
    echo "Error: Insufficient disk space ($available_space KB available, $required_space KB required)"
    exit 1
fi

# Print pipeline info with explicit paths for debugging
echo "====== Mosquito RNA-Seq Pipeline ======"
echo "Repository root: $REPO_ROOT"
echo "Data directory: $data_base"
echo "Results directory: $result_base" 
echo "Logs directory: $logs_base"
echo "======================================"

# Check if data directory exists
if [[ ! -d "$data_base" ]]; then
    echo "Data directory not found: $data_base"
    echo "Please make sure this directory exists and contains read files."
    echo "Directory structure from repo root:"
    ls -la $REPO_ROOT
    exit 1
fi

# Find R1 and R2 files and pair them by sample name
declare -A r1_files r2_files
echo "Scanning for read files in $data_base ..."

# Define file lists for storing input/output files
r1_list="${temp_dir}/r1_files.txt"
r2_list="${temp_dir}/r2_files.txt"
trimmed_r1_list="${temp_dir}/trimmed_r1_files.txt"
trimmed_r2_list="${temp_dir}/trimmed_r2_files.txt"

# Initialize file lists
> "$r1_list"
> "$r2_list"
> "$trimmed_r1_list"
> "$trimmed_r2_list"

# Find and store R1 files
for file in "$data_base"/*R1*.fastq.gz "$data_base"/*_1.fastq.gz; do
    if [[ -s "$file" ]]; then
        # Extract sample name from filename
        sample=$(basename "$file" | sed -E 's/_R1.*|_1\.fastq\.gz//')
        r1_files["$sample"]="$file"
        echo "Found R1 file for sample $sample: $file"
    fi
done

# Find and store R2 files
for file in "$data_base"/*R2*.fastq.gz "$data_base"/*_2.fastq.gz; do
    if [[ -s "$file" ]]; then
        # Extract sample name from filename
        sample=$(basename "$file" | sed -E 's/_R2.*|_2\.fastq\.gz//')
        r2_files["$sample"]="$file"
        echo "Found R2 file for sample $sample: $file"
    fi
done

echo "Found ${#r1_files[@]} R1 files and ${#r2_files[@]} R2 files"

# Get SCRIPT_DIR for subsequent scripts
SCRIPT_DIR="${REPO_ROOT}/pipelines/transcriptome_assembly/bin"
if [[ ! -d "$SCRIPT_DIR" ]]; then
    echo "ERROR: Script directory not found: $SCRIPT_DIR"
    exit 1
fi

# Process paired files and submit trimming jobs
echo "Processing paired read files..."
sample_count=0
trim_dependencies=""

# Write sample metadata to CSV for downstream
metadata_file="${result_base}/sample_metadata.csv"
echo "sample,r1_file,r2_file,trimmed_r1,trimmed_r2" > "$metadata_file"

# Process only a subset for testing if in debug mode
max_samples=1000
if [[ "$debug_mode" == true ]]; then
    max_samples=2
    echo "DEBUG MODE: Processing only $max_samples samples"
fi

# Iterate through R1 files and find matching R2 files
for sample in "${!r1_files[@]}"; do
    r1="${r1_files[$sample]}"
    
    if [[ -n "${r2_files[$sample]}" ]]; then
        r2="${r2_files[$sample]}"
        
        if [[ $sample_count -lt $max_samples ]]; then
            echo "Processing sample pair: $sample"
            echo "  R1: $r1"
            echo "  R2: $r2"
            
            # Calculate output filenames for trimming
            trimmed_r1="${result_base}/trimmed/${sample}_R1_trimmed.fastq.gz"
            trimmed_r2="${result_base}/trimmed/${sample}_R2_trimmed.fastq.gz"
            
            # Create trimmed directory
            mkdir -p "${result_base}/trimmed"
            
            # Add to metadata
            echo "$sample,$r1,$r2,$trimmed_r1,$trimmed_r2" >> "$metadata_file"
            
            # Add to file lists
            echo "$r1" >> "$r1_list"
            echo "$r2" >> "$r2_list"
            echo "$trimmed_r1" >> "$trimmed_r1_list" 
            echo "$trimmed_r2" >> "$trimmed_r2_list"
            
            # Submit trimming job
            trim_log="${logs_base}/trim_${sample}.log"
            
            trim_job_id=$(sbatch --parsable \
                --job-name="trim_${sample}" \
                --output="${logs_base}/trim_${sample}_%j.out" \
                --error="${logs_base}/trim_${sample}_%j.err" \
                "${SCRIPT_DIR}/01_trim.sh" "$r1" "$r2" "$trimmed_r1" "$trimmed_r2" "$sample")
            
            echo "Submitted trimming job for $sample: $trim_job_id"
            
            # Add to dependencies
            if [[ -z "$trim_dependencies" ]]; then
                trim_dependencies="afterok:$trim_job_id"
            else
                trim_dependencies="$trim_dependencies:$trim_job_id"
            fi
            
            ((sample_count++))
        fi
    else
        echo "Warning: No matching R2 file found for sample $sample (R1: $r1)"
        echo "This sample will be skipped"
    fi
done

echo "Processing $sample_count paired samples"

if [[ $sample_count -eq 0 ]]; then
    echo "Error: No valid sample pairs found. Exiting."
    exit 1
fi

# Submit merge job
echo "Submitting merge job..."

merge_job_id=$(sbatch --parsable \
    --job-name="merge" \
    --dependency="$trim_dependencies" \
    --output="${logs_base}/merge_%j.out" \
    --error="${logs_base}/merge_%j.err" \
    "${SCRIPT_DIR}/02_merge.sh" "$trimmed_r1_list" "$trimmed_r2_list" "${result_base}/merged_reads_R1.fastq.gz" "${result_base}/merged_reads_R2.fastq.gz")

echo "Submitted merge job: $merge_job_id"

# Submit normalization job
echo "Submitting normalization job..."

norm_job_id=$(sbatch --parsable \
    --job-name="normalize" \
    --dependency="afterok:$merge_job_id" \
    --output="${logs_base}/normalize_%j.out" \
    --error="${logs_base}/normalize_%j.err" \
    "${SCRIPT_DIR}/03_normalize.sh" "${result_base}/merged_reads_R1.fastq.gz" "${result_base}/merged_reads_R2.fastq.gz" "${result_base}/normalized_reads")

echo "Submitted normalization job: $norm_job_id"  

# Submit assembly job
echo "Submitting assembly job..."

assembly_job_id=$(sbatch --parsable \
    --job-name="assembly" \
    --dependency="afterok:$norm_job_id" \
    --output="${logs_base}/assembly_%j.out" \
    --error="${logs_base}/assembly_%j.err" \
    "${SCRIPT_DIR}/04_assemble.sh" "${result_base}/normalized_reads" "${result_base}/assembly")

echo "Submitted assembly job: $assembly_job_id"

# Submit busco job
echo "Submitting BUSCO job..."

busco_job_id=$(sbatch --parsable \
    --job-name="busco" \
    --dependency="afterok:$assembly_job_id" \
    --output="${logs_base}/busco_%j.out" \
    --error="${logs_base}/busco_%j.err" \
    "${SCRIPT_DIR}/06_busco.sh" "${result_base}/assembly/Trinity.fasta" "${result_base}/busco")

echo "Submitted BUSCO job: $busco_job_id"

# Print job summary
echo "====== Job Summary ======"
echo "Trimming jobs: $trim_dependencies"
echo "Merge job: $merge_job_id"
echo "Normalization job: $norm_job_id"
echo "Assembly job: $assembly_job_id"
echo "BUSCO job: $busco_job_id"
echo "========================="

# Calculate and print pipeline runtime
end_time=$(date +%s)
runtime=$((end_time - start_time))
echo "Pipeline setup completed in $runtime seconds"
echo "Jobs are now running. Check job status with 'squeue -u $USER'"
