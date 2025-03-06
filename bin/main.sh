#!/bin/bash


# main.sh - Master control script for mosquito RNA-seq pipeline
# This script identifies input files, sets up directories, and manages job dependencies

#SBATCH --job-name=main
#SBATCH --output=./logs/main_%j.out
#SBATCH --error=./logs/main_%j.err

# Source conda
source ~/.bashrc

# Default values - use current directory as base
current_dir=$(pwd)
raw_reads_dir="${current_dir}/data/raw_reads"
result_base="${current_dir}/results"
logs_base="${current_dir}/logs"  # Changed to be at the same level as results
draft_transcriptome=""
debug_mode=false

# Parse command line arguments
while getopts ":R:dh" opt; do
  case ${opt} in
    R )
      draft_transcriptome=$OPTARG
      ;;
    d )
      debug_mode=true
      echo "Debug mode enabled: Will check for existing output files and skip completed steps."
      ;;
    h )
      echo "Usage: $0 [-R /path/to/reference/transcriptome] [-d] [raw_reads_dir] [result_base] [logs_base]"
      echo "  -R: Path to reference transcriptome (optional)"
      echo "  -d: Debug mode - check for existing output files and skip completed steps"
      echo "  raw_reads_dir: Directory with raw fastq files (default: ./data/raw_reads)"
      echo "  result_base: Base directory for all results (default: ./results)"
      echo "  logs_base: Base directory for all logs (default: ./logs)"
      exit 0
      ;;
    \? )
      echo "Invalid option: -$OPTARG" 1>&2
      exit 1
      ;;
    : )
      echo "Option -$OPTARG requires an argument." 1>&2
      exit 1
      ;;
  esac
done
shift $((OPTIND -1))

# Override defaults with positional arguments if provided
if [ "$1" != "" ]; then
  raw_reads_dir=$1
fi
if [ "$2" != "" ]; then
  result_base=$2
fi
if [ "$3" != "" ]; then
  logs_base=$3
fi

# Create logs directory before sourcing parameters to ensure SLURM output has a place to go
mkdir -p "${logs_base}"

# Source parameters file
source config/parameters.txt

# Check if the conda environment exists and create it only if needed
if ! conda info --envs | grep -q "cellSquito"; then
    echo "Creating cellSquito conda environment..."
    conda env create -f config/cellSquito.yml -n cellSquito
else
    echo "cellSquito conda environment already exists"
fi

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

# Create improved log directory structure
trim_logs="${logs_base}/01_trimming"          # Logs for trimming
merge_logs="${logs_base}/02_merge"            # Logs for merging
assembly_logs="${logs_base}/03_assembly"      # Logs for assembly
busco_logs="${logs_base}/04_busco"            # Logs for BUSCO
rnaquast_logs="${logs_base}/04_rnaquast"      # Logs for rnaQuast
viz_logs="${logs_base}/05_visualization"      # Logs for visualization
summary_logs="${logs_base}/summaries"         # Logs for summary reports

# Create output and log directories
mkdir -p "$trimmed_dir" "$merged_dir" "$assembly_dir" "$busco_dir" "$rnaquast_dir" \
         "$draft_busco_dir" "$draft_rnaquast_dir" "$viz_dir"
mkdir -p "$trim_logs" "$merge_logs" "$assembly_logs" "$busco_logs" "$rnaquast_logs" \
         "$viz_logs" "$summary_logs"

# Create summary file
SUMMARY_FILE="${logs_base}/pipeline_summary.csv"
echo "Step,Sample,Metric,Value" > "$SUMMARY_FILE"
echo "Pipeline,Info,Start Time,$(date)" >> "$SUMMARY_FILE"
echo "Pipeline,Info,Working Directory,$current_dir" >> "$SUMMARY_FILE"

# Create temporary directory for file lists
temp_dir="${result_base}/temp"
mkdir -p "$temp_dir"
r1_trimmed_list="${temp_dir}/r1_trimmed_files.txt"
r2_trimmed_list="${temp_dir}/r2_trimmed_files.txt"
> "$r1_trimmed_list"  # Clear contents
> "$r2_trimmed_list"  # Clear contents

# Function to check job status
check_job_status() {
    local job_id=$1
    local job_name=$2
    local max_attempts=5
    local attempt=1
    local sleep_time=2
    
    while [[ $attempt -le $max_attempts ]]; do
        if squeue -j "$job_id" &>/dev/null; then
            echo "Job $job_name (ID: $job_id) successfully submitted and in queue."
            return 0
        fi
        
        echo "Waiting for job $job_name (ID: $job_id) to appear in queue (attempt $attempt/$max_attempts)..."
        sleep $sleep_time
        ((attempt++))
        ((sleep_time*=2))  # Exponential backoff
    done
    
    echo "Warning: Job $job_name (ID: $job_id) not found in queue after $max_attempts attempts."
    return 1
}

# Add this function to track and log failed jobs
track_failed_jobs() {
    local job_ids=("$@")
    local failed_jobs=()
    local failed_samples=()
    
    for ((i=0; i<${#job_ids[@]}; i++)); do
        local job_id="${job_ids[$i]}"
        if [[ "$job_id" != "debug_skipped" ]]; then
            local state=$(sacct -j "$job_id" --format=State -n | head -1 | tr -d ' ')
            if [[ "$state" == "FAILED" ]]; then
                failed_jobs+=("$job_id")
                failed_samples+=("${samples[$i]}")
                
                # Log the failure
                echo "Job $job_id (Sample: ${samples[$i]}) failed" >> "$logs_base/failed_jobs.log"
                echo "Failure time: $(date)" >> "$logs_base/failed_jobs.log"
                
                # Add to summary file
                echo "Trimming,${samples[$i]},Status,Failed" >> "$SUMMARY_FILE"
            fi
        fi
    done
    
    if [[ ${#failed_jobs[@]} -gt 0 ]]; then
        echo "Warning: The following jobs failed:"
        for ((i=0; i<${#failed_jobs[@]}; i++)); do
            echo "  Job ID: ${failed_jobs[$i]} - Sample: ${failed_samples[$i]}"
        done
        echo "These failures have been logged to $logs_base/failed_jobs.log"
        echo "The pipeline will continue using afterany dependencies, but some samples may be missing."
        
        return 1
    fi
    
    return 0
}

# Print pipeline information
echo "===== Mosquito RNA-Seq Pipeline ====="
echo "Raw reads directory: $raw_reads_dir"
echo "Results directory: $result_base"
echo "Log files: $logs_base"
echo "Debug mode: $debug_mode"
echo "Summary file: $SUMMARY_FILE"
echo "======================================="

# Step 1: Identify read pairs
echo "Identifying read pairs..."
if [[ ! -d "$raw_reads_dir" ]]; then
    echo "Error: Raw reads directory $raw_reads_dir does not exist!"
    exit 1
fi

# Check if directory is empty
if [[ -z "$(ls -A $raw_reads_dir)" ]]; then
    echo "Error: Raw reads directory $raw_reads_dir is empty!"
    exit 1
fi

# Arrays to store paired files
declare -a r1_files_array
declare -a r2_files_array
declare -a samples

# Function to extract sample name from filename
extract_sample_name() {
    local filename=$(basename "$1")
    # Remove common suffixes and extensions
    local sample=${filename%%_R1*}
    sample=${sample%%_1*}
    sample=${sample%%_r1*}
    echo "$sample"
}

echo "Pairing read files based on naming patterns..."
paired_found=0

# Find all potential R1 files with various naming conventions
r1_files=$(find "$raw_reads_dir" -type f -name "*_R1_*.fastq*" -o -name "*_R1.fastq*" -o -name "*_1.fastq*" -o -name "*_r1.fastq*" -o -name "*_r1_*.fastq*" | sort)

# For each R1 file, find its corresponding R2 file
for r1 in $r1_files; do
    # Try different R2 naming patterns
    r2=${r1/_R1_/_R2_}
    r2=${r2/_R1./_R2.}
    r2=${r2/_1./_2.}
    r2=${r2/_r1./_r2.}
    r2=${r2/_r1_/_r2_}
    
    # Check if R2 exists
    if [[ -f "$r2" ]]; then
        sample=$(extract_sample_name "$r1")
        r1_files_array+=("$r1")
        r2_files_array+=("$r2")
        samples+=("$sample")
        paired_found=$((paired_found + 1))
        echo "  Paired: $sample"
        echo "    R1: $r1"
        echo "    R2: $r2"
    else
        echo "  Warning: Could not find R2 pair for $r1"
    fi
done

echo "Found $paired_found paired read files:"
for ((i=0; i<${#samples[@]}; i++)); do
    echo "  ${samples[$i]}: ${r1_files_array[$i]} + ${r2_files_array[$i]}"
done

if [[ $paired_found -eq 0 ]]; then
    echo "Error: No read pairs found in $raw_reads_dir"
    exit 1
fi

# Step 2: Submit jobs in sequence with dependencies
# Step 2.1: Submit trimming jobs for each pair
echo "Submitting trimming jobs..."
trim_job_ids=()
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
    
    # Check if files already exist in debug mode
    if [[ "$debug_mode" == "true" && -s "$trim_r1" && -s "$trim_r2" ]]; then
        echo "Debug mode: Trimmed files already exist for sample $sample. Skipping trimming job."
        # Add entry to summary file
        echo "Trimming,$sample,Status,Skipped (files exist)" >> "$SUMMARY_FILE"
        continue
    fi
    
    echo "Submitting trimming job for sample $sample"
    # Submit trimming job with specific log directory and files
    job_id=$(sbatch --parsable \
             --partition="${fastp_partition}" \
             --time="${fastp_time}" \
             --nodes=${fastp_nodes} \
             --cpus-per-task=${fastp_cpu_cores_per_task} \
             --mem="${fastp_mem}" \
             --output="${trim_logs}/trim_${sample}_%j.out" \
             --error="${trim_logs}/trim_${sample}_%j.err" \
             bin/01_trimming.sh "$r1" "$r2" "$trim_r1" "$trim_r2" "$sample" "$trim_logs" "$SUMMARY_FILE" "$debug_mode")
    
    # Check if job submission was successful
    if [[ $? -ne 0 || -z "$job_id" ]]; then
        echo "Error: Failed to submit trimming job for sample $sample"
        exit 1
    fi
    
    trim_job_ids+=($job_id)
    echo "  Job ID: $job_id"
    
    # Verify job was submitted correctly
    if ! check_job_status "$job_id" "trim_${sample}"; then
        echo "Warning: Job verification failed for trimming job $job_id"
        # Continue anyway, as the job might still be in queue
    fi
    
    # Add a short delay to prevent overwhelming the scheduler
    sleep 1
done

# If no trimming jobs were submitted in debug mode, check if we have all the files we need
if [[ "$debug_mode" == "true" && ${#trim_job_ids[@]} -eq 0 ]]; then
    echo "Debug mode: All trimming jobs skipped. Checking if all required trimmed files exist..."
    all_files_exist=true
    for ((i=0; i<${#samples[@]}; i++)); do
        sample="${samples[$i]}"
        trim_r1="${trimmed_dir}/${sample}_R1_trimmed.fastq"
        trim_r2="${trimmed_dir}/${sample}_R2_trimmed.fastq"
        
        if [[ ! -s "$trim_r1" || ! -s "$trim_r2" ]]; then
            echo "Error: Missing trimmed files for sample $sample in debug mode."
            all_files_exist=false
            break
        fi
    done
    
    if [[ "$all_files_exist" == "false" ]]; then
        echo "Error: Cannot proceed in debug mode without all trimmed files."
        exit 1
    fi
fi

# Step 2.2: Submit merging job (depends on all trimming jobs)
echo "Preparing to submit merging job..."
# Set output for merged files
merged_r1="${merged_dir}/merged_R1.fastq"
merged_r2="${merged_dir}/merged_R2.fastq"

# Check if merge results already exist in debug mode
if [[ "$debug_mode" == "true" && -s "$merged_r1" && -s "$merged_r2" ]]; then
    echo "Debug mode: Merged files already exist. Skipping merge job."
    # Add entry to summary file
    echo "Merging,,Status,Skipped (files exist)" >> "$SUMMARY_FILE"
    merge_job_id="debug_skipped"
else
    # Check for failed trimming jobs and log them
    echo "Checking for failed trimming jobs..."
    track_failed_jobs "${trim_job_ids[@]}"
    
    # Create a dependency string for the merge job using afterany
    trim_dependency=""
    valid_dependencies=false
    
    # Check if any trimming jobs were actually submitted (not skipped in debug mode)
    for job_id in "${trim_job_ids[@]}"; do
        if [[ -n "$job_id" && "$job_id" != "debug_skipped" ]]; then
            valid_dependencies=true
            if [[ -z "$trim_dependency" ]]; then
                trim_dependency="afterany:$job_id"
            else
                trim_dependency="${trim_dependency}:$job_id"
            fi
        fi
    done
    
    echo "Trimming job IDs: ${trim_job_ids[*]}"
    echo "Merge dependency string: $trim_dependency"
    
    # Add this before submitting the merge job
    echo "Checking if file lists exist and have content:"
    echo "R1 list path: $r1_trimmed_list"
    echo "R2 list path: $r2_trimmed_list"

    if [[ -f "$r1_trimmed_list" ]]; then
        echo "R1 list exists. Content:"
        cat "$r1_trimmed_list"
    else
        echo "ERROR: R1 list file does not exist!"
        # Create the directory and an empty file
        mkdir -p $(dirname "$r1_trimmed_list")
        touch "$r1_trimmed_list"
    fi

    if [[ -f "$r2_trimmed_list" ]]; then
        echo "R2 list exists. Content:"
        cat "$r2_trimmed_list"
    else
        echo "ERROR: R2 list file does not exist!"
        # Create the directory and an empty file
        mkdir -p $(dirname "$r2_trimmed_list")
        touch "$r2_trimmed_list"
    fi

    # Make sure the output directories exist
    mkdir -p $(dirname "$merged_r1")
    mkdir -p "$merge_logs"
    
    # Submit merge job with appropriate dependencies
    if [[ "$valid_dependencies" == "true" ]]; then
        echo "Submitting merge job with dependency: $trim_dependency"
        merge_job_id=$(sbatch --parsable \
                      --partition="${merge_partition}" \
                      --time="${merge_time}" \
                      --nodes=${merge_nodes} \
                      --cpus-per-task=${merge_cpu_cores_per_task} \
                      --mem="${merge_mem}" \
                      --dependency=$trim_dependency \
                      --output="${merge_logs}/merge_%j.out" \
                      --error="${merge_logs}/merge_%j.err" \
                      bin/02_merge.sh "$r1_trimmed_list" "$r2_trimmed_list" "$merged_r1" "$merged_r2" "$merge_logs" "$SUMMARY_FILE" "$debug_mode")
    else
        # If all trimming jobs were skipped in debug mode, submit without dependencies
        echo "All trimming jobs were skipped in debug mode. Submitting merge job without dependencies."
        merge_job_id=$(sbatch --parsable \
                      --partition="${merge_partition}" \
                      --time="${merge_time}" \
                      --nodes=${merge_nodes} \
                      --cpus-per-task=${merge_cpu_cores_per_task} \
                      --mem="${merge_mem}" \
                      --output="${merge_logs}/merge_%j.out" \
                      --error="${merge_logs}/merge_%j.err" \
                      bin/02_merge.sh "$r1_trimmed_list" "$r2_trimmed_list" "$merged_r1" "$merged_r2" "$merge_logs" "$SUMMARY_FILE" "$debug_mode")
    fi
    
    # Check if job submission was successful
    if [[ $? -ne 0 || -z "$merge_job_id" ]]; then
        echo "Error: Failed to submit merge job"
        exit 1
    fi
    
    # Verify job was submitted correctly
    echo "Waiting for merge job to appear in queue..."
    sleep 2  # Give SLURM a moment to register the job
    
    if ! check_job_status "$merge_job_id" "merge"; then
        echo "Warning: Merge job $merge_job_id not found in queue. This might indicate a problem with job dependencies."
        echo "Checking job status..."
        sacct -j "$merge_job_id" --format=JobID,State,ExitCode
    else
        echo "Merge job successfully submitted and in queue."
    fi
fi

echo "  Merge job ID: $merge_job_id"

# Step 2.3: Submit assembly job (depends on merging job)
echo "Preparing to submit assembly job..."
assembly_transcripts="${assembly_dir}/transcripts.fasta"

# Check if assembly already exists in debug mode
if [[ "$debug_mode" == "true" && -s "$assembly_transcripts" ]]; then
    echo "Debug mode: Assembly file already exists. Skipping assembly job."
    # Add entry to summary file
    echo "Assembly,,Status,Skipped (files exist)" >> "$SUMMARY_FILE"
    assembly_job_id="debug_skipped"
else
    # Set up dependency for assembly job
    if [[ "$merge_job_id" == "debug_skipped" ]]; then
        echo "Debug mode: Merge job was skipped. Submitting assembly job without dependencies."
        
        assembly_job_id=$(sbatch --parsable \
                         --partition="${rnaSpades_partition}" \
                         --time="${rnaSpades_time}" \
                         --nodes=${rnaSpades_nodes} \
                         --cpus-per-task=${rnaSpades_cpu_cores_per_task} \
                         --mem="${rnaSpades_mem}" \
                         --output="${assembly_logs}/assembly_%j.out" \
                         --error="${assembly_logs}/assembly_%j.err" \
                         bin/03_assembly.sh "$merged_r1" "$merged_r2" "$assembly_dir" "${rnaSpades_opts}" "$assembly_logs" "$SUMMARY_FILE" "$debug_mode")
    else
        echo "Submitting assembly job with dependency on merge job: $merge_job_id"
        
        assembly_job_id=$(sbatch --parsable \
                         --partition="${rnaSpades_partition}" \
                         --time="${rnaSpades_time}" \
                         --nodes=${rnaSpades_nodes} \
                         --cpus-per-task=${rnaSpades_cpu_cores_per_task} \
                         --mem="${rnaSpades_mem}" \
                         --dependency=afterok:$merge_job_id \
                         --output="${assembly_logs}/assembly_%j.out" \
                         --error="${assembly_logs}/assembly_%j.err" \
                         bin/03_assembly.sh "$merged_r1" "$merged_r2" "$assembly_dir" "${rnaSpades_opts}" "$assembly_logs" "$SUMMARY_FILE" "$debug_mode")
    fi
    
    # Check if job submission was successful
    if [[ $? -ne 0 || -z "$assembly_job_id" ]]; then
        echo "Error: Failed to submit assembly job"
        exit 1
    fi
    
    echo "  Assembly job ID: $assembly_job_id"
    
    # Verify job was submitted correctly
    if ! check_job_status "$assembly_job_id" "assembly"; then
        echo "Warning: Job verification failed for assembly job $assembly_job_id"
        # Continue anyway, as the job might still be in queue
    fi
fi

# Step 2.4: Submit quality assessment jobs (depend on assembly job)
echo "Preparing to submit quality assessment jobs..."

# Check if BUSCO results already exist in debug mode
busco_summary="${busco_dir}/short_summary.specific.${busco_lineage}.${busco_mode}.txt"
if [[ "$debug_mode" == "true" && -s "$busco_summary" ]]; then
    echo "Debug mode: BUSCO summary already exists. Skipping BUSCO job."
    # Add entry to summary file
    echo "BUSCO,,Status,Skipped (files exist)" >> "$SUMMARY_FILE"
    busco_job_id="debug_skipped"
else
    # Set up dependency for BUSCO job
    if [[ "$assembly_job_id" == "debug_skipped" ]]; then
        echo "Debug mode: Assembly job was skipped. Submitting BUSCO job without dependencies."
        
        busco_job_id=$(sbatch --parsable \
                      --partition="${busco_partition}" \
                      --time="${busco_time}" \
                      --nodes=${busco_nodes} \
                      --cpus-per-task=${busco_cpu_cores_per_task} \
                      --mem="${busco_mem}" \
                      --output="${busco_logs}/busco_%j.out" \
                      --error="${busco_logs}/busco_%j.err" \
                      bin/04_busco.sh "$assembly_transcripts" "$busco_dir" "./busco_downloads" "transcriptome" "$busco_logs" "$SUMMARY_FILE" "$debug_mode")
    else
        echo "Submitting BUSCO job with dependency on assembly job: $assembly_job_id"
        
        busco_job_id=$(sbatch --parsable \
                      --partition="${busco_partition}" \
                      --time="${busco_time}" \
                      --nodes=${busco_nodes} \
                      --cpus-per-task=${busco_cpu_cores_per_task} \
                      --mem="${busco_mem}" \
                      --dependency=afterok:$assembly_job_id \
                      --output="${busco_logs}/busco_%j.out" \
                      --error="${busco_logs}/busco_%j.err" \
                      bin/04_busco.sh "$assembly_transcripts" "$busco_dir" "./busco_downloads" "transcriptome" "$busco_logs" "$SUMMARY_FILE" "$debug_mode")
    fi
    
    # Check if job submission was successful
    if [[ $? -ne 0 || -z "$busco_job_id" ]]; then
        echo "Error: Failed to submit BUSCO job"
        exit 1
    fi
    
    echo "  BUSCO job ID: $busco_job_id"
    
    # Verify job was submitted correctly
    if ! check_job_status "$busco_job_id" "busco"; then
        echo "Warning: Job verification failed for BUSCO job $busco_job_id"
        # Continue anyway, as the job might still be in queue
    fi
fi

# Check if rnaQuast results already exist in debug mode
rnaquast_report="${rnaquast_dir}/report.txt"
if [[ "$debug_mode" == "true" && -s "$rnaquast_report" ]]; then
    echo "Debug mode: rnaQuast report already exists. Skipping rnaQuast job."
    # Add entry to summary file
    echo "rnaQuast,,Status,Skipped (files exist)" >> "$SUMMARY_FILE"
    rnaquast_job_id="debug_skipped"
else
    # Set up dependency for rnaQuast job
    if [[ "$assembly_job_id" == "debug_skipped" ]]; then
        echo "Debug mode: Assembly job was skipped. Submitting rnaQuast job without dependencies."
        
        rnaquast_job_id=$(sbatch --parsable \
                         --partition="${rnaQuast_partition}" \
                         --time="${rnaQuast_time}" \
                         --nodes=${rnaQuast_nodes} \
                         --cpus-per-task=${rnaQuast_cpu_cores_per_task} \
                         --mem="${rnaQuast_mem}" \
                         --output="${rnaquast_logs}/rnaquast_%j.out" \
                         --error="${rnaquast_logs}/rnaquast_%j.err" \
                         bin/04_rnaquast.sh "$assembly_transcripts" "$rnaquast_dir" "$merged_r1" "$merged_r2" "${rnaQuast_opts}" "$rnaquast_logs" "$SUMMARY_FILE" "$debug_mode")
    else
        echo "Submitting rnaQuast job with dependency on assembly job: $assembly_job_id"
        
        rnaquast_job_id=$(sbatch --parsable \
                         --partition="${rnaQuast_partition}" \
                         --time="${rnaQuast_time}" \
                         --nodes=${rnaQuast_nodes} \
                         --cpus-per-task=${rnaQuast_cpu_cores_per_task} \
                         --mem="${rnaQuast_mem}" \
                         --dependency=afterok:$assembly_job_id \
                         --output="${rnaquast_logs}/rnaquast_%j.out" \
                         --error="${rnaquast_logs}/rnaquast_%j.err" \
                         bin/04_rnaquast.sh "$assembly_transcripts" "$rnaquast_dir" "$merged_r1" "$merged_r2" "${rnaQuast_opts}" "$rnaquast_logs" "$SUMMARY_FILE" "$debug_mode")
    fi
    
    # Check if job submission was successful
    if [[ $? -ne 0 || -z "$rnaquast_job_id" ]]; then
        echo "Error: Failed to submit rnaQuast job"
        exit 1
    fi
    
    echo "  rnaQuast job ID: $rnaquast_job_id"
    
    # Verify job was submitted correctly
    if ! check_job_status "$rnaquast_job_id" "rnaquast"; then
        echo "Warning: Job verification failed for rnaQuast job $rnaquast_job_id"
        # Continue anyway, as the job might still be in queue
    fi
fi

# If draft transcriptome is provided, run quality assessment on it too
draft_busco_job_id=""
draft_rnaquast_job_id=""
if [[ -n "$draft_transcriptome" && -f "$draft_transcriptome" ]]; then
    echo "Found draft transcriptome: $draft_transcriptome"
    
    # Check if draft BUSCO results already exist in debug mode
    draft_busco_summary="${draft_busco_dir}/short_summary.specific.${busco_lineage}.draft_assembly.txt"
    if [[ "$debug_mode" == "true" && -s "$draft_busco_summary" ]]; then
        echo "Debug mode: Draft BUSCO summary already exists. Skipping draft BUSCO job."
        # Add entry to summary file
        echo "BUSCO,draft,Status,Skipped (files exist)" >> "$SUMMARY_FILE"
        draft_busco_job_id="debug_skipped"
    else
        echo "Submitting BUSCO job for draft transcriptome"
        draft_busco_job_id=$(sbatch --parsable \
                            --partition="${busco_partition}" \
                            --time="${busco_time}" \
                            --nodes=${busco_nodes} \
                            --cpus-per-task=${busco_cpu_cores_per_task} \
                            --mem="${busco_mem}" \
                            --output="${busco_logs}/draft_busco_%j.out" \
                            --error="${busco_logs}/draft_busco_%j.err" \
                            bin/04_busco.sh "$draft_transcriptome" "$draft_busco_dir" "./busco_downloads" "draft_assembly" "$busco_logs" "$SUMMARY_FILE" "$debug_mode")
        
        # Check if job submission was successful
        if [[ $? -ne 0 || -z "$draft_busco_job_id" ]]; then
            echo "Error: Failed to submit draft BUSCO job"
            # Continue anyway, as this is optional
        else
            echo "  Draft BUSCO job ID: $draft_busco_job_id"
        fi
    fi
    
    # Check if draft rnaQuast results already exist in debug mode
    draft_rnaquast_report="${draft_rnaquast_dir}/report.txt"
    if [[ "$debug_mode" == "true" && -s "$draft_rnaquast_report" ]]; then
        echo "Debug mode: Draft rnaQuast report already exists. Skipping draft rnaQuast job."
        # Add entry to summary file
        echo "rnaQuast,draft,Status,Skipped (files exist)" >> "$SUMMARY_FILE"
        draft_rnaquast_job_id="debug_skipped"
    else
        echo "Submitting rnaQuast job for draft transcriptome"
        draft_rnaquast_job_id=$(sbatch --parsable \
                               --partition="${rnaQuast_partition}" \
                               --time="${rnaQuast_time}" \
                               --nodes=${rnaQuast_nodes} \
                               --cpus-per-task=${rnaQuast_cpu_cores_per_task} \
                               --mem="${rnaQuast_mem}" \
                               --output="${rnaquast_logs}/draft_rnaquast_%j.out" \
                               --error="${rnaquast_logs}/draft_rnaquast_%j.err" \
                               bin/04_rnaquast.sh "$draft_transcriptome" "$draft_rnaquast_dir" "$merged_r1" "$merged_r2" "${rnaQuast_opts}" "$rnaquast_logs" "$SUMMARY_FILE" "$debug_mode")
        
        # Check if job submission was successful
        if [[ $? -ne 0 || -z "$draft_rnaquast_job_id" ]]; then
            echo "Error: Failed to submit draft rnaQuast job"
            # Continue anyway, as this is optional
        else
            echo "  Draft rnaQuast job ID: $draft_rnaquast_job_id"
        fi
    fi
fi

# Step 2.5: Submit visualization job (depends on all quality assessment jobs)
echo "Preparing to submit visualization job..."
# Check if visualization results already exist in debug mode
viz_plot="${viz_dir}/combined_plot.pdf"
if [[ "$debug_mode" == "true" && -s "$viz_plot" ]]; then
    echo "Debug mode: Visualization plot already exists. Skipping visualization job."
    # Add entry to summary file
    echo "Visualization,,Status,Skipped (files exist)" >> "$SUMMARY_FILE"
    viz_job_id="debug_skipped"
else
    # Create dependency string for visualization
    viz_dependency=""
    if [[ "$busco_job_id" != "debug_skipped" && "$rnaquast_job_id" != "debug_skipped" ]]; then
        viz_dependency="afterok:$busco_job_id:$rnaquast_job_id"
        
        # Add draft jobs if they exist and weren't skipped
        if [[ -n "$draft_transcriptome" && -f "$draft_transcriptome" ]]; then
            if [[ "$draft_busco_job_id" != "debug_skipped" && "$draft_rnaquast_job_id" != "debug_skipped" ]]; then
                viz_dependency="$viz_dependency:$draft_busco_job_id:$draft_rnaquast_job_id"
            fi
        fi
        
        viz_job_id=$(sbatch --parsable \
                    --partition="${visualize_partition}" \
                    --time="${visualize_time}" \
                    --nodes=${visualize_nodes} \
                    --cpus-per-task=${visualize_cpu_cores_per_task} \
                    --mem="${visualize_mem}" \
                    --dependency=$viz_dependency \
                    --output="${viz_logs}/visualize_%j.out" \
                    --error="${viz_logs}/visualize_%j.err" \
                    bin/05_visualize.sh "$busco_dir" "$rnaquast_dir" "$viz_dir" "$draft_busco_dir" "$draft_rnaquast_dir" "$viz_logs")
    else
        viz_job_id=$(sbatch --parsable \
                    --partition="${visualize_partition}" \
                    --time="${visualize_time}" \
                    --nodes=${visualize_nodes} \
                    --cpus-per-task=${visualize_cpu_cores_per_task} \
                    --mem="${visualize_mem}" \
                    --dependency=$viz_dependency \
                    --output="${viz_logs}/visualize_%j.out" \
                    --error="${viz_logs}/visualize_%j.err" \
                    bin/05_visualize.sh "$busco_dir" "$rnaquast_dir" "$viz_dir" "" "" "$viz_logs")
    fi
    
    # Check if job submission was successful
    if [[ $? -ne 0 || -z "$viz_job_id" ]]; then
        echo "Error: Failed to submit visualization job"
        exit 1
    fi
    
    # Verify job was submitted correctly
    if ! check_job_status "$viz_job_id" "visualize"; then
        echo "Warning: Job verification failed for visualization job $viz_job_id"
        # Continue anyway, as the job might still be in queue
    fi
fi

echo "  Visualization job ID: $viz_job_id"

# Print summary of submitted jobs
echo "======================="
echo "Job submission summary:"
echo "======================="
echo "Trimming jobs: ${trim_job_ids[*]}"
echo "Merge job: $merge_job_id"
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
echo "Log files will be in: $logs_base"

# Create a helper script to cancel all jobs if needed
cancel_script="${logs_base}/cancel_all_jobs.sh"
echo "#!/bin/bash" > $cancel_script
echo "# Script to cancel all pipeline jobs" >> $cancel_script
echo "echo 'Cancelling all pipeline jobs...'" >> $cancel_script
for job_id in "${trim_job_ids[@]}" "$merge_job_id" "$assembly_job_id" "$busco_job_id" "$rnaquast_job_id" "$draft_busco_job_id" "$draft_rnaquast_job_id" "$viz_job_id"; do
    if [[ -n "$job_id" ]]; then
        echo "scancel $job_id" >> $cancel_script
    fi
done
echo "echo 'All jobs cancelled.'" >> $cancel_script
chmod +x $cancel_script
echo "To cancel all jobs, run: $cancel_script"
