#!/bin/bash

# slurm parameters, see config/parameters.txt
#SBATCH --partition=day-long-cpu
#SBATCH --time=02:00:00          # Reduced time since each job does less work
#SBATCH --nodes=1
#SBATCH --cpus-per-task=32
#SBATCH --mem=64G
#SBATCH --job-name=cat_merge
# Log files will be specified when submitting the job

# input variables passed in as arguments from main.sh
FILE_LIST=$1   # File containing list of files to merge
OUTPUT_FILE=$2 # Output merged file
FILE_TYPE=$3   # R1 or R2 identifier
LOG_DIR=${4:-"logs/02_merge"}  # Directory for logs
DEBUG_MODE=${5:-false}  # Debug mode flag
SUMMARY_FILE=${6:-"logs/pipeline_summary.csv"}  # Summary file path

# Create output directory if it doesn't exist
mkdir -p $(dirname $OUTPUT_FILE)
mkdir -p $LOG_DIR

# Create a log file for this merge job
MERGE_LOG="$LOG_DIR/merge_${FILE_TYPE}_$(date +%Y%m%d_%H%M%S).log"
echo "Starting $FILE_TYPE merge job at $(date)" > $MERGE_LOG
echo "File list: $FILE_LIST" >> $MERGE_LOG
echo "Output file: $OUTPUT_FILE" >> $MERGE_LOG

# Debug mode: Check if output file already exists
if [[ "$DEBUG_MODE" == "true" && -s "$OUTPUT_FILE" ]]; then
    echo "Debug mode: Merged $FILE_TYPE file already exists. Skipping merge." | tee -a $MERGE_LOG
    echo "Merge,$FILE_TYPE,Status,Skipped (file exists)" >> "$SUMMARY_FILE"
    exit 0
fi

# Check if input list exists
if [[ ! -s "$FILE_LIST" ]]; then
    echo "Error: Input list $FILE_LIST is missing or empty!" | tee -a $MERGE_LOG
    echo "Merge,$FILE_TYPE,Status,Failed (missing input list)" >> "$SUMMARY_FILE"
    exit 1
fi

# Load conda environment for pigz
source ~/.bashrc
conda activate cellSquito &>/dev/null || true

# Check if pigz is available
if command -v pigz >/dev/null 2>&1; then
    COMPRESS_CMD="pigz -p $SLURM_CPUS_PER_TASK"
    DECOMPRESS_CMD="pigz -dc -p $SLURM_CPUS_PER_TASK"
    echo "Using pigz for parallel compression/decompression with $SLURM_CPUS_PER_TASK cores" | tee -a $MERGE_LOG
else
    COMPRESS_CMD="gzip"
    DECOMPRESS_CMD="zcat"
    echo "Warning: pigz not found, using slower gzip/zcat" | tee -a $MERGE_LOG
fi

# Count total files
total_files=$(wc -l < $FILE_LIST)
echo "Total $FILE_TYPE files to merge: $total_files" | tee -a $MERGE_LOG

# Verify input files exist
echo "Verifying input files..." | tee -a $MERGE_LOG
missing_files=0

while IFS= read -r file; do
    if [[ ! -s "$file" ]]; then
        echo "  Missing file: $file" | tee -a $MERGE_LOG
        missing_files=$((missing_files + 1))
    fi
done < "$FILE_LIST"

if [[ $missing_files -gt 0 ]]; then
    echo "Error: Found $missing_files missing input files" | tee -a $MERGE_LOG
    echo "Merge,$FILE_TYPE,Status,Failed (missing input files)" >> "$SUMMARY_FILE"
    exit 1
fi

echo "All input files verified successfully" | tee -a $MERGE_LOG

# Start timing
start_time=$(date +%s)

# Set up temporary uncompressed file
TEMP_DIR="$(dirname $OUTPUT_FILE)"
TEMP_FILE="$TEMP_DIR/merged_${FILE_TYPE}_temp.fastq"

echo "Creating uncompressed merge first in $TEMP_FILE..." | tee -a $MERGE_LOG

# Remove existing temp file if it exists
rm -f $TEMP_FILE

# Process files in blocks of 4 for better I/O management
block_size=4
total_blocks=$(( (total_files + block_size - 1) / block_size ))
current_block=0
processed=0

# Create a temporary file list for the current block
BLOCK_LIST="$TEMP_DIR/block_${FILE_TYPE}_$$.txt"

while (( processed < total_files )); do
    current_block=$((current_block + 1))
    echo "Processing block $current_block of $total_blocks (files $(( processed + 1 ))-$(( processed + block_size < total_files ? processed + block_size : total_files )))" | tee -a $MERGE_LOG
    
    # Create a list of files for this block
    rm -f $BLOCK_LIST
    head -n $(( processed + block_size )) "$FILE_LIST" | tail -n $block_size > $BLOCK_LIST
    
    # Merge this block of files
    while IFS= read -r file; do
        processed=$((processed + 1))
        echo "  Processing file $processed/$total_files ($(( processed * 100 / total_files ))%): $(basename $file)" | tee -a $MERGE_LOG
        
        # Direct append to avoid creating new processes
        $DECOMPRESS_CMD "$file" >> $TEMP_FILE
        
    done < $BLOCK_LIST
done

# Clean up block list
rm -f $BLOCK_LIST

# Check if merge was successful
if [[ ! -s "$TEMP_FILE" ]]; then
    echo "Error: Failed to create merged uncompressed file!" | tee -a $MERGE_LOG
    echo "Merge,$FILE_TYPE,Status,Failed (merge error)" >> "$SUMMARY_FILE"
    exit 1
fi

echo "Successfully created uncompressed merged file" | tee -a $MERGE_LOG
uncompressed_size=$(du -h $TEMP_FILE | cut -f1)
echo "Uncompressed $FILE_TYPE size: $uncompressed_size" | tee -a $MERGE_LOG

# Compress the merged file
echo "Compressing merged file..." | tee -a $MERGE_LOG
if [[ -e "$OUTPUT_FILE" ]]; then rm -f "$OUTPUT_FILE"; fi

# Compress with maximum speed (-1) since we're more concerned with time than space
$COMPRESS_CMD -1 < $TEMP_FILE > $OUTPUT_FILE
compress_status=$?

# Remove the temporary uncompressed file
echo "Removing temporary uncompressed file..." | tee -a $MERGE_LOG
rm -f $TEMP_FILE

# Check if compression was successful
if [[ $compress_status -eq 0 && -s "$OUTPUT_FILE" ]]; then
    end_time=$(date +%s)
    runtime=$((end_time - start_time))
    
    echo "Merging and compression completed successfully in $runtime seconds!" | tee -a $MERGE_LOG
    
    # Report file size
    merged_size=$(du -h $OUTPUT_FILE | cut -f1)
    echo "Merged $FILE_TYPE file size: $merged_size" | tee -a $MERGE_LOG
    
    # Add to summary file
    echo "Merge,$FILE_TYPE,Status,Completed" >> "$SUMMARY_FILE"
    echo "Merge,$FILE_TYPE,Runtime,$runtime seconds" >> "$SUMMARY_FILE"
    echo "Merge,$FILE_TYPE,Size,$merged_size" >> "$SUMMARY_FILE"
    
    exit 0
else
    echo "Error: Compression failed with status $compress_status!" | tee -a $MERGE_LOG
    echo "Merge,$FILE_TYPE,Status,Failed (compression error)" >> "$SUMMARY_FILE"
    exit 1
fi

# output error and log files to logs directory mergefq_jobid. err and .out respectively