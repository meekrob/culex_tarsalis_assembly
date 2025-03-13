#!/bin/bash


# main.sh - Master control script for mosquito RNA-seq pipeline
# This script identifies input files, sets up directories, and manages job dependencies

#SBATCH --job-name=transcriptome
#SBATCH --output=logs/transcriptome_assembly/main_%j.out
#SBATCH --error=logs/transcriptome_assembly/main_%j.err

# Get start time for timing
start_time=$(date +%s)

# Source conda
source ~/.bashrc

# Detect repository root more reliably
SCRIPT_PATH=$(realpath "$0")
SCRIPT_DIR=$(dirname "$SCRIPT_PATH")
REPO_ROOT=$(realpath "$SCRIPT_DIR/../../..")

# Source paths file - use explicit path
CONFIG_PATH="${REPO_ROOT}/config/paths.sh"
if [[ -f "$CONFIG_PATH" ]]; then
    source "$CONFIG_PATH"
else
    echo "ERROR: Cannot find paths config at $CONFIG_PATH"
    echo "Current directory: $(pwd)"
    echo "Script path: $SCRIPT_PATH"
    exit 1
fi

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

# Define standardized directories
data_base="${1:-${RAW_READS_DIR}}"
result_base="${2:-${RESULTS_DIR}/transcriptome_assembly}"
logs_base="${LOGS_DIR}/transcriptome_assembly"
temp_dir="${TEMP_DIR}/transcriptome_assembly"

# Create directories manually instead of using function
echo "Creating pipeline directories..."
mkdir -p "${result_base}"
mkdir -p "${logs_base}"
mkdir -p "${temp_dir}"

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

# Ensure all R1 files have matching R2 files
trim_dependencies=""
sample_count=0

for sample in "${!r1_files[@]}"; do
    r1="${r1_files[$sample]}"
    
    if [[ -n "${r2_files[$sample]}" ]]; then
        r2="${r2_files[$sample]}"
        echo "Paired sample $sample:"
        echo "  R1: $r1"
        echo "  R2: $r2"
        
        # Add to file lists
        echo "$r1" >> "$r1_list"
        echo "$r2" >> "$r2_list"
        
        # Define output files for trimming
        trimmed_r1="${result_base}/01_trimmed/$(basename "$r1")"
        trimmed_r2="${result_base}/01_trimmed/$(basename "$r2")"
        trimmed_r1=${trimmed_r1/.fastq.gz/_trimmed.fastq.gz}
        trimmed_r2=${trimmed_r2/.fastq.gz/_trimmed.fastq.gz}
        
        # Add to trimmed file lists
        echo "$trimmed_r1" >> "$trimmed_r1_list"
        echo "$trimmed_r2" >> "$trimmed_r2_list"
        
        # Submit trimming job for this pair
        echo "Submitting trimming job for sample $sample..."
        
        # Skip if outputs exist and debug mode is on
        if [[ "$debug_mode" == true && -s "$trimmed_r1" && -s "$trimmed_r2" ]]; then
            echo "DEBUG: Skipping trimming for $sample, outputs exist"
            trim_job_id="skipped"
        else
            trim_cmd="sbatch --parsable --job-name=trim_${sample} --output=${logs_base}/01_trimming/trim_${sample}_%j.out --error=${logs_base}/01_trimming/trim_${sample}_%j.err"
            trim_job_id=$(eval $trim_cmd $SCRIPT_DIR/01_trimming.sh "$r1" "$r2" "$trimmed_r1" "$trimmed_r2" "$sample" "${logs_base}/01_trimming" "$summary_file")
            
            if [[ -z "$trim_job_id" || "$trim_job_id" == "0" ]]; then
                echo "Error: Failed to submit trimming job for sample $sample"
                continue
            fi
            
            echo "Submitted trimming job: $trim_job_id"
        fi
        
        # Add to trim dependency list for merge step
        if [[ "$trim_job_id" != "skipped" ]]; then
            if [[ -z "$trim_dependencies" ]]; then
                trim_dependencies="afterok:$trim_job_id"
            else
                trim_dependencies="$trim_dependencies:$trim_job_id"
            fi
        fi
        
        ((sample_count++))
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

# Step 2: Submit merge jobs
echo "Submitting merge jobs..."

# Define output files for merged reads
merged_r1="${result_base}/02_merged/merged_R1.fastq.gz"
merged_r2="${result_base}/02_merged/merged_R2.fastq.gz"

# Submit merge job for R1 files
merge_r1_cmd="sbatch --parsable --job-name=merge_R1 --output=${logs_base}/02_merge/merge_R1_%j.out --error=${logs_base}/02_merge/merge_R1_%j.err --dependency=$trim_dependencies"
merge_r1_job_id=$(eval $merge_r1_cmd $SCRIPT_DIR/02_merge.sh "$r1_list" "$merged_r1" "R1" "${logs_base}/02_merge" "$debug_mode" "$summary_file")

if [[ -n "$merge_r1_job_id" ]]; then
    echo "Submitted merge job for R1: $merge_r1_job_id"
else
    echo "Error: Failed to submit merge job for R1"
    exit 1
fi

# Submit merge job for R2 files
merge_r2_cmd="sbatch --parsable --job-name=merge_R2 --output=${logs_base}/02_merge/merge_R2_%j.out --error=${logs_base}/02_merge/merge_R2_%j.err --dependency=$trim_dependencies"
merge_r2_job_id=$(eval $merge_r2_cmd $SCRIPT_DIR/02_merge.sh "$r2_list" "$merged_r2" "R2" "${logs_base}/02_merge" "$debug_mode" "$summary_file")

if [[ -n "$merge_r2_job_id" ]]; then
    echo "Submitted merge job for R2: $merge_r2_job_id"
else
    echo "Error: Failed to submit merge job for R2"
    exit 1
fi

# Step 3: Add pair checking step
echo "Submitting pair checking job..."

# Set output files for fixed paired reads
fixed_r1="${result_base}/03_pairs/fixed_R1.fastq.gz"
fixed_r2="${result_base}/03_pairs/fixed_R2.fastq.gz"

# Make pair checking job dependent on both merge jobs
check_pairs_dependency="--dependency=afterok:${merge_r1_job_id}:${merge_r2_job_id}"

# Submit pair checking job
check_pairs_cmd="sbatch --parsable --job-name=check_pairs --output=${logs_base}/03_pairs/check_pairs_%j.out --error=${logs_base}/03_pairs/check_pairs_%j.err $check_pairs_dependency"
check_pairs_job_id=$(eval $check_pairs_cmd $SCRIPT_DIR/03_check_pairs.sh "$merged_r1" "$merged_r2" "$fixed_r1" "$fixed_r2" "${logs_base}/03_pairs" "$summary_file" "$debug_mode")

if [[ -n "$check_pairs_job_id" ]]; then
    echo "Submitted pair checking job: $check_pairs_job_id"
else
    echo "Error: Failed to submit pair checking job"
    exit 1
fi

# Step 4: Add normalization steps (both methods)
echo "Submitting read normalization jobs (BBNorm and Trinity)..."

# Set output files for BBNorm normalized reads
bbnorm_dir="${result_base}/04_normalized/bbnorm"
mkdir -p "$bbnorm_dir"
bbnorm_r1="${bbnorm_dir}/normalized_R1.fastq.gz"
bbnorm_r2="${bbnorm_dir}/normalized_R2.fastq.gz"

# Set output files for Trinity normalized reads
trinity_norm_dir="${result_base}/04_normalized/trinity"
mkdir -p "$trinity_norm_dir"
trinity_norm_r1="${trinity_norm_dir}/normalized_R1.fastq.gz"
trinity_norm_r2="${trinity_norm_dir}/normalized_R2.fastq.gz"

# Make normalization jobs dependent on pair checking job
norm_dependency="--dependency=afterok:${check_pairs_job_id}"

# Submit BBNorm normalization job
bbnorm_logs="${logs_base}/04_normalization/bbnorm"
mkdir -p "$bbnorm_logs"
bbnorm_cmd="sbatch --parsable --job-name=bbnorm --output=${bbnorm_logs}/normalize_%j.out --error=${bbnorm_logs}/normalize_%j.err $norm_dependency"
bbnorm_job_id=$(eval $bbnorm_cmd $SCRIPT_DIR/04_read_normalization.sh "$fixed_r1" "$fixed_r2" "$bbnorm_r1" "$bbnorm_r2" "$bbnorm_logs" "$summary_file" "$debug_mode")

if [[ -n "$bbnorm_job_id" ]]; then
    echo "Submitted BBNorm normalization job: $bbnorm_job_id"
else
    echo "Error: Failed to submit BBNorm normalization job"
    exit 1
fi

# Submit Trinity normalization job
trinity_norm_logs="${logs_base}/04_normalization/trinity"
mkdir -p "$trinity_norm_logs"
trinity_norm_cmd="sbatch --parsable --job-name=trinity_norm --output=${trinity_norm_logs}/normalize_%j.out --error=${trinity_norm_logs}/normalize_%j.err $norm_dependency"
trinity_norm_job_id=$(eval $trinity_norm_cmd $SCRIPT_DIR/04_trinity_normalization.sh "$fixed_r1" "$fixed_r2" "$trinity_norm_r1" "$trinity_norm_r2" "$trinity_norm_logs" "$summary_file" "$debug_mode")

if [[ -n "$trinity_norm_job_id" ]]; then
    echo "Submitted Trinity normalization job: $trinity_norm_job_id"
else
    echo "Error: Failed to submit Trinity normalization job"
    exit 1
fi

# Step 5: Submit assembly jobs (one for each normalization method)
echo "Submitting assembly jobs (one for each normalization method)..."

# Define separate assembly directories
bbnorm_assembly_dir="${result_base}/05_assembly/bbnorm"
trinity_norm_assembly_dir="${result_base}/05_assembly/trinity"
mkdir -p "$bbnorm_assembly_dir"
mkdir -p "$trinity_norm_assembly_dir"

# Define separate assembly log directories
bbnorm_assembly_logs="${logs_base}/05_assembly/bbnorm"
trinity_norm_assembly_logs="${logs_base}/05_assembly/trinity"
mkdir -p "$bbnorm_assembly_logs"
mkdir -p "$trinity_norm_assembly_logs"

# Make assembly jobs dependent on respective normalization jobs
bbnorm_assembly_dependency="--dependency=afterok:${bbnorm_job_id}"
trinity_norm_assembly_dependency="--dependency=afterok:${trinity_norm_job_id}"

# Submit BBNorm-based assembly job
bbnorm_assembly_cmd="sbatch --parsable --job-name=assembly_bbnorm --output=${bbnorm_assembly_logs}/assembly_%j.out --error=${bbnorm_assembly_logs}/assembly_%j.err $bbnorm_assembly_dependency"
bbnorm_assembly_job_id=$(eval $bbnorm_assembly_cmd $SCRIPT_DIR/05_assembly.sh "$bbnorm_r1" "$bbnorm_r2" "$bbnorm_assembly_dir" "$bbnorm_assembly_logs" "$debug_mode" "$summary_file")

if [[ -n "$bbnorm_assembly_job_id" ]]; then
    echo "Submitted BBNorm-based assembly job: $bbnorm_assembly_job_id"
else
    echo "Error: Failed to submit BBNorm-based assembly job"
    exit 1
fi

# Submit Trinity-based assembly job
trinity_norm_assembly_cmd="sbatch --parsable --job-name=assembly_trinity --output=${trinity_norm_assembly_logs}/assembly_%j.out --error=${trinity_norm_assembly_logs}/assembly_%j.err $trinity_norm_assembly_dependency"
trinity_norm_assembly_job_id=$(eval $trinity_norm_assembly_cmd $SCRIPT_DIR/05_assembly.sh "$trinity_norm_r1" "$trinity_norm_r2" "$trinity_norm_assembly_dir" "$trinity_norm_assembly_logs" "$debug_mode" "$summary_file")

if [[ -n "$trinity_norm_assembly_job_id" ]]; then
    echo "Submitted Trinity-based assembly job: $trinity_norm_assembly_job_id"
else
    echo "Error: Failed to submit Trinity-based assembly job"
    exit 1
fi

# Step 6: Submit BUSCO jobs for both assemblies
echo "Submitting quality assessment jobs for both assemblies..."

# Define separate BUSCO directories
bbnorm_busco_dir="${result_base}/06_busco/bbnorm"
trinity_norm_busco_dir="${result_base}/06_busco/trinity"
mkdir -p "$bbnorm_busco_dir"
mkdir -p "$trinity_norm_busco_dir"

# Define separate BUSCO log directories
bbnorm_busco_logs="${logs_base}/06_busco/bbnorm"
trinity_norm_busco_logs="${logs_base}/06_busco/trinity"
mkdir -p "$bbnorm_busco_logs"
mkdir -p "$trinity_norm_busco_logs"

# Submit BUSCO job for BBNorm-based assembly
bbnorm_busco_cmd="sbatch --parsable --job-name=busco_bbnorm --output=${bbnorm_busco_logs}/busco_%j.out --error=${bbnorm_busco_logs}/busco_%j.err --dependency=afterok:${bbnorm_assembly_job_id}"
bbnorm_busco_job_id=$(eval $bbnorm_busco_cmd $SCRIPT_DIR/06_busco.sh "$bbnorm_assembly_dir/transcripts.fasta" "$bbnorm_busco_dir" "$bbnorm_busco_logs" "$debug_mode" "$summary_file")

if [[ -n "$bbnorm_busco_job_id" ]]; then
    echo "Submitted BUSCO job for BBNorm assembly: $bbnorm_busco_job_id"
else
    echo "Error: Failed to submit BUSCO job for BBNorm assembly"
    exit 1
fi

# Submit BUSCO job for Trinity-based assembly
trinity_norm_busco_cmd="sbatch --parsable --job-name=busco_trinity --output=${trinity_norm_busco_logs}/busco_%j.out --error=${trinity_norm_busco_logs}/busco_%j.err --dependency=afterok:${trinity_norm_assembly_job_id}"
trinity_norm_busco_job_id=$(eval $trinity_norm_busco_cmd $SCRIPT_DIR/06_busco.sh "$trinity_norm_assembly_dir/transcripts.fasta" "$trinity_norm_busco_dir" "$trinity_norm_busco_logs" "$debug_mode" "$summary_file")

if [[ -n "$trinity_norm_busco_job_id" ]]; then
    echo "Submitted BUSCO job for Trinity assembly: $trinity_norm_busco_job_id"
else
    echo "Error: Failed to submit BUSCO job for Trinity assembly"
    exit 1
fi

echo "All jobs submitted. Pipeline will run with the following job IDs:"
echo "  Trimming: $trim_dependencies"
echo "  Merging: $merge_r1_job_id, $merge_r2_job_id"
echo "  Pair checking: $check_pairs_job_id"
echo "  BBNorm normalization: $bbnorm_job_id"
echo "  Trinity normalization: $trinity_norm_job_id"
echo "  BBNorm assembly: $bbnorm_assembly_job_id"
echo "  Trinity assembly: $trinity_norm_assembly_job_id"
echo "  BBNorm BUSCO: $bbnorm_busco_job_id"
echo "  Trinity BUSCO: $trinity_norm_busco_job_id"

# Calculate total runtime
end_time=$(date +%s)
total_runtime=$((end_time - start_time))
echo "Pipeline setup completed in $total_runtime seconds"
echo "Check job status with: squeue -u $USER"
