#!/bin/bash

# main.sh - Master control script for repeat annotation pipeline
# This script sets up directories and manages job dependencies

#SBATCH --job-name=main_repeat
#SBATCH --output=./logs/repeat_annotator/main_%j.out
#SBATCH --error=./logs/repeat_annotator/main_%j.err

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
repeat_lib="${REPO_ROOT}/data/repeats/mosquito_repeat_lib.fasta"
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
echo "Repeat library: $repeat_lib"
echo "Results base: $result_base"
echo "Logs base: $logs_base"

# Create output directories
mkdir -p "$result_base"
mkdir -p "$logs_base"
mkdir -p "$temp_dir"

# Create summary file
summary_file="${logs_base}/pipeline_summary.csv"
echo "Step,Sample,Metric,Value" > "$summary_file"

# Display run info
echo "====== Mosquito Repeat Annotation Pipeline ======"
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

# Check if repeat library exists
if [[ ! -f "$repeat_lib" ]]; then
    echo "Repeat library not found: $repeat_lib"
    echo "Attempting to create repeat library directory"
    mkdir -p "$(dirname "$repeat_lib")"
    
    echo "Please make sure to create a repeat library before running RepeatMasker."
    echo "See instructions in the README.md for creating a repeat library."
    exit 1
fi

echo "Using genome file: $genome_file"

# Define genome name (from file name)
genome_name=$(basename "$genome_file" | sed 's/\.[^.]*$//')
echo "Using genome name: $genome_name"

# Submit RepeatMasker job
echo "Submitting RepeatMasker job..."
repeatmasker_cmd="sbatch --parsable --job-name=repeatmasker_${genome_name} --output=${logs_base}/repeatmasker_${genome_name}_%j.out --error=${logs_base}/repeatmasker_${genome_name}_%j.err"
repeatmasker_job_id=$(eval $repeatmasker_cmd $SCRIPT_DIR/repeatmasker.sh "$genome_file" "$repeat_lib" "$result_base" "$logs_base" "$debug_mode" "$summary_file")

if [[ -n "$repeatmasker_job_id" ]]; then
    echo "Submitted RepeatMasker job: $repeatmasker_job_id"
else
    echo "Error: Failed to submit RepeatMasker job"
    exit 1
fi

echo "All jobs submitted successfully!"
end_time=$(date +%s)
runtime=$((end_time - start_time))
echo "Total setup time: $runtime seconds" 