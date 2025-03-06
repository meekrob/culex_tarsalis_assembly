#!/bin/bash

# slurm parameters, see config/parameters.txt
#SBATCH --partition=day-long-cpu
#SBATCH --time=04:00:00          # Increased time limit
#SBATCH --nodes=1
#SBATCH --cpus-per-task=32       # Increased CPUs for parallel processing
#SBATCH --mem=64G                # More memory for efficient buffering
#SBATCH --job-name=cat_merge
# Log files will be specified when submitting the job

# input variables passed in as arguments from main.sh
R1_LIST=$1  # File containing list of R1 files to merge
R2_LIST=$2  # File containing list of R2 files to merge
OUT_R1=$3   # Output merged R1 file
OUT_R2=$4   # Output merged R2 file
LOG_DIR=${5:-"logs/02_merge"}  # Directory for logs
DEBUG_MODE=${6:-false}  # Debug mode flag
SUMMARY_FILE=${7:-"logs/pipeline_summary.csv"}  # Summary file path

# Create output directory if it doesn't exist
mkdir -p $(dirname $OUT_R1)
mkdir -p $LOG_DIR

# Create a log file for this merge job
MERGE_LOG="$LOG_DIR/merge_$(date +%Y%m%d_%H%M%S).log"
echo "Starting merge job at $(date)" > $MERGE_LOG
echo "R1 list: $R1_LIST" >> $MERGE_LOG
echo "R2 list: $R2_LIST" >> $MERGE_LOG
echo "Output R1: $OUT_R1" >> $MERGE_LOG
echo "Output R2: $OUT_R2" >> $MERGE_LOG

# Check if output files already exist and debug mode is enabled
if [[ "$DEBUG_MODE" == "true" && -s "$OUT_R1" && -s "$OUT_R2" ]]; then
    echo "Debug mode: Merged files already exist. Skipping merge." | tee -a $MERGE_LOG
    
    # Add skipped status to summary file
    echo "Merge,,Status,Skipped (files exist)" >> "$SUMMARY_FILE"
    
    # Get file sizes for reporting
    r1_size=$(du -h $OUT_R1 | cut -f1)
    r2_size=$(du -h $OUT_R2 | cut -f1)
    
    echo "Merged R1 file size: $r1_size" | tee -a $MERGE_LOG
    echo "Merged R2 file size: $r2_size" | tee -a $MERGE_LOG
    
    exit 0
fi

# Make sure input file lists exist
if [[ ! -s "$R1_LIST" || ! -s "$R2_LIST" ]]; then
    echo "Error: One or both input lists are missing or empty!" | tee -a $MERGE_LOG
    echo "R1 list: $R1_LIST ($(test -f $R1_LIST && echo "exists" || echo "missing"))" | tee -a $MERGE_LOG
    echo "R2 list: $R2_LIST ($(test -f $R2_LIST && echo "exists" || echo "missing"))" | tee -a $MERGE_LOG
    
    # Add failure to summary file
    echo "Merge,,Status,Failed (missing input lists)" >> "$SUMMARY_FILE"
    
    exit 1
fi

# Load conda environment if needed
source ~/.bashrc
conda activate cellSquito &>/dev/null || true  # Continue if conda activation fails

# Check if pigz is available for parallel compression
if command -v pigz >/dev/null 2>&1; then
    COMPRESS_CMD="pigz"
    DECOMPRESS_CMD="pigz -dc"
    echo "Using pigz for parallel compression/decompression" | tee -a $MERGE_LOG
else
    COMPRESS_CMD="gzip"
    DECOMPRESS_CMD="zcat"
    echo "Using standard gzip/zcat" | tee -a $MERGE_LOG
fi

# Count total files
total_r1_files=$(wc -l < $R1_LIST)
total_r2_files=$(wc -l < $R2_LIST)
echo "Total R1 files to merge: $total_r1_files" | tee -a $MERGE_LOG
echo "Total R2 files to merge: $total_r2_files" | tee -a $MERGE_LOG

# Verify all input files exist
echo "Verifying input files..." | tee -a $MERGE_LOG
missing_files=0

check_files_existence() {
    local file_list=$1
    local log_file=$2
    local file_type=$3
    local missing=0
    
    while IFS= read -r file; do
        if [[ ! -s "$file" ]]; then
            echo "  Missing $file_type file: $file" | tee -a $log_file
            missing=$((missing + 1))
        fi
    done < "$file_list"
    
    return $missing
}

# Check R1 files
check_files_existence "$R1_LIST" "$MERGE_LOG" "R1"
missing_r1=$?

# Check R2 files
check_files_existence "$R2_LIST" "$MERGE_LOG" "R2" 
missing_r2=$?

# If any files are missing, exit
if [[ $missing_r1 -gt 0 || $missing_r2 -gt 0 ]]; then
    echo "Error: Found $missing_r1 missing R1 files and $missing_r2 missing R2 files" | tee -a $MERGE_LOG
    echo "Merge,,Status,Failed (missing input files)" >> "$SUMMARY_FILE"
    exit 1
fi

echo "All input files verified successfully" | tee -a $MERGE_LOG

# Get start time
start_time=$(date +%s)

# Function to stream-merge files directly to compressed output
stream_merge_files() {
    local file_list=$1
    local output_file=$2
    local file_type=$3
    local total_files=$(wc -l < $file_list)
    local files_processed=0
    
    echo "Starting direct stream merge for $file_type to $output_file..." | tee -a $MERGE_LOG
    
    # Create a fifo pipe for streaming
    local pipe=$(mktemp -u)
    mkfifo $pipe
    
    # Start compression in background using all CPU cores
    if [[ "$COMPRESS_CMD" == "pigz" ]]; then
        $COMPRESS_CMD -p $SLURM_CPUS_PER_TASK < $pipe > $output_file &
    else
        $COMPRESS_CMD < $pipe > $output_file &
    fi
    compress_pid=$!
    
    # Stream each file through the pipe with progress reporting
    while IFS= read -r file; do
        files_processed=$((files_processed + 1))
        
        # Calculate progress percentage
        local progress=$((files_processed * 100 / total_files))
        echo "  Processing $file_type file $files_processed/$total_files ($progress%): $(basename "$file")" | tee -a $MERGE_LOG
        
        # Stream this file through the pipe
        $DECOMPRESS_CMD "$file" >> $pipe
    done < "$file_list"
    
    # Close the pipe to finish compression
    exec {pipe}>&-
    
    # Wait for compression to complete
    wait $compress_pid
    local status=$?
    
    # Clean up
    rm -f $pipe
    
    # Check if compression was successful
    if [[ $status -eq 0 && -s "$output_file" ]]; then
        echo "  Successfully created $output_file" | tee -a $MERGE_LOG
        return 0
    else
        echo "  Error in stream merge for $file_type!" | tee -a $MERGE_LOG
        return 1
    fi
}

# Process R1 and R2 files in parallel with different CPU allocations
# Use more cores for compression (2/3) and fewer for decompression (1/3)
COMPRESS_CORES=$((SLURM_CPUS_PER_TASK * 2 / 3))
DECOMPRESS_CORES=$((SLURM_CPUS_PER_TASK / 3))
if [[ $COMPRESS_CORES -lt 1 ]]; then COMPRESS_CORES=1; fi
if [[ $DECOMPRESS_CORES -lt 1 ]]; then DECOMPRESS_CORES=1; fi

echo "Merging R1 files from list: $R1_LIST" | tee -a $MERGE_LOG
echo "Merging R2 files from list: $R2_LIST" | tee -a $MERGE_LOG
echo "Output R1: $OUT_R1" | tee -a $MERGE_LOG
echo "Output R2: $OUT_R2" | tee -a $MERGE_LOG
echo "Using $COMPRESS_CORES cores for compression and $DECOMPRESS_CORES cores for decompression" | tee -a $MERGE_LOG

# Launch R1 merge
{
    export OMP_NUM_THREADS=$DECOMPRESS_CORES
    echo "Starting R1 merge..." | tee -a $MERGE_LOG
    stream_merge_files "$R1_LIST" "$OUT_R1" "R1"
    r1_status=$?
} &
pid1=$!

# Launch R2 merge after a small delay to avoid resource contention
sleep 2

{
    export OMP_NUM_THREADS=$DECOMPRESS_CORES
    echo "Starting R2 merge..." | tee -a $MERGE_LOG
    stream_merge_files "$R2_LIST" "$OUT_R2" "R2"
    r2_status=$?
} &
pid2=$!

# Wait for both processes to complete
wait $pid1 || true
wait $pid2 || true

# Check if both merges completed successfully
if [[ $r1_status -eq 0 && $r2_status -eq 0 && -s "$OUT_R1" && -s "$OUT_R2" ]]; then
    end_time=$(date +%s)
    runtime=$((end_time - start_time))
    
    echo "Merging completed successfully in $runtime seconds!" | tee -a $MERGE_LOG
    
    # Report file sizes
    merged_r1_size=$(du -h $OUT_R1 | cut -f1)
    merged_r2_size=$(du -h $OUT_R2 | cut -f1)
    echo "Merged R1 file size: $merged_r1_size" | tee -a $MERGE_LOG
    echo "Merged R2 file size: $merged_r2_size" | tee -a $MERGE_LOG
    
    # Count reads in merged files (sample only first million lines for speed)
    echo "Sampling reads in merged files..." | tee -a $MERGE_LOG
    merged_r1_sample=$($DECOMPRESS_CMD "$OUT_R1" | head -n 1000000 | awk 'NR%4==1' | wc -l)
    merged_r2_sample=$($DECOMPRESS_CMD "$OUT_R2" | head -n 1000000 | awk 'NR%4==1' | wc -l)
    
    # Estimate total reads based on file sizes and sample
    sample_size=1000000
    r1_bytes=$(stat -c%s "$OUT_R1")
    r2_bytes=$(stat -c%s "$OUT_R2")
    r1_est_reads=$(echo "scale=0; ($merged_r1_sample * $r1_bytes) / ($sample_size * 4)" | bc)
    r2_est_reads=$(echo "scale=0; ($merged_r2_sample * $r2_bytes) / ($sample_size * 4)" | bc)
    
    echo "Estimated R1 reads: ~$r1_est_reads" | tee -a $MERGE_LOG
    echo "Estimated R2 reads: ~$r2_est_reads" | tee -a $MERGE_LOG
    
    # Add to summary file
    echo "Merge,,Status,Completed" >> "$SUMMARY_FILE"
    echo "Merge,,Runtime,$runtime seconds" >> "$SUMMARY_FILE"
    echo "Merge,,R1 Size,$merged_r1_size" >> "$SUMMARY_FILE"
    echo "Merge,,R2 Size,$merged_r2_size" >> "$SUMMARY_FILE"
    echo "Merge,,Estimated R1 Reads,$r1_est_reads" >> "$SUMMARY_FILE"
    echo "Merge,,Estimated R2 Reads,$r2_est_reads" >> "$SUMMARY_FILE"
    
    exit 0
else
    echo "Error: Merging failed!" | tee -a $MERGE_LOG
    
    # Check specific failures
    if [[ $r1_status -ne 0 ]]; then
        echo "R1 merging failed with status $r1_status" | tee -a $MERGE_LOG
    fi
    
    if [[ $r2_status -ne 0 ]]; then
        echo "R2 merging failed with status $r2_status" | tee -a $MERGE_LOG
    fi
    
    if [[ ! -s "$OUT_R1" ]]; then
        echo "Output R1 file is missing or empty" | tee -a $MERGE_LOG
    fi
    
    if [[ ! -s "$OUT_R2" ]]; then
        echo "Output R2 file is missing or empty" | tee -a $MERGE_LOG
    fi
    
    # Add to summary file
    echo "Merge,,Status,Failed" >> "$SUMMARY_FILE"
    
    exit 1
fi

# output error and log files to logs directory mergefq_jobid. err and .out respectively