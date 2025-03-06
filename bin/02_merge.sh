#!/bin/bash

# slurm parameters, see config/parameters.txt
#SBATCH --partition=short-cpu
#SBATCH --time=04:00:00          # Increased time limit
#SBATCH --nodes=1
#SBATCH --cpus-per-task=16       # More CPUs for parallel processing
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
CHUNK_SIZE=${8:-5}      # Number of files to process in each chunk

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

# Create temporary directory for processing
TMP_DIR=$(mktemp -d -p "${TMPDIR:-/tmp}" merge_XXXXXXXX)
trap 'rm -rf "$TMP_DIR"' EXIT

# Get start time
start_time=$(date +%s)

# Function to merge files in chunks with progress tracking
merge_files_in_chunks() {
    local file_list=$1
    local output_file=$2
    local file_type=$3
    local tmp_output="$TMP_DIR/${file_type}_merged.fastq"
    local total_files=$(wc -l < $file_list)
    local chunk_start=1
    local files_processed=0
    
    # Remove output file if it exists
    rm -f "$output_file"
    
    # Process in chunks
    while [[ $files_processed -lt $total_files ]]; do
        # Calculate how many files to process in this chunk (min of CHUNK_SIZE or remaining files)
        local remaining=$((total_files - files_processed))
        local chunk_size=$((remaining < CHUNK_SIZE ? remaining : CHUNK_SIZE))
        local chunk_end=$((files_processed + chunk_size))
        
        echo "  Processing $file_type chunk: files $((files_processed+1))-$chunk_end of $total_files" | tee -a $MERGE_LOG
        
        # Create temporary file with file paths for this chunk
        local chunk_list="$TMP_DIR/${file_type}_chunk_${files_processed}.txt"
        sed -n "$((files_processed+1)),$chunk_end p" $file_list > $chunk_list
        
        # Create temporary output for this chunk
        local chunk_output="$TMP_DIR/${file_type}_chunk_${files_processed}.fastq"
        
        # Merge this chunk of files
        if ! (cat $chunk_list | xargs $DECOMPRESS_CMD > $chunk_output); then
            echo "  Error merging chunk $((files_processed+1))-$chunk_end for $file_type!" | tee -a $MERGE_LOG
            return 1
        fi
        
        # Append to main output or set as main output if first chunk
        if [[ $files_processed -eq 0 ]]; then
            mv $chunk_output $tmp_output
        else
            cat $chunk_output >> $tmp_output
            rm $chunk_output
        fi
        
        # Clean up chunk file list
        rm $chunk_list
        
        # Update processed count
        files_processed=$chunk_end
        
        # Calculate and display progress
        local progress=$((files_processed * 100 / total_files))
        echo "  Progress: $progress% complete for $file_type" | tee -a $MERGE_LOG
    done
    
    # Compress final output with maximum parallelism
    echo "  Compressing final $file_type output..." | tee -a $MERGE_LOG
    
    if [[ "$COMPRESS_CMD" == "pigz" ]]; then
        # Use pigz with all available cores
        cat $tmp_output | $COMPRESS_CMD -p $SLURM_CPUS_PER_TASK > $output_file
    else
        # Use standard gzip
        cat $tmp_output | $COMPRESS_CMD > $output_file
    fi
    
    # Check if compression was successful
    if [[ $? -eq 0 && -s $output_file ]]; then
        echo "  Successfully created $output_file" | tee -a $MERGE_LOG
        rm $tmp_output
        return 0
    else
        echo "  Error compressing final $file_type output!" | tee -a $MERGE_LOG
        return 1
    fi
}

# Process R1 and R2 files in parallel
echo "Merging R1 files from list: $R1_LIST" | tee -a $MERGE_LOG
echo "Merging R2 files from list: $R2_LIST" | tee -a $MERGE_LOG
echo "Output R1: $OUT_R1" | tee -a $MERGE_LOG
echo "Output R2: $OUT_R2" | tee -a $MERGE_LOG

# Split available CPUs between the two processes
HALF_CPUS=$((SLURM_CPUS_PER_TASK / 2))
if [[ $HALF_CPUS -lt 1 ]]; then HALF_CPUS=1; fi

# Launch R1 and R2 merging in parallel with controlled CPU usage
{
    export OMP_NUM_THREADS=$HALF_CPUS
    echo "Starting R1 merge with $HALF_CPUS threads..." | tee -a $MERGE_LOG
    merge_files_in_chunks "$R1_LIST" "$OUT_R1" "R1"
    r1_status=$?
} &
pid1=$!

{
    export OMP_NUM_THREADS=$HALF_CPUS
    echo "Starting R2 merge with $HALF_CPUS threads..." | tee -a $MERGE_LOG
    merge_files_in_chunks "$R2_LIST" "$OUT_R2" "R2"
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
    
    # Count reads in merged files
    echo "Counting reads in merged files (this may take a moment)..." | tee -a $MERGE_LOG
    merged_r1_reads=$($DECOMPRESS_CMD "$OUT_R1" | awk 'NR%4==1' | wc -l)
    merged_r2_reads=$($DECOMPRESS_CMD "$OUT_R2" | awk 'NR%4==1' | wc -l)
    
    echo "Merged R1 reads: $merged_r1_reads" | tee -a $MERGE_LOG
    echo "Merged R2 reads: $merged_r2_reads" | tee -a $MERGE_LOG
    
    # Add to summary file
    echo "Merge,,Status,Completed" >> "$SUMMARY_FILE"
    echo "Merge,,Runtime,$runtime seconds" >> "$SUMMARY_FILE"
    echo "Merge,,R1 Reads,$merged_r1_reads" >> "$SUMMARY_FILE"
    echo "Merge,,R2 Reads,$merged_r2_reads" >> "$SUMMARY_FILE"
    echo "Merge,,R1 Size,$merged_r1_size" >> "$SUMMARY_FILE"
    echo "Merge,,R2 Size,$merged_r2_size" >> "$SUMMARY_FILE"
    
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