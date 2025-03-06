#!/bin/bash


# main.sh - Master control script for mosquito RNA-seq pipeline
# This script identifies input files, sets up directories, and manages job dependencies

#SBATCH --job-name=main
#SBATCH --output=./logs/main_%j.out
#SBATCH --error=./logs/main_%j.err

# Source conda
source ~/.bashrc

# Define base directories
current_dir=$(pwd)
data_base="${current_dir}/data"
result_base="${current_dir}/results"
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

# Get start time for timing
start_time=$(date +%s)

# Debug mode flag (set to true to skip steps if output exists)
debug_mode=false

# Check for command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --debug|-d)
            debug_mode=true
            shift
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Define sample names and input files
sample_names=(
    "Cx-Adult-41"
    "Cx-Adult-54"
    # Add more samples as needed
)

# Submit trimming jobs for each sample
trim_job_ids=()
for sample_name in "${sample_names[@]}"; do
    r1="${data_base}/raw/${sample_name}_R1.fastq.gz"
    r2="${data_base}/raw/${sample_name}_R2.fastq.gz"
    
    # Skip if input files don't exist
    if [[ ! -f "$r1" || ! -f "$r2" ]]; then
        echo "Warning: Input files not found for $sample_name, skipping."
        continue
    fi
    
    # Define output files
    out_r1="${trimmed_dir}/${sample_name}_R1_trimmed.fastq.gz"
    out_r2="${trimmed_dir}/${sample_name}_R2_trimmed.fastq.gz"
    
    # Submit trimming job
    trim_job_id=$(sbatch --parsable \
                 --job-name="fastp_${sample_name}" \
                 --output="${trim_logs}/fastp_${sample_name}_%j.out" \
                 --error="${trim_logs}/fastp_${sample_name}_%j.err" \
                 bin/01_fastp.sh "$r1" "$r2" "$out_r1" "$out_r2" "$sample_name" "$trim_logs" "$debug_mode")
    
    # Add job ID to array if successful
    if [[ -n "$trim_job_id" ]]; then
        trim_job_ids+=($trim_job_id)
        echo "Submitted trimming job for $sample_name: $trim_job_id"
    else
        echo "Error: Failed to submit trimming job for $sample_name"
    fi
done

# Create dependency string for merge job
if [[ ${#trim_job_ids[@]} -gt 0 ]]; then
    trim_dependency="--dependency=afterany:$(IFS=:; echo "${trim_job_ids[*]}")"
else
    trim_dependency=""
    echo "Warning: No trimming jobs submitted. Merge job will run without dependencies."
fi

# Create lists of trimmed files for merging
r1_trimmed_list="${temp_dir}/r1_trimmed_files.txt"
r2_trimmed_list="${temp_dir}/r2_trimmed_files.txt"

# Clear existing lists
> "$r1_trimmed_list"
> "$r2_trimmed_list"

# Add trimmed files to lists
for sample_name in "${sample_names[@]}"; do
    trimmed_r1="${trimmed_dir}/${sample_name}_R1_trimmed.fastq.gz"
    trimmed_r2="${trimmed_dir}/${sample_name}_R2_trimmed.fastq.gz"
    
    # Check if files exist before adding to list
    if [[ -f "$trimmed_r1" ]]; then
        echo "$trimmed_r1" >> "$r1_trimmed_list"
    else
        echo "Warning: Trimmed R1 file not found for $sample_name: $trimmed_r1"
    fi
    
    if [[ -f "$trimmed_r2" ]]; then
        echo "$trimmed_r2" >> "$r2_trimmed_list"
    else
        echo "Warning: Trimmed R2 file not found for $sample_name: $trimmed_r2"
    fi
done

# Define merged output files
merged_r1="${merged_dir}/all_samples_R1.fastq.gz"
merged_r2="${merged_dir}/all_samples_R2.fastq.gz"

# Submit merge job
merge_cmd="sbatch --parsable --job-name=merge --output=${merge_logs}/merge_%j.out --error=${merge_logs}/merge_%j.err"
if [[ -n "$trim_dependency" ]]; then
    merge_cmd="$merge_cmd $trim_dependency"
fi
merge_job_id=$(eval $merge_cmd bin/02_merge.sh "$r1_trimmed_list" "$r2_trimmed_list" "$merged_r1" "$merged_r2" "$merge_logs" "$debug_mode")

if [[ -n "$merge_job_id" ]]; then
    echo "Submitted merge job: $merge_job_id"
else
    echo "Error: Failed to submit merge job"
    exit 1
fi

# Submit assembly job
assembly_cmd="sbatch --parsable --job-name=rnaspades --output=${assembly_logs}/assembly_%j.out --error=${assembly_logs}/assembly_%j.err --dependency=afterany:${merge_job_id}"
assembly_job_id=$(eval $assembly_cmd bin/03_assembly.sh "$merged_r1" "$merged_r2" "$assembly_dir" "$assembly_logs" "$debug_mode")

if [[ -n "$assembly_job_id" ]]; then
    echo "Submitted assembly job: $assembly_job_id"
else
    echo "Error: Failed to submit assembly job"
    exit 1
fi

# Submit BUSCO job
busco_cmd="sbatch --parsable --job-name=busco --output=${busco_logs}/busco_%j.out --error=${busco_logs}/busco_%j.err --dependency=afterany:${assembly_job_id}"
busco_job_id=$(eval $busco_cmd bin/04_busco.sh "$assembly_dir/transcripts.fasta" "$busco_dir" "$busco_logs" "$debug_mode")

if [[ -n "$busco_job_id" ]]; then
    echo "Submitted BUSCO job: $busco_job_id"
else
    echo "Error: Failed to submit BUSCO job"
    exit 1
fi

# Submit rnaQuast job
rnaquast_cmd="sbatch --parsable --job-name=rnaquast --output=${rnaquast_logs}/rnaquast_%j.out --error=${rnaquast_logs}/rnaquast_%j.err --dependency=afterany:${assembly_job_id}"
rnaquast_job_id=$(eval $rnaquast_cmd bin/04_rnaquast.sh "$assembly_dir/transcripts.fasta" "$rnaquast_dir" "$rnaquast_logs" "$debug_mode")

if [[ -n "$rnaquast_job_id" ]]; then
    echo "Submitted rnaQuast job: $rnaquast_job_id"
else
    echo "Error: Failed to submit rnaQuast job"
    exit 1
fi

# Submit visualization job
viz_cmd="sbatch --parsable --job-name=visualize --output=${viz_logs}/viz_%j.out --error=${viz_logs}/viz_%j.err --dependency=afterany:${busco_job_id}:${rnaquast_job_id}"
viz_job_id=$(eval $viz_cmd bin/05_visualize.sh "$busco_dir" "$rnaquast_dir" "$viz_dir" "$viz_logs" "$debug_mode")

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
