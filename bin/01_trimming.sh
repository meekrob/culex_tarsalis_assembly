#!/bin/bash

# slurm parameters, see config/parameters.txt
#SBATCH --partition=short-cpu
#SBATCH --time=01:00:00
#SBATCH --nodes=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=8G
#SBATCH --job-name=fastp_trim
# Log files will be specified when submitting the job

# Source configuration
source config/parameters.txt

# input file variables passed in as arguments from main.sh
FILE=$1    # R1 input file
TWO=$2     # R2 input file  
TRIM1=$3   # R1 output file
TRIM2=$4   # R2 output file
SAMPLE_NAME=$5  # Sample name for logs/reporting
LOG_DIR=${6:-"logs/01_trimming"}  # Directory for logs
SUMMARY_FILE=${7:-"logs/pipeline_summary.csv"}  # Summary file path
DEBUG_MODE=${8:-false}  # Debug mode flag

# Enhance input validation
for f in "$FILE" "$TWO"; do
    if [[ ! -f "$f" ]]; then
        echo "Error: Input file $f not found!" >&2
        exit 1
    fi
done

# Create output directory if it doesn't exist
TRIM_DIR=$(dirname $TRIM1)
mkdir -p $TRIM_DIR
mkdir -p $LOG_DIR

# Create reports directory inside the trimmed directory
REPORTS_DIR="${TRIM_DIR}/reports"
mkdir -p $REPORTS_DIR

# Set HTML and JSON report paths
HTML_REPORT="${REPORTS_DIR}/${SAMPLE_NAME}_fastp.html"
JSON_REPORT="${REPORTS_DIR}/${SAMPLE_NAME}_fastp.json"

# Debug mode: Check if output files already exist
if [[ "$DEBUG_MODE" == "true" && -s "$TRIM1" && -s "$TRIM2" ]]; then
    echo "Debug mode: Trimmed files already exist for $SAMPLE_NAME: $TRIM1, $TRIM2. Skipping trimming."
    
    # Add entry to summary file
    echo "Trimming,$SAMPLE_NAME,Status,Skipped (files exist)" >> "$SUMMARY_FILE"
    
    exit 0
fi

# activate conda env
source ~/.bashrc
conda activate cellSquito

echo "Processing sample: $SAMPLE_NAME"
echo "Input R1: $FILE"
echo "Input R2: $TWO"
echo "Output R1: $TRIM1"
echo "Output R2: $TRIM2"

# run fastp with configurable parameters
cmd="fastp -i ${FILE} -I ${TWO} \
               -o ${TRIM1} -O ${TRIM2} \
               -h ${HTML_REPORT} -j ${JSON_REPORT} \
               -w $((SLURM_CPUS_PER_TASK-1)) --dedup"
echo "Executing command: $cmd"
time eval $cmd

# Improved error handling
if [[ $? -ne 0 ]]; then
    echo "Error: fastp failed for sample $SAMPLE_NAME" >&2
    echo "Trimming,$SAMPLE_NAME,Status,Failed" >> "$SUMMARY_FILE"
    exit 1
fi

# Check if output files were created
for f in "$TRIM1" "$TRIM2" "$HTML_REPORT" "$JSON_REPORT"; do
    if [[ ! -s "$f" ]]; then
        echo "Error: Output file $f is missing or empty!" >&2
        echo "Trimming,$SAMPLE_NAME,Status,Failed (missing output)" >> "$SUMMARY_FILE"
        exit 1
    fi
done

echo "Trimming completed for sample $SAMPLE_NAME"

# Add statistics to summary file
reads_before=$(zcat -f "$FILE" | wc -l | awk '{print $1/4}')
reads_after=$(zcat -f "$TRIM1" | wc -l | awk '{print $1/4}')

echo "Trimming,$SAMPLE_NAME,Reads Before,$reads_before" >> "$SUMMARY_FILE"
echo "Trimming,$SAMPLE_NAME,Reads After,$reads_after" >> "$SUMMARY_FILE"
echo "Trimming,$SAMPLE_NAME,Status,Completed" >> "$SUMMARY_FILE"

# Add logging information
echo "Sample: $SAMPLE_NAME" >> "$LOG_DIR/trim_summary.txt"
echo "Reads before: $reads_before" >> "$LOG_DIR/trim_summary.txt"
echo "Reads after: $reads_after" >> "$LOG_DIR/trim_summary.txt" 
echo "-------------------" >> "$LOG_DIR/trim_summary.txt"

echo "HTML report: $HTML_REPORT"
echo "JSON report: $JSON_REPORT"