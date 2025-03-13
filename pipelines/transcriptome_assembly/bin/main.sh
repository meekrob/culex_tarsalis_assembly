#!/bin/bash


# main.sh - Master control script for mosquito RNA-seq pipeline
# This script identifies input files, sets up directories, and manages job dependencies

#SBATCH --job-name=transcriptome
#SBATCH --output=transcriptome_%j.out
#SBATCH --error=transcriptome_%j.err

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

# Rest of script continues here
