#!/bin/bash

# SLURM parameters
#SBATCH --partition=day-long-cpu
#SBATCH --time=12:00:00
#SBATCH --nodes=1
#SBATCH --cpus-per-task=32
#SBATCH --mem=128G
#SBATCH --job-name=trinity_norm
# Log files specified at submission

# Get script directory for relative paths
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PIPELINE_DIR="$( dirname "$SCRIPT_DIR" )"
PIPELINE_NAME="$( basename "$PIPELINE_DIR" )"

# Input arguments from main.sh
FIXED_R1=$1
FIXED_R2=$2
NORM_R1=$3
NORM_R2=$4
LOG_DIR=${5:-"${PIPELINE_NAME}_logs/04_trinity_normalization"}
SUMMARY_FILE=${6:-"${PIPELINE_NAME}_logs/pipeline_summary.csv"}
DEBUG_MODE=${7:-false}

# Create output directories
mkdir -p $(dirname "$NORM_R1")
mkdir -p "$LOG_DIR"

# Set up logging
NORM_LOG="$LOG_DIR/trinity_normalize_$(date +%Y%m%d_%H%M%S).log"
echo "Starting Trinity normalization job at $(date)" > "$NORM_LOG"
echo "Input R1: $FIXED_R1" >> "$NORM_LOG"
echo "Input R2: $FIXED_R2" >> "$NORM_LOG"
echo "Output R1: $NORM_R1" >> "$NORM_LOG"
echo "Output R2: $NORM_R2" >> "$NORM_LOG"

# Debug mode: Skip if outputs exist
if [[ "$DEBUG_MODE" == "true" && -s "$NORM_R1" && -s "$NORM_R2" ]]; then
    echo "Debug mode: Normalized files already exist. Skipping normalization." | tee -a "$NORM_LOG"
    echo "TrinityNormalization,,Status,Skipped (files exist)" >> "$SUMMARY_FILE"
    exit 0
fi

# Check if input files exist
if [[ ! -s "$FIXED_R1" || ! -s "$FIXED_R2" ]]; then
    echo "Error: One or both input files are missing or empty!" | tee -a "$NORM_LOG"
    echo "FIXED_R1: $FIXED_R1 ($(du -h "$FIXED_R1" 2>/dev/null || echo 'missing'))" | tee -a "$NORM_LOG"
    echo "FIXED_R2: $FIXED_R2 ($(du -h "$FIXED_R2" 2>/dev/null || echo 'missing'))" | tee -a "$NORM_LOG"
    
    # Add error to summary
    echo "TrinityNormalization,,Status,Failed (missing input)" >> "$SUMMARY_FILE"
    exit 1
fi

# Activate Trinity Conda environment
source ~/.bashrc
conda activate trinity

# Start timing
start_time=$(date +%s)

# Create a temporary directory for Trinity normalization
TEMP_DIR=$(dirname "$NORM_R1")/trinity_norm_tmp
mkdir -p "$TEMP_DIR"

# Uncompress input files if they're gzipped
if [[ "$FIXED_R1" == *.gz && "$FIXED_R2" == *.gz ]]; then
    echo "Uncompressing input files for Trinity..." | tee -a "$NORM_LOG"
    UNCOMPRESSED_R1="$TEMP_DIR/$(basename "${FIXED_R1%.gz}")"
    UNCOMPRESSED_R2="$TEMP_DIR/$(basename "${FIXED_R2%.gz}")"
    
    gunzip -c "$FIXED_R1" > "$UNCOMPRESSED_R1"
    gunzip -c "$FIXED_R2" > "$UNCOMPRESSED_R2"
else
    UNCOMPRESSED_R1="$FIXED_R1"
    UNCOMPRESSED_R2="$FIXED_R2"
fi

# Run Trinity normalization
echo "Running Trinity normalization..." | tee -a "$NORM_LOG"

# Find Trinity installation directory
TRINITY_HOME=$(dirname $(which Trinity))/..

# Run the normalization command
$TRINITY_HOME/util/insilico_read_normalization.pl \
    --seqType fq \
    --JM 128G \
    --max_cov 100 \
    --left "$UNCOMPRESSED_R1" \
    --right "$UNCOMPRESSED_R2" \
    --pairs_together \
    --PARALLEL_STATS \
    --CPU $SLURM_CPUS_PER_TASK \
    --output "$TEMP_DIR" \
    2>> "$NORM_LOG"

# Check if normalization was successful
NORM_LEFT="$TEMP_DIR/left.norm.fq"
NORM_RIGHT="$TEMP_DIR/right.norm.fq"

if [[ $? -eq 0 && -s "$NORM_LEFT" && -s "$NORM_RIGHT" ]]; then
    # Compress the normalized files to the desired output locations
    echo "Compressing normalized files..." | tee -a "$NORM_LOG"
    gzip -c "$NORM_LEFT" > "$NORM_R1"
    gzip -c "$NORM_RIGHT" > "$NORM_R2"
    
    # Check if compression was successful
    if [[ -s "$NORM_R1" && -s "$NORM_R2" ]]; then
        end_time=$(date +%s)
        runtime=$((end_time - start_time))
        
        # Count reads in files
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
        echo "TrinityNormalization,,Status,Completed" >> "$SUMMARY_FILE"
        echo "TrinityNormalization,,Runtime,$runtime seconds" >> "$SUMMARY_FILE"
        echo "TrinityNormalization,,Reads Before,$before_r1_reads" >> "$SUMMARY_FILE"
        echo "TrinityNormalization,,Reads After,$after_r1_reads" >> "$SUMMARY_FILE"
        echo "TrinityNormalization,,Retention Rate,$retention_rate%" >> "$SUMMARY_FILE"
        
        # Clean up temporary files
        echo "Cleaning up temporary files..." | tee -a "$NORM_LOG"
        rm -rf "$TEMP_DIR"
        
        exit 0
    else
        echo "Error: Failed to compress normalized files!" | tee -a "$NORM_LOG"
        echo "TrinityNormalization,,Status,Failed (compression error)" >> "$SUMMARY_FILE"
        exit 1
    fi
else
    echo "Error: Trinity normalization failed!" | tee -a "$NORM_LOG"
    echo "TrinityNormalization,,Status,Failed" >> "$SUMMARY_FILE"
    exit 1
fi 