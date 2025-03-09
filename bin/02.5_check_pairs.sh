#!/bin/bash

# slurm parameters
#SBATCH --partition=day-long-highmem
#SBATCH --time=24:00:00
#SBATCH --nodes=1
#SBATCH --cpus-per-task=64
#SBATCH --mem=128G
#SBATCH --job-name=check_pairs
# Log files will be specified when submitting the job

# input file variables passed in as arguments from main.sh
MERGED_R1=$1
MERGED_R2=$2
FIXED_R1=$3
FIXED_R2=$4
LOG_DIR=${5:-"logs/02.5_check_pairs"}
SUMMARY_FILE=${6:-"logs/pipeline_summary.csv"}
DEBUG_MODE=${7:-false}

# Create output directory if it doesn't exist
mkdir -p $(dirname $FIXED_R1)
mkdir -p $LOG_DIR

# Create a log file for this pair checking job
CHECK_LOG="$LOG_DIR/check_pairs_$(date +%Y%m%d_%H%M%S).log"
echo "Starting paired-end consistency check at $(date)" > $CHECK_LOG
echo "Merged R1: $MERGED_R1" >> $CHECK_LOG
echo "Merged R2: $MERGED_R2" >> $CHECK_LOG
echo "Output R1: $FIXED_R1" >> $CHECK_LOG
echo "Output R2: $FIXED_R2" >> $CHECK_LOG

# Debug mode: Check if output files already exist
if [[ "$DEBUG_MODE" == "true" && -s "$FIXED_R1" && -s "$FIXED_R2" ]]; then
    echo "Debug mode: Fixed paired files already exist. Skipping pair check." | tee -a $CHECK_LOG
    echo "PairCheck,,Status,Skipped (files exist)" >> "$SUMMARY_FILE"
    exit 0
fi

# Check if input files exist
if [[ ! -s "$MERGED_R1" || ! -s "$MERGED_R2" ]]; then
    echo "Error: One or both input files are missing or empty!" | tee -a $CHECK_LOG
    echo "MERGED_R1: $MERGED_R1 ($(du -h $MERGED_R1 2>/dev/null || echo 'missing'))" | tee -a $CHECK_LOG
    echo "MERGED_R2: $MERGED_R2 ($(du -h $MERGED_R2 2>/dev/null || echo 'missing'))" | tee -a $CHECK_LOG
    
    # Add error to summary
    echo "PairCheck,,Status,Failed (missing input)" >> "$SUMMARY_FILE"
    exit 1
fi

# Activate conda environment
source ~/.bashrc
conda activate cellSquito

# Start timing
start_time=$(date +%s)

# Run repair.sh to check and fix paired-end consistency
echo "Running repair.sh to check and fix paired-end consistency..." | tee -a $CHECK_LOG

repair.sh \
    in1="$MERGED_R1" \
    in2="$MERGED_R2" \
    out1="$FIXED_R1" \
    out2="$FIXED_R2" \
    overwrite=t \
    tossbrokenreads=t \
    repair=t \
    showspeed=t \
    threads=$SLURM_CPUS_PER_TASK \
    2>> $CHECK_LOG

# Check if repair.sh completed successfully
if [[ $? -eq 0 && -s "$FIXED_R1" && -s "$FIXED_R2" ]]; then
    end_time=$(date +%s)
    runtime=$((end_time - start_time))
    
    # Count reads in fixed files
    r1_reads=$(zcat -f "$FIXED_R1" | wc -l | awk '{print $1/4}')
    r2_reads=$(zcat -f "$FIXED_R2" | wc -l | awk '{print $1/4}')
    
    # Count reads in original merged files
    orig_r1_reads=$(zcat -f "$MERGED_R1" | wc -l | awk '{print $1/4}')
    orig_r2_reads=$(zcat -f "$MERGED_R2" | wc -l | awk '{print $1/4}')
    
    echo "Original R1 reads: $orig_r1_reads" | tee -a $CHECK_LOG
    echo "Original R2 reads: $orig_r2_reads" | tee -a $CHECK_LOG
    echo "Fixed R1 reads: $r1_reads" | tee -a $CHECK_LOG
    echo "Fixed R2 reads: $r2_reads" | tee -a $CHECK_LOG
    
    # Calculate percentage of reads retained
    if [[ $orig_r1_reads -gt 0 && $orig_r2_reads -gt 0 ]]; then
        retention_rate=$(awk "BEGIN {printf \"%.2f\", ($r1_reads / (($orig_r1_reads + $orig_r2_reads) / 2)) * 100}")
        echo "Retention rate: ${retention_rate}%" | tee -a $CHECK_LOG
    else
        retention_rate="N/A"
        echo "Warning: Cannot calculate retention rate (original read count is zero)" | tee -a $CHECK_LOG
    fi
    
    # Verify that fixed files have the same number of reads
    if [[ "$r1_reads" -eq "$r2_reads" ]]; then
        echo "Pair check passed: $r1_reads reads in both files" | tee -a $CHECK_LOG
        echo "Pair checking completed successfully in $runtime seconds" | tee -a $CHECK_LOG
        
        # Add to summary file
        echo "PairCheck,,Status,Completed" >> "$SUMMARY_FILE"
        echo "PairCheck,,Runtime,$runtime seconds" >> "$SUMMARY_FILE"
        echo "PairCheck,,Reads,$r1_reads" >> "$SUMMARY_FILE"
        echo "PairCheck,,Retention,$retention_rate%" >> "$SUMMARY_FILE"
        
        exit 0
    else
        echo "Error: Read counts differ after repair (R1: $r1_reads, R2: $r2_reads)" | tee -a $CHECK_LOG
        echo "PairCheck,,Status,Failed (count mismatch)" >> "$SUMMARY_FILE"
        exit 1
    fi
else
    echo "Error: repair.sh failed!" | tee -a $CHECK_LOG
    echo "PairCheck,,Status,Failed (repair error)" >> "$SUMMARY_FILE"
    exit 1
fi 