#!/bin/bash

# main.sh - Master control script for mosquito RNA-seq pipeline

#SBATCH --job-name=transcriptome
#SBATCH --partition=day-long-cpu
#SBATCH --time=24:00:00
#SBATCH --mem=8G
#SBATCH --cpus-per-task=1

# Record start time
start_time=$(date +%s)

# Robustly determine repository root
SCRIPT_PATH="$(realpath "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"
REPO_ROOT="$(realpath "$SCRIPT_DIR/../../..")"
echo "Repository root determined as: $REPO_ROOT"

# Parse command line arguments
debug_mode=false
while getopts "d" opt; do
    case $opt in
        d) debug_mode=true ;;
        ?) echo "Invalid option: -$OPTARG" >&2; exit 1 ;;
    esac
done
shift $((OPTIND-1))

# Define standardized directories
DATA_DIR="${REPO_ROOT}/data"
RESULTS_DIR="${REPO_ROOT}/results"
LOGS_DIR="${REPO_ROOT}/logs"
TEMP_DIR="${REPO_ROOT}/temp"
RAW_READS_DIR="${DATA_DIR}/raw_reads"

data_base="${1:-${RAW_READS_DIR}}"
result_base="${2:-${RESULTS_DIR}/transcriptome_assembly}"
logs_base="${LOGS_DIR}/transcriptome_assembly"
temp_dir="${TEMP_DIR}/transcriptome_assembly"

# Create directories
for dir in "$DATA_DIR" "$RESULTS_DIR" "$LOGS_DIR" "$TEMP_DIR" "$RAW_READS_DIR" \
           "$result_base" "$logs_base" "$temp_dir" \
           "$result_base/01_trimmed" "$result_base/02_merged" "$result_base/03_pairs" \
           "$result_base/04_normalized/bbnorm" "$result_base/04_normalized/trinity" \
           "$result_base/05_assembly/bbnorm" "$result_base/05_assembly/trinity" \
           "$result_base/06_busco/bbnorm" "$result_base/06_busco/trinity" \
           "$logs_base/01_trimming" "$logs_base/02_merge" "$logs_base/03_pairs" \
           "$logs_base/04_normalization/bbnorm" "$logs_base/04_normalization/trinity" \
           "$logs_base/05_assembly/bbnorm" "$logs_base/05_assembly/trinity" \
           "$logs_base/06_busco/bbnorm" "$logs_base/06_busco/trinity"; do
    mkdir -p "$dir" || { echo "Failed to create $dir"; exit 1; }
done

# Redirect SLURM output
mv "$SLURM_SUBMIT_DIR/transcriptome_*.out" "$logs_base/" 2>/dev/null || true
mv "$SLURM_SUBMIT_DIR/transcriptome_*.err" "$logs_base/" 2>/dev/null || true
echo "SLURM output redirected to $logs_base"

# Initialize summary file
summary_file="${logs_base}/pipeline_summary.csv"
echo "Step,Sample,Metric,Value" > "$summary_file"

# Check disk space (50GB required)
required_space=$((50 * 1024 * 1024))
available_space=$(df -k "$result_base" | tail -1 | awk '{print $4}')
if [[ $available_space -lt $required_space ]]; then
    echo "Error: Insufficient disk space ($available_space KB available, $required_space KB required)" >&2
    exit 1
fi

# Print pipeline info
echo "====== Mosquito RNA-Seq Pipeline ======"
echo "Data directory: $data_base"
echo "Results directory: $result_base"
echo "Logs directory: $logs_base"
echo "Debug mode: $debug_mode"
echo "======================================"

# Verify data directory
if [[ ! -d "$data_base" ]]; then
    echo "Error: Data directory not found: $data_base" >&2
    ls -la "$REPO_ROOT"
    exit 1
fi

# Source environment
source ~/.bashrc || { echo "Failed to source ~/.bashrc" >&2; exit 1; }
conda activate cellSquito || { echo "Failed to activate cellSquito environment" >&2; exit 1; }

# Find and pair read files
declare -A r1_files r2_files
r1_list="${temp_dir}/r1_files.txt"
r2_list="${temp_dir}/r2_files.txt"
trimmed_r1_list="${temp_dir}/trimmed_r1_files.txt"
trimmed_r2_list="${temp_dir}/trimmed_r2_files.txt"
> "$r1_list" "$r2_list" "$trimmed_r1_list" "$trimmed_r2_list"

echo "Scanning for read files in $data_base..."
for file in "$data_base"/*{R1,_1}*.fastq.gz; do
    [[ -s "$file" ]] || continue
    sample=$(basename "$file" | sed -E 's/_R1.*|_1\.fastq\.gz//')
    r1_files["$sample"]="$file"
done
for file in "$data_base"/*{R2,_2}*.fastq.gz; do
    [[ -s "$file" ]] || continue
    sample=$(basename "$file" | sed -E 's/_R2.*|_2\.fastq\.gz//')
    r2_files["$sample"]="$file"
done

echo "Found ${#r1_files[@]} R1 files and ${#r2_files[@]} R2 files"

# Submit trimming jobs
sample_count=0
trim_job_ids=()
metadata_file="${result_base}/sample_metadata.csv"
echo "sample,r1_file,r2_file,trimmed_r1,trimmed_r2" > "$metadata_file"

for sample in "${!r1_files[@]}"; do
    r1="${r1_files[$sample]}"
    r2="${r2_files[$sample]}"
    if [[ -z "$r2" ]]; then
        echo "Warning: No R2 for $sample (R1: $r1), skipping" >&2
        continue
    fi

    trimmed_r1="${result_base}/01_trimmed/${sample}_R1_trimmed.fastq.gz"
    trimmed_r2="${result_base}/01_trimmed/${sample}_R2_trimmed.fastq.gz"
    echo "$sample,$r1,$r2,$trimmed_r1,$trimmed_r2" >> "$metadata_file"
    echo "$r1" >> "$r1_list"
    echo "$r2" >> "$r2_list"
    echo "$trimmed_r1" >> "$trimmed_r1_list"
    echo "$trimmed_r2" >> "$trimmed_r2_list"

    job_id=$(sbatch --parsable \
        --job-name="trim_${sample}" \
        --output="${logs_base}/01_trimming/trim_${sample}_%j.out" \
        --error="${logs_base}/01_trimming/trim_${sample}_%j.err" \
        "$SCRIPT_DIR/01_trimming.sh" "$r1" "$r2" "$trimmed_r1" "$trimmed_r2" "$sample" \
        "$logs_base/01_trimming" "$summary_file" "$debug_mode")
    if [[ $? -ne 0 || -z "$job_id" ]]; then
        echo "Error: Failed to submit trimming job for $sample" >&2
        exit 1
    fi
    trim_job_ids+=("$job_id")
    echo "Submitted trimming job for $sample: $job_id"
    ((sample_count++))
done

[[ $sample_count -eq 0 ]] && { echo "Error: No valid sample pairs found" >&2; exit 1; }
echo "Processing $sample_count paired samples"

# Build dependency string
trim_deps=$(IFS=:; echo "afterok:${trim_job_ids[*]}")

# Submit merge job
merge_r1="${result_base}/02_merged/merged_reads_R1.fastq.gz"
merge_r2="${result_base}/02_merged/merged_reads_R2.fastq.gz"
merge_job_id=$(sbatch --parsable \
    --job-name="merge" \
    --dependency="$trim_deps" \
    --output="${logs_base}/02_merge/merge_%j.out" \
    --error="${logs_base}/02_merge/merge_%j.err" \
    "$SCRIPT_DIR/02_merge.sh" "$trimmed_r1_list" "$merge_r1" "R1" "$logs_base/02_merge" "$debug_mode" "$summary_file")
[[ $? -ne 0 || -z "$merge_job_id" ]] && { echo "Error: Failed to submit merge job for R1" >&2; exit 1; }
merge_job_id_r2=$(sbatch --parsable \
    --job-name="merge_r2" \
    --dependency="$trim_deps" \
    --output="${logs_base}/02_merge/merge_r2_%j.out" \
    --error="${logs_base}/02_merge/merge_r2_%j.err" \
    "$SCRIPT_DIR/02_merge.sh" "$trimmed_r2_list" "$merge_r2" "R2" "$logs_base/02_merge" "$debug_mode" "$summary_file")
[[ $? -ne 0 || -z "$merge_job_id_r2" ]] && { echo "Error: Failed to submit merge job for R2" >&2; exit 1; }
echo "Submitted merge jobs: $merge_job_id (R1), $merge_job_id_r2 (R2)"

# Submit pair checking
fixed_r1="${result_base}/03_pairs/fixed_R1.fastq.gz"
fixed_r2="${result_base}/03_pairs/fixed_R2.fastq.gz"
pair_job_id=$(sbatch --parsable \
    --job-name="pair_check" \
    --dependency="afterok:$merge_job_id:$merge_job_id_r2" \
    --output="${logs_base}/03_pairs/pair_%j.out" \
    --error="${logs_base}/03_pairs/pair_%j.err" \
    "$SCRIPT_DIR/03_check_pairs.sh" "$merge_r1" "$merge_r2" "$fixed_r1" "$fixed_r2" "$logs_base/03_pairs" "$debug_mode" "$summary_file")
[[ $? -ne 0 || -z "$pair_job_id" ]] && { echo "Error: Failed to submit pair check job" >&2; exit 1; }
echo "Submitted pair check job: $pair_job_id"

# Submit normalization jobs (BBNorm and Trinity)
norm_r1_bb="${result_base}/04_normalized/bbnorm/norm_R1.fastq.gz"
norm_r2_bb="${result_base}/04_normalized/bbnorm/norm_R2.fastq.gz"
norm_r1_tr="${result_base}/04_normalized/trinity/norm_R1.fastq.gz"
norm_r2_tr="${result_base}/04_normalized/trinity/norm_R2.fastq.gz"

bbnorm_job_id=$(sbatch --parsable \
    --job-name="bbnorm" \
    --dependency="afterok:$pair_job_id" \
    --output="${logs_base}/04_normalization/bbnorm/bbnorm_%j.out" \
    --error="${logs_base}/04_normalization/bbnorm/bbnorm_%j.err" \
    "$SCRIPT_DIR/04_read_normalization.sh" "$fixed_r1" "$fixed_r2" "$norm_r1_bb" "$norm_r2_bb" "$logs_base/04_normalization/bbnorm" "$summary_file" "$debug_mode")
[[ $? -ne 0 || -z "$bbnorm_job_id" ]] && { echo "Error: Failed to submit BBNorm job" >&2; exit 1; }
echo "Submitted BBNorm job: $bbnorm_job_id"

trinity_norm_job_id=$(sbatch --parsable \
    --job-name="trinity_norm" \
    --dependency="afterok:$pair_job_id" \
    --output="${logs_base}/04_normalization/trinity/trinity_norm_%j.out" \
    --error="${logs_base}/04_normalization/trinity/trinity_norm_%j.err" \
    "$SCRIPT_DIR/04_trinity_normalization.sh" "$fixed_r1" "$fixed_r2" "$norm_r1_tr" "$norm_r2_tr" "$logs_base/04_normalization/trinity" "$summary_file" "$debug_mode")
[[ $? -ne 0 || -z "$trinity_norm_job_id" ]] && { echo "Error: Failed to submit Trinity norm job" >&2; exit 1; }
echo "Submitted Trinity norm job: $trinity_norm_job_id"

# Submit assembly jobs
assembly_bb_dir="${result_base}/05_assembly/bbnorm"
assembly_tr_dir="${result_base}/05_assembly/trinity"
assembly_bb_job_id=$(sbatch --parsable \
    --job-name="assembly_bb" \
    --dependency="afterok:$bbnorm_job_id" \
    --output="${logs_base}/05_assembly/bbnorm/assembly_%j.out" \
    --error="${logs_base}/05_assembly/bbnorm/assembly_%j.err" \
    "$SCRIPT_DIR/05_assembly.sh" "$norm_r1_bb" "$norm_r2_bb" "$assembly_bb_dir" "$logs_base/05_assembly/bbnorm" "$debug_mode" "$summary_file")
[[ $? -ne 0 || -z "$assembly_bb_job_id" ]] && { echo "Error: Failed to submit BBNorm assembly job" >&2; exit 1; }
echo "Submitted BBNorm assembly job: $assembly_bb_job_id"

assembly_tr_job_id=$(sbatch --parsable \
    --job-name="assembly_tr" \
    --dependency="afterok:$trinity_norm_job_id" \
    --output="${logs_base}/05_assembly/trinity/assembly_%j.out" \
    --error="${logs_base}/05_assembly/trinity/assembly_%j.err" \
    "$SCRIPT_DIR/05_assembly.sh" "$norm_r1_tr" "$norm_r2_tr" "$assembly_tr_dir" "$logs_base/05_assembly/trinity" "$debug_mode" "$summary_file")
[[ $? -ne 0 || -z "$assembly_tr_job_id" ]] && { echo "Error: Failed to submit Trinity assembly job" >&2; exit 1; }
echo "Submitted Trinity assembly job: $assembly_tr_job_id"

# Submit BUSCO jobs
busco_bb_job_id=$(sbatch --parsable \
    --job-name="busco_bb" \
    --dependency="afterok:$assembly_bb_job_id" \
    --output="${logs_base}/06_busco/bbnorm/busco_%j.out" \
    --error="${logs_base}/06_busco/bbnorm/busco_%j.err" \
    "$SCRIPT_DIR/06_busco.sh" "$assembly_bb_dir/transcripts.fasta" "${result_base}/06_busco/bbnorm" "$logs_base/06_busco/bbnorm" "$debug_mode" "$summary_file" "bbnorm")
[[ $? -ne 0 || -z "$busco_bb_job_id" ]] && { echo "Error: Failed to submit BBNorm BUSCO job" >&2; exit 1; }
echo "Submitted BBNorm BUSCO job: $busco_bb_job_id"

busco_tr_job_id=$(sbatch --parsable \
    --job-name="busco_tr" \
    --dependency="afterok:$assembly_tr_job_id" \
    --output="${logs_base}/06_busco/trinity/busco_%j.out" \
    --error="${logs_base}/06_busco/trinity/busco_%j.err" \
    "$SCRIPT_DIR/06_busco.sh" "$assembly_tr_dir/transcripts.fasta" "${result_base}/06_busco/trinity" "$logs_base/06_busco/trinity" "$debug_mode" "$summary_file" "trinity")
[[ $? -ne 0 || -z "$busco_tr_job_id" ]] && { echo "Error: Failed to submit Trinity BUSCO job" >&2; exit 1; }
echo "Submitted Trinity BUSCO job: $busco_tr_job_id"

# Print job summary
echo "====== Job Summary ======"
echo "Trimming jobs: ${trim_job_ids[*]}"
echo "Merge jobs: $merge_job_id (R1), $merge_job_id_r2 (R2)"
echo "Pair check job: $pair_job_id"
echo "Normalization jobs: $bbnorm_job_id (BBNorm), $trinity_norm_job_id (Trinity)"
echo "Assembly jobs: $assembly_bb_job_id (BBNorm), $assembly_tr_job_id (Trinity)"
echo "BUSCO jobs: $busco_bb_job_id (BBNorm), $busco_tr_job_id (Trinity)"
echo "========================="

end_time=$(date +%s)
runtime=$((end_time - start_time))
echo "Pipeline setup completed in $runtime seconds"
echo "Monitor jobs with: squeue -u $USER"