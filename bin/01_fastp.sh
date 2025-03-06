#!/bin/bash

# slurm parameters, see config/parameters.txt
#SBATCH --partition=short-cpu
#SBATCH --time=01:00:00
#SBATCH --nodes=1
#SBATCH --cpus-per-task=4
#SBATCH --mem=8G
#SBATCH --job-name=fastp
# Log files will be specified when submitting the job

# input file variables passed in as arguments from main.sh
R1=$1
R2=$2
OUT_R1=$3
OUT_R2=$4
SAMPLE_NAME=$5
LOG_DIR=${6:-"logs/01_trimming"}
DEBUG_MODE=${7:-false}

# Ensure output files have .gz extension
if [[ ! "$OUT_R1" == *.gz ]]; then
    OUT_R1="${OUT_R1}.gz"
fi
if [[ ! "$OUT_R2" == *.gz ]]; then
    OUT_R2="${OUT_R2}.gz"
fi

# Create output directory if it doesn't exist
mkdir -p $(dirname $OUT_R1)
mkdir -p $LOG_DIR

# Create a log file for this trimming job
TRIM_LOG="$LOG_DIR/${SAMPLE_NAME}_$(date +%Y%m%d_%H%M%S).log"
echo "Starting trimming job for $SAMPLE_NAME at $(date)" > $TRIM_LOG
echo "R1: $R1" >> $TRIM_LOG
echo "R2: $R2" >> $TRIM_LOG
echo "Output R1: $OUT_R1" >> $TRIM_LOG
echo "Output R2: $OUT_R2" >> $TRIM_LOG

# Debug mode: Check if output files already exist
if [[ "$DEBUG_MODE" == "true" && -s "$OUT_R1" && -s "$OUT_R2" ]]; then
    echo "Debug mode: Trimmed files already exist: $OUT_R1, $OUT_R2. Skipping trimming." | tee -a $TRIM_LOG
    exit 0
fi

# Run fastp
echo "Running fastp for $SAMPLE_NAME..." | tee -a $TRIM_LOG

# Set up fastp output files - directly in the trimmed directory
HTML_REPORT="$(dirname $OUT_R1)/${SAMPLE_NAME}_fastp.html"
JSON_REPORT="$(dirname $OUT_R1)/${SAMPLE_NAME}_fastp.json"

# Run fastp with appropriate parameters
fastp \
    -i "$R1" \
    -I "$R2" \
    -o "$OUT_R1" \
    -O "$OUT_R2" \
    --html "$HTML_REPORT" \
    --json "$JSON_REPORT" \
    --detect_adapter_for_pe \
    --cut_front \
    --cut_tail \
    --cut_window_size=4 \
    --cut_mean_quality=20 \
    --qualified_quality_phred=20 \
    --unqualified_percent_limit=40 \
    --n_base_limit=5 \
    --length_required=50 \
    --thread=4 \
    --compression=6 \
    2>> $TRIM_LOG

# Check if fastp completed successfully
if [[ $? -eq 0 && -s "$OUT_R1" && -s "$OUT_R2" ]]; then
    echo "Trimming completed successfully for $SAMPLE_NAME" | tee -a $TRIM_LOG
    
    # Get read counts
    raw_r1_reads=$(zcat -f "$R1" | wc -l | awk '{print $1/4}')
    raw_r2_reads=$(zcat -f "$R2" | wc -l | awk '{print $1/4}')
    trimmed_r1_reads=$(zcat -f "$OUT_R1" | wc -l | awk '{print $1/4}')
    trimmed_r2_reads=$(zcat -f "$OUT_R2" | wc -l | awk '{print $1/4}')
    
    # Calculate retention rate
    retention_rate=$(awk "BEGIN {printf \"%.2f\", ($trimmed_r1_reads / $raw_r1_reads) * 100}")
    
    echo "Raw R1 reads: $raw_r1_reads" | tee -a $TRIM_LOG
    echo "Raw R2 reads: $raw_r2_reads" | tee -a $TRIM_LOG
    echo "Trimmed R1 reads: $trimmed_r1_reads" | tee -a $TRIM_LOG
    echo "Trimmed R2 reads: $trimmed_r2_reads" | tee -a $TRIM_LOG
    echo "Retention rate: ${retention_rate}%" | tee -a $TRIM_LOG
else
    echo "Error: Trimming failed for $SAMPLE_NAME" | tee -a $TRIM_LOG
    exit 1
fi 