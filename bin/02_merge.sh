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
DEBUG_MODE=${6:-false}  # Debug mode flag

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
    
    exit 0
fi

# activate conda env
source ~/.bashrc
conda activate cellSquito

echo "Merging R1 files from list: $R1_LIST"
echo "Merging R2 files from list: $R2_LIST"
echo "Output R1: $OUT_R1"
echo "Output R2: $OUT_R2"

# Function to merge files and handle missing files
merge_files() {
    local file_list=$1
    local output_file=$2
    local valid_files=""
    local missing_files=0
    
    echo "Checking files in $file_list..." | tee -a $MERGE_LOG
    
    # Check each file in the list
    while IFS= read -r file; do
        if [[ -s "$file" ]]; then
            echo "  File exists: $file" >> $MERGE_LOG
            valid_files="$valid_files $file"
        else
            echo "  WARNING: Missing or empty file: $file" | tee -a $MERGE_LOG
            missing_files=$((missing_files + 1))
        fi
    done < "$file_list"
    
    # Report missing files
    if [[ $missing_files -gt 0 ]]; then
        echo "WARNING: $missing_files files are missing or empty" | tee -a $MERGE_LOG
    fi
    
    # If no valid files, exit with error
    if [[ -z "$valid_files" ]]; then
        echo "ERROR: No valid files to merge!" | tee -a $MERGE_LOG
        return 1
    fi
    
    # Merge valid files - check if files are gzipped
    echo "Merging $(echo $valid_files | wc -w) files into $output_file..." | tee -a $MERGE_LOG
    
    # Check if first file is gzipped
    first_file=$(echo $valid_files | awk '{print $1}')
    if [[ "$first_file" == *.gz ]]; then
        # For gzipped files
        if [[ "$output_file" == *.gz ]]; then
            # If output should be gzipped too
            echo "Files are gzipped, using zcat for merging..." >> $MERGE_LOG
            echo $valid_files | xargs zcat | gzip -c > $output_file
        else
            # If output should be uncompressed
            echo "Files are gzipped, but output is uncompressed..." >> $MERGE_LOG
            echo $valid_files | xargs zcat > $output_file
        fi
    else
        # For uncompressed files
        if [[ "$output_file" == *.gz ]]; then
            # If output should be gzipped
            echo "Files are uncompressed, but output is gzipped..." >> $MERGE_LOG
            echo $valid_files | xargs cat | gzip -c > $output_file
        else
            # If both input and output are uncompressed
            echo "Using cat for merging uncompressed files..." >> $MERGE_LOG
            echo $valid_files | xargs cat > $output_file
        fi
    fi
    
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
else
    echo "Error: Merging failed!" | tee -a $MERGE_LOG
    exit 1
fi

# store results in results/02_merge

# output error and log files to logs directory mergefq_jobid. err and .out respectively