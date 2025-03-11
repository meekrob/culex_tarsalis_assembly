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
pairs_dir="${result_base}/03_pairs"
norm_dir="${result_base}/04_normalized"
assembly_dir="${result_base}/05_assembly"
busco_dir="${result_base}/06_busco"

# Create these directories
mkdir -p "$trimmed_dir"
mkdir -p "$merged_dir"
mkdir -p "$pairs_dir"
mkdir -p "$norm_dir"
mkdir -p "$assembly_dir"
mkdir -p "$busco_dir"

# Create specific log directories
trim_logs="${logs_base}/01_trimming"
merge_logs="${logs_base}/02_merge"
pairs_logs="${logs_base}/03_pairs"
norm_logs="${logs_base}/04_normalization"
assembly_logs="${logs_base}/05_assembly"
busco_logs="${logs_base}/06_busco"

# Create log directories
mkdir -p "$trim_logs"
mkdir -p "$merge_logs"
mkdir -p "$pairs_logs"
mkdir -p "$norm_logs"
mkdir -p "$assembly_logs"
mkdir -p "$busco_logs"

# Create summary file
summary_file="${logs_base}/pipeline_summary.csv"
echo "Step,Sample,Metric,Value" > "$summary_file"

# Display run info
echo "====== Mosquito RNA-Seq Pipeline ======"
echo "Data directory: $data_base"
echo "Results directory: $result_base"
echo "Logs directory: $logs_base"
if [[ "$debug_mode" == true ]]; then
    echo "Running in DEBUG mode - will skip steps with existing outputs"
fi
echo "======================================"

# Find input files
if [[ -d "$data_base" ]]; then
    # Find all valid input read files (non-empty files with R1 or R2 in their names)
    mapfile -t r1_files < <(find "$data_base" -name "*R1*" -not -empty | sort)
    mapfile -t r2_files < <(find "$data_base" -name "*R2*" -not -empty | sort)
    
    if [[ ${#r1_files[@]} -eq 0 || ${#r2_files[@]} -eq 0 ]]; then
        echo "No valid read files found in $data_base"
        exit 1
    fi
    
    echo "Found ${#r1_files[@]} R1 files and ${#r2_files[@]} R2 files"
else
    echo "Data directory not found: $data_base"
    exit 1
fi

# Create temporary files for file lists
r1_list="${temp_dir}/r1_files.txt"
r2_list="${temp_dir}/r2_files.txt"
trimmed_r1_list="${temp_dir}/trimmed_r1_files.txt"
trimmed_r2_list="${temp_dir}/trimmed_r2_files.txt"

# Initialize file lists
> "$r1_list"
> "$r2_list"
> "$trimmed_r1_list"
> "$trimmed_r2_list"

# Step 1: Submit trimming jobs for all input files
echo "Submitting trimming jobs..."
declare -a trim_job_ids=()

for i in "${!r1_files[@]}"; do
    r1="${r1_files[$i]}"
    r2="${r2_files[$i]}"
    
    # Extract sample name from file path
    filename=$(basename "$r1")
    sample_name="${filename%%_*}"
    
    # Define output files
    out_r1="${trimmed_dir}/${sample_name}_R1_trimmed.fastq.gz"
    out_r2="${trimmed_dir}/${sample_name}_R2_trimmed.fastq.gz"
    
    # Add to file lists
    echo "$r1" >> "$r1_list"
    echo "$r2" >> "$r2_list"
    echo "$out_r1" >> "$trimmed_r1_list"
    echo "$out_r2" >> "$trimmed_r2_list"
    
    # Submit trimming job
    trim_cmd="sbatch --parsable --job-name=trim_${sample_name} --output=${trim_logs}/trim_${sample_name}_%j.out --error=${trim_logs}/trim_${sample_name}_%j.err"
    trim_job_id=$(eval $trim_cmd bin/01_trimming.sh "$r1" "$r2" "$out_r1" "$out_r2" "$sample_name" "$trim_logs" "$summary_file" "$debug_mode")
    
    if [[ -n "$trim_job_id" ]]; then
        trim_job_ids+=("$trim_job_id")
        echo "Submitted trimming job for $sample_name: $trim_job_id"
    else
        echo "Error: Failed to submit trimming job for $sample_name"
        exit 1
    fi
done

# Create dependency string for merge jobs
trim_dependency=""
if [[ ${#trim_job_ids[@]} -gt 0 ]]; then
    trim_dependency="--dependency=afterok:$(IFS=:; echo "${trim_job_ids[*]}")"
fi

# Step 2: Submit merge jobs
echo "Submitting merge jobs..."

# Define output files for merged reads
merged_r1="${merged_dir}/merged_R1.fastq.gz"
merged_r2="${merged_dir}/merged_R2.fastq.gz"

# Submit merge job for R1 files
merge_r1_cmd="sbatch --parsable --job-name=merge_R1 --output=${merge_logs}/merge_R1_%j.out --error=${merge_logs}/merge_R1_%j.err $trim_dependency"
merge_r1_job_id=$(eval $merge_r1_cmd bin/02_merge.sh "$trimmed_r1_list" "$merged_r1" "R1" "$merge_logs" "$debug_mode" "$summary_file")

if [[ -n "$merge_r1_job_id" ]]; then
    echo "Submitted merge job for R1: $merge_r1_job_id"
else
    echo "Error: Failed to submit merge job for R1"
    exit 1
fi

# Submit merge job for R2 files
merge_r2_cmd="sbatch --parsable --job-name=merge_R2 --output=${merge_logs}/merge_R2_%j.out --error=${merge_logs}/merge_R2_%j.err $trim_dependency"
merge_r2_job_id=$(eval $merge_r2_cmd bin/02_merge.sh "$trimmed_r2_list" "$merged_r2" "R2" "$merge_logs" "$debug_mode" "$summary_file")

if [[ -n "$merge_r2_job_id" ]]; then
    echo "Submitted merge job for R2: $merge_r2_job_id"
else
    echo "Error: Failed to submit merge job for R2"
    exit 1
fi

# Step 3: Add pair checking step
echo "Submitting pair checking job..."

# Set output files for fixed paired reads
fixed_r1="${pairs_dir}/fixed_R1.fastq.gz"
fixed_r2="${pairs_dir}/fixed_R2.fastq.gz"

# Make pair checking job dependent on both merge jobs
check_pairs_dependency="--dependency=afterok:${merge_r1_job_id}:${merge_r2_job_id}"

# Submit pair checking job
check_pairs_cmd="sbatch --parsable --job-name=check_pairs --output=${pairs_logs}/check_pairs_%j.out --error=${pairs_logs}/check_pairs_%j.err $check_pairs_dependency"
check_pairs_job_id=$(eval $check_pairs_cmd bin/03_check_pairs.sh "$merged_r1" "$merged_r2" "$fixed_r1" "$fixed_r2" "$pairs_logs" "$summary_file" "$debug_mode")

if [[ -n "$check_pairs_job_id" ]]; then
    echo "Submitted pair checking job: $check_pairs_job_id"
else
    echo "Error: Failed to submit pair checking job"
    exit 1
fi

# Step 4: Add normalization step
echo "Submitting read normalization job..."

# Set output files for normalized reads
norm_r1="${norm_dir}/normalized_R1.fastq.gz"
norm_r2="${norm_dir}/normalized_R2.fastq.gz"

# Make normalization job dependent on pair checking job
norm_dependency="--dependency=afterok:${check_pairs_job_id}"

# Submit normalization job
norm_cmd="sbatch --parsable --job-name=normalize --output=${norm_logs}/normalize_%j.out --error=${norm_logs}/normalize_%j.err $norm_dependency"
norm_job_id=$(eval $norm_cmd bin/04_read_normalization.sh "$fixed_r1" "$fixed_r2" "$norm_r1" "$norm_r2" "$norm_logs" "$summary_file" "$debug_mode")

if [[ -n "$norm_job_id" ]]; then
    echo "Submitted normalization job: $norm_job_id"
else
    echo "Error: Failed to submit normalization job"
    exit 1
fi

# Step 5: Submit assembly job
echo "Submitting assembly job..."

# Make assembly job dependent on normalization job
assembly_dependency="--dependency=afterok:${norm_job_id}"

# Submit assembly job
assembly_cmd="sbatch --parsable --job-name=assembly --output=${assembly_logs}/assembly_%j.out --error=${assembly_logs}/assembly_%j.err $assembly_dependency"
assembly_job_id=$(eval $assembly_cmd bin/05_assembly.sh "$norm_r1" "$norm_r2" "$assembly_dir" "$assembly_logs" "$debug_mode" "$summary_file")

if [[ -n "$assembly_job_id" ]]; then
    echo "Submitted assembly job: $assembly_job_id"
else
    echo "Error: Failed to submit assembly job"
    exit 1
fi

# Step 6: Submit BUSCO job
echo "Submitting quality assessment job..."

# Submit BUSCO job
busco_cmd="sbatch --parsable --job-name=busco --output=${busco_logs}/busco_%j.out --error=${busco_logs}/busco_%j.err --dependency=afterok:${assembly_job_id}"
busco_job_id=$(eval $busco_cmd bin/06_busco.sh "$assembly_dir/transcripts.fasta" "$busco_dir" "$busco_logs" "$debug_mode" "$summary_file")

if [[ -n "$busco_job_id" ]]; then
    echo "Submitted BUSCO job: $busco_job_id"
else
    echo "Error: Failed to submit BUSCO job"
    exit 1
fi

echo "All jobs submitted. Pipeline will run with the following job IDs:"
echo "  Trimming: ${trim_job_ids[*]}"
echo "  Merging: $merge_r1_job_id, $merge_r2_job_id"
echo "  Pair checking: $check_pairs_job_id"
echo "  Normalization: $norm_job_id"
echo "  Assembly: $assembly_job_id"
echo "  BUSCO: $busco_job_id"

# Calculate total runtime
end_time=$(date +%s)
total_runtime=$((end_time - start_time))
echo "Pipeline setup completed in $total_runtime seconds"
echo "Check job status with: squeue -u $USER"
