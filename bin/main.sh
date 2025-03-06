#!/bin/bash


# main.sh - Master control script for mosquito RNA-seq pipeline
# This script identifies input files, sets up directories, and manages job dependencies

#SBATCH --job-name=main
#SBATCH --output=./logs/main_%j.out
#SBATCH --error=./logs/main_%j.err

# Source conda
source ~/.bashrc

# Source parameters file
source config/parameters.txt

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
        --debug)
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
    
    trimmed_r1="${trimmed_dir}/${sample_name}_R1_trimmed.fastq.gz"
    trimmed_r2="${trimmed_dir}/${sample_name}_R2_trimmed.fastq.gz"
    
    # Submit trimming job
    trim_job_id=$(sbatch --parsable \
                --partition="${fastp_partition}" \
                --time="${fastp_time}" \
                --nodes=${fastp_nodes} \
                --cpus-per-task=${fastp_cpu_cores_per_task} \
                --mem="${fastp_mem}" \
                --output="${trim_logs}/fastp_%j.out" \
                --error="${trim_logs}/fastp_%j.err" \
                bin/01_fastp.sh "$r1" "$r2" "$trimmed_r1" "$trimmed_r2" "$sample_name" "$trim_logs" "$debug_mode")
    
    trim_job_ids+=($trim_job_id)
    echo "Submitted trimming job for $sample_name: $trim_job_id"
done

# Create dependency string for all trimming jobs
trim_dependency=""
if [[ ${#trim_job_ids[@]} -gt 0 ]]; then
    trim_dependency="afterany:$(IFS=:; echo "${trim_job_ids[*]}")"
fi

# Create lists of trimmed files for merging
r1_trimmed_list="${temp_dir}/r1_trimmed_files.txt"
r2_trimmed_list="${temp_dir}/r2_trimmed_files.txt"

# Clear existing lists if they exist
> "$r1_trimmed_list"
> "$r2_trimmed_list"

# Add all trimmed files to the lists
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
merge_job_id=$(sbatch --parsable \
              --partition="${cat_partition}" \
              --time="${cat_time}" \
              --nodes=${cat_nodes} \
              --cpus-per-task=${cat_cpu_cores_per_task} \
              --mem="${cat_mem}" \
              --output="${merge_logs}/merge_%j.out" \
              --error="${merge_logs}/merge_%j.err" \
              --dependency=$trim_dependency \
              bin/02_merge.sh "$r1_trimmed_list" "$r2_trimmed_list" "$merged_r1" "$merged_r2" "$merge_logs" "$debug_mode")

echo "Submitted merge job: $merge_job_id"

# Submit assembly job
assembly_job_id=$(sbatch --parsable \
                --partition="${rnaSpades_partition}" \
                --time="${rnaSpades_time}" \
                --nodes=${rnaSpades_nodes} \
                --cpus-per-task=${rnaSpades_cpu_cores_per_task} \
                --mem="${rnaSpades_mem}" \
                --output="${assembly_logs}/assembly_%j.out" \
                --error="${assembly_logs}/assembly_%j.err" \
                --dependency=afterany:${merge_job_id} \
                bin/03_assembly.sh "$merged_r1" "$merged_r2" "$assembly_dir" "$assembly_logs" "$debug_mode")

echo "Submitted assembly job: $assembly_job_id"

# Submit BUSCO job
busco_job_id=$(sbatch --parsable \
              --partition="${busco_partition}" \
              --time="${busco_time}" \
              --nodes=${busco_nodes} \
              --cpus-per-task=${busco_cpu_cores_per_task} \
              --mem="${busco_mem}" \
              --output="${busco_logs}/busco_%j.out" \
              --error="${busco_logs}/busco_%j.err" \
              --dependency=afterany:${assembly_job_id} \
              bin/04_busco.sh "$assembly_dir/transcripts.fasta" "$busco_dir" "$busco_logs" "$debug_mode")

echo "Submitted BUSCO job: $busco_job_id"

# Submit rnaQuast job
rnaquast_job_id=$(sbatch --parsable \
                --partition="${rnaQuast_partition}" \
                --time="${rnaQuast_time}" \
                --nodes=${rnaQuast_nodes} \
                --cpus-per-task=${rnaQuast_cpu_cores_per_task} \
                --mem="${rnaQuast_mem}" \
                --output="${rnaquast_logs}/rnaquast_%j.out" \
                --error="${rnaquast_logs}/rnaquast_%j.err" \
                --dependency=afterany:${assembly_job_id} \
                bin/04_rnaquast.sh "$assembly_dir/transcripts.fasta" "$rnaquast_dir" "$rnaquast_logs" "$debug_mode")

echo "Submitted rnaQuast job: $rnaquast_job_id"

# Submit visualization job
viz_job_id=$(sbatch --parsable \
            --partition="${visualize_partition}" \
            --time="${visualize_time}" \
            --nodes=${visualize_nodes} \
            --cpus-per-task=${visualize_cpu_cores_per_task} \
            --mem="${visualize_mem}" \
            --output="${viz_logs}/viz_%j.out" \
            --error="${viz_logs}/viz_%j.err" \
            --dependency=afterany:${busco_job_id}:${rnaquast_job_id} \
            bin/05_visualize.sh "$busco_dir" "$rnaquast_dir" "$viz_dir" "$viz_logs" "$debug_mode")

echo "Submitted visualization job: $viz_job_id"

echo "All jobs submitted. Pipeline will run with the following job IDs:"
echo "  Trimming: ${trim_job_ids[*]}"
echo "  Merging: $merge_job_id"
echo "  Assembly: $assembly_job_id"
echo "  BUSCO: $busco_job_id"
echo "  rnaQuast: $rnaquast_job_id"
echo "  Visualization: $viz_job_id"
