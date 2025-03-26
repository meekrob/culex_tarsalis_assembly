#!/bin/bash

# SLURM parameters
#SBATCH --partition=day-long-cpu
#SBATCH --time=12:00:00
#SBATCH --nodes=1
#SBATCH --cpus-per-task=32
#SBATCH --mem=128G
#SBATCH --job-name=normalize
# Log files specified at submission

# Input arguments from main.sh
FIXED_R1=$1
FIXED_R2=$2
NORM_R1=$3
NORM_R2=$4
LOG_DIR=${5:-"logs/02.75_normalization"}
SUMMARY_FILE=${6:-"logs/pipeline_summary.csv"}
DEBUG_MODE=${7:-false}

# Create output directories
mkdir -p $(dirname "$NORM_R1")
mkdir -p "$LOG_DIR"

# Set up logging
NORM_LOG="$LOG_DIR/normalize_$(date +%Y%m%d_%H%M%S).log"
echo "Starting normalization job at $(date)" > "$NORM_LOG"
echo "Input R1: $FIXED_R1" >> "$NORM_LOG"
echo "Input R2: $FIXED_R2" >> "$NORM_LOG"
echo "Output R1: $NORM_R1" >> "$NORM_LOG"
echo "Output R2: $NORM_R2" >> "$NORM_LOG"

# Debug mode: Skip if outputs exist
if [[ "$DEBUG_MODE" == "true" && -s "$NORM_R1" && -s "$NORM_R2" ]]; then
    echo "Debug mode: Normalized files already exist. Skipping normalization." | tee -a "$NORM_LOG"
    echo "Normalization,,Status,Skipped (files exist)" >> "$SUMMARY_FILE"
    exit 0
fi

# Check if input files exist
if [[ ! -s "$FIXED_R1" || ! -s "$FIXED_R2" ]]; then
    echo "Error: One or both input files are missing or empty!" | tee -a "$NORM_LOG"
    echo "FIXED_R1: $FIXED_R1 ($(du -h "$FIXED_R1" 2>/dev/null || echo 'missing'))" | tee -a "$NORM_LOG"
    echo "FIXED_R2: $FIXED_R2 ($(du -h "$FIXED_R2" 2>/dev/null || echo 'missing'))" | tee -a "$NORM_LOG"
    
    # Add error to summary
    echo "Normalization,,Status,Failed (missing input)" >> "$SUMMARY_FILE"
    exit 1
fi

# Activate Conda environment
source ~/.bashrc
conda activate cellSquito

# Start timing
start_time=$(date +%s)

# Run BBNorm for read normalization
echo "Running BBNorm for read normalization..." | tee -a "$NORM_LOG"
HIST_FILE="$LOG_DIR/kmer_histogram.txt"

bbnorm.sh \
    in1="$FIXED_R1" \
    in2="$FIXED_R2" \
    out1="$NORM_R1" \
    out2="$NORM_R2" \
    hist="$HIST_FILE" \
    target=100 \
    min=5 \
    threads=$SLURM_CPUS_PER_TASK \
    ecc=t \
    prefilter=t \
    2>> "$NORM_LOG"

# Check if normalization was successful
if [[ $? -eq 0 && -s "$NORM_R1" && -s "$NORM_R2" ]]; then
    end_time=$(date +%s)
    runtime=$((end_time - start_time))
    
    # Count reads in files
    # Using zcat for gzipped files, could use pigz -dc if available
    before_r1_reads=$(zcat -f "$FIXED_R1" | wc -l | awk '{print $1/4}')
    before_r2_reads=$(zcat -f "$FIXED_R2" | wc -l | awk '{print $1/4}')
    after_r1_reads=$(zcat -f "$NORM_R1" | wc -l | awk '{print $1/4}')
    after_r2_reads=$(zcat -f "$NORM_R2" | wc -l | awk '{print $1/4}')
    
    # Calculate retention rate
    retention_rate=$(awk "BEGIN {printf \"%.2f\", ($after_r1_reads / $before_r1_reads) * 100}")
    
    echo "Reads before normalization (R1): $before_r1_reads" | tee -a "$NORM_LOG"
    echo "Reads before normalization (R2): $before_r2_reads" | tee -a "$NORM_LOG"
    echo "Reads after normalization (R1): $after_r1_reads" | tee -a "$NORM_LOG"
    echo "Reads after normalization (R2): $after_r2_reads" | tee -a "$NORM_LOG"
    echo "Retention rate: ${retention_rate}%" | tee -a "$NORM_LOG"
    
    # Add to summary file
    echo "Normalization,,Status,Completed" >> "$SUMMARY_FILE"
    echo "Normalization,,Runtime,$runtime seconds" >> "$SUMMARY_FILE"
    echo "Normalization,,Reads Before,$before_r1_reads" >> "$SUMMARY_FILE"
    echo "Normalization,,Reads After,$after_r1_reads" >> "$SUMMARY_FILE"
    echo "Normalization,,Retention Rate,$retention_rate%" >> "$SUMMARY_FILE"
    
    exit 0
else
    echo "Error: Normalization failed!" | tee -a "$NORM_LOG"
    echo "Normalization,,Status,Failed" >> "$SUMMARY_FILE"
    exit 1
fi 