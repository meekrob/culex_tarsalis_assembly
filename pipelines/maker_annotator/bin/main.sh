#!/bin/bash

# main.sh - Master control script for genome annotation pipeline
# This script sets up directories and manages job dependencies

#SBATCH --job-name=main_maker
#SBATCH --output=./logs/maker_annotator/main_%j.out
#SBATCH --error=./logs/maker_annotator/main_%j.err

# Get start time for timing
start_time=$(date +%s)

# Source conda
source ~/.bashrc

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

# Get the repository root directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PIPELINE_DIR="$( dirname "$SCRIPT_DIR" )"
PIPELINE_NAME="$( basename "$PIPELINE_DIR" )"
REPO_ROOT="$( cd "$SCRIPT_DIR/../../.." && pwd )"

# Define standardized directories
genome_dir="${REPO_ROOT}/data/genome"
genome_base="${1:-$genome_dir}"
result_base="${2:-${REPO_ROOT}/results/${PIPELINE_NAME}}"
logs_base="${REPO_ROOT}/logs/${PIPELINE_NAME}"
temp_dir="${REPO_ROOT}/temp/${PIPELINE_NAME}"

# Debug all directory paths
echo "Running pipeline: $PIPELINE_NAME"
echo "Repository root: $REPO_ROOT"
echo "Script directory: $SCRIPT_DIR"
echo "Pipeline directory: $PIPELINE_DIR"
echo "Genome directory path: $genome_dir"
echo "Genome base: $genome_base"
echo "Results base: $result_base"
echo "Logs base: $logs_base"

# Create output directories
mkdir -p "$result_base"
mkdir -p "$logs_base"
mkdir -p "$temp_dir"

# Define specific output and log directories
braker_dir="${result_base}/braker"
braker_logs="${logs_base}/braker"

# Create these directories
mkdir -p "$braker_dir"
mkdir -p "$braker_logs"

# Create summary file
summary_file="${logs_base}/pipeline_summary.csv"
echo "Step,Sample,Metric,Value" > "$summary_file"

# Display run info
echo "====== Mosquito Genome Annotation Pipeline ======"
echo "Genome directory: $genome_base"
echo "Results directory: $result_base"
echo "Logs directory: $logs_base"
if [[ "$debug_mode" == true ]]; then
    echo "Running in DEBUG mode - will skip steps with existing outputs"
fi
echo "======================================"

# Check if genome directory exists
if [[ ! -d "$genome_base" ]]; then
    echo "Genome directory not found: $genome_base"
    echo "Please make sure this directory exists and contains genome files."
    echo "Directory structure from repo root:"
    find "$REPO_ROOT" -type d -maxdepth 3 | sort
    exit 1
fi

# Find genome fasta file
genome_file=$(find "$genome_base" -name "*.fa" -o -name "*.fasta" | head -n 1)
if [[ -z "$genome_file" ]]; then
    echo "No genome FASTA file found in $genome_base"
    echo "Available files in directory:"
    ls -la "$genome_base"
    exit 1
fi

# Find transcriptome BAM file
bam_file="${REPO_ROOT}/data/transcriptome.bam"
if [[ ! -f "$bam_file" ]]; then
    echo "Transcriptome BAM file not found: $bam_file"
    echo "Please make sure this file exists."
    exit 1
fi

echo "Using genome file: $genome_file"
echo "Using BAM file: $bam_file"

# Define species name (from directory name or default)
species_name=$(basename "$genome_base" | sed 's/[^a-zA-Z0-9]/_/g')
species_name=${species_name:-"mosquito"}

echo "Using species name: $species_name"

# Submit BRAKER job
echo "Submitting BRAKER job..."
braker_cmd="sbatch --parsable --job-name=braker_${species_name} --output=${braker_logs}/braker_${species_name}_%j.out --error=${braker_logs}/braker_${species_name}_%j.err"
braker_job_id=$(eval $braker_cmd $SCRIPT_DIR/braker.sh "$genome_file" "$bam_file" "$braker_dir" "$braker_logs" "$debug_mode" "$summary_file" "$species_name")

if [[ -n "$braker_job_id" ]]; then
    echo "Submitted BRAKER job: $braker_job_id"
else
    echo "Error: Failed to submit BRAKER job"
    exit 1
fi

echo "All jobs submitted successfully!"
end_time=$(date +%s)
runtime=$((end_time - start_time))
echo "Total setup time: $runtime seconds" 