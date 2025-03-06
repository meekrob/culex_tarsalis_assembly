#! /bin/bash

# slurm parameters, see config/parameters.txt
#SBATCH --partition=short-cpu
#SBATCH --time=01:00:00
#SBATCH --nodes=1
#SBATCH --cpus-per-task=2
#SBATCH --mem=16G
#SBATCH --job-name=cat_merge
# Log files will be specified when submitting the job

# input file variables passed in as arguments from main_mosquito.sh
R1_LIST=$1  # File containing list of R1 files to merge
R2_LIST=$2  # File containing list of R2 files to merge
OUT_R1=$3   # Output merged R1 file
OUT_R2=$4   # Output merged R2 file
LOG_DIR=${5:-"logs/02_merge"}  # Directory for logs
SUMMARY_FILE=${6:-"logs/pipeline_summary.csv"}  # Summary file path
DEBUG_MODE=${7:-false}  # Debug mode flag

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

# Debug mode: Check if output files already exist
if [[ "$DEBUG_MODE" == "true" && -s "$OUT_R1" && -s "$OUT_R2" ]]; then
    echo "Debug mode: Merged files already exist: $OUT_R1, $OUT_R2. Skipping merging." | tee -a $MERGE_LOG
    
    # Add entry to summary file
    echo "Merging,,Status,Skipped (files exist)" >> "$SUMMARY_FILE"
    
    # Extract some basic stats for the summary file
    merged_r1_reads=$(zcat -f "$OUT_R1" | wc -l | awk '{print $1/4}')
    merged_r2_reads=$(zcat -f "$OUT_R2" | wc -l | awk '{print $1/4}')
    merged_r1_size=$(du -h "$OUT_R1" | cut -f1)
    merged_r2_size=$(du -h "$OUT_R2" | cut -f1)
    
    echo "Merging,,Merged R1 Reads,$merged_r1_reads" >> "$SUMMARY_FILE"
    echo "Merging,,Merged R2 Reads,$merged_r2_reads" >> "$SUMMARY_FILE"
    echo "Merging,,Merged R1 Size,$merged_r1_size" >> "$SUMMARY_FILE"
    echo "Merging,,Merged R2 Size,$merged_r2_size" >> "$SUMMARY_FILE"
    
    exit 0
fi

# activate conda env
source ~/.bashrc
conda activate cellSquito

echo "Merging R1 files from list: $R1_LIST"
echo "Merging R2 files from list: $R2_LIST"
echo "Output R1: $OUT_R1"
echo "Output R2: $OUT_R2"

# Function to merge files, handling missing files gracefully
merge_files() {
    local list_file=$1
    local output_file=$2
    local missing_count=0
    local total_count=0
    local valid_files=""
    
    echo "Processing file list: $list_file" | tee -a $MERGE_LOG
    
    # Check each file in the list
    while read file_path; do
        ((total_count++))
        if [[ -s "$file_path" ]]; then
            echo "  File exists: $file_path" >> $MERGE_LOG
            valid_files="$valid_files $file_path"
        else
            ((missing_count++))
            echo "  WARNING: Missing or empty file: $file_path" | tee -a $MERGE_LOG
            echo "Merging,,Missing File,$file_path" >> "$SUMMARY_FILE"
        fi
    done < $list_file
    
    echo "Found $missing_count missing files out of $total_count total files" | tee -a $MERGE_LOG
    
    if [[ $missing_count -eq $total_count ]]; then
        echo "ERROR: All input files are missing! Cannot create $output_file" | tee -a $MERGE_LOG
        echo "Merging,,Error,All input files missing for $(basename $output_file)" >> "$SUMMARY_FILE"
        return 1
    fi
    
    if [[ -z "$valid_files" ]]; then
        echo "ERROR: No valid files to merge!" | tee -a $MERGE_LOG
        return 1
    fi
    
    echo "Merging $((total_count - missing_count)) files into $output_file" | tee -a $MERGE_LOG
    
    # Use cat to merge the valid files
    echo $valid_files | xargs cat > $output_file
    
    if [[ $? -eq 0 && -s "$output_file" ]]; then
        echo "Successfully created $output_file" | tee -a $MERGE_LOG
        return 0
    else
        echo "ERROR: Failed to create $output_file" | tee -a $MERGE_LOG
        return 1
    fi
}

# Run merges in parallel
echo "Starting R1 merge..." | tee -a $MERGE_LOG
merge_files $R1_LIST $OUT_R1 &
pid1=$!

echo "Starting R2 merge..." | tee -a $MERGE_LOG
merge_files $R2_LIST $OUT_R2 &
pid2=$!

# Wait for both to finish
wait $pid1
r1_status=$?
wait $pid2
r2_status=$?

# Check if both processes completed successfully
if [[ $r1_status -eq 0 && $r2_status -eq 0 ]]; then
    echo "Merging completed successfully!" | tee -a $MERGE_LOG
    
    # Report file sizes
    merged_r1_size=$(du -h $OUT_R1 | cut -f1)
    merged_r2_size=$(du -h $OUT_R2 | cut -f1)
    echo "Merged R1 file size: $merged_r1_size" | tee -a $MERGE_LOG
    echo "Merged R2 file size: $merged_r2_size" | tee -a $MERGE_LOG
    
    # Count reads in merged files
    merged_r1_reads=$(zcat -f "$OUT_R1" | wc -l | awk '{print $1/4}')
    merged_r2_reads=$(zcat -f "$OUT_R2" | wc -l | awk '{print $1/4}')
    
    # Add statistics to summary file
    echo "Merging,,Status,Completed" >> "$SUMMARY_FILE"
    echo "Merging,,Merged R1 Reads,$merged_r1_reads" >> "$SUMMARY_FILE"
    echo "Merging,,Merged R2 Reads,$merged_r2_reads" >> "$SUMMARY_FILE"
    echo "Merging,,Merged R1 Size,$merged_r1_size" >> "$SUMMARY_FILE"
    echo "Merging,,Merged R2 Size,$merged_r2_size" >> "$SUMMARY_FILE"
else
    echo "Error: Merging failed!" | tee -a $MERGE_LOG
    echo "Merging,,Status,Failed" >> "$SUMMARY_FILE"
    exit 1
fi

# store results in results/02_merge

# output error and log files to logs directory mergefq_jobid. err and .out respectively