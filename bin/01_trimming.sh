#! /bin/bash

# slurm parameters, see config/parameters.txt
#SBATCH --partition=short-cpu
#SBATCH --time=01:00:00
#SBATCH --nodes=1
#SBATCH --cpus-per-task=17
#SBATCH --mem=8G
#SBATCH --job-name=fastp_trim
# Log files will be specified when submitting the job

# Source configuration
source config/parameters.txt

# input file variables passed in as arguments from main_mosquito.sh
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

# Debug mode: Check if output files already exist
if [[ "$DEBUG_MODE" == "true" && -s "$TRIM1" && -s "$TRIM2" ]]; then
    echo "Debug mode: Trimmed files already exist for $SAMPLE_NAME: $TRIM1, $TRIM2. Skipping trimming."
    
    # Add entry to summary file
    echo "Trimming,$SAMPLE_NAME,Status,Skipped (files exist)" >> "$SUMMARY_FILE"
    
    # Extract some basic stats for the summary file
    READS_BEFORE=$(zcat -f "$FILE" | wc -l | awk '{print $1/4}')
    READS_AFTER=$(zcat -f "$TRIM1" | wc -l | awk '{print $1/4}')
    
    echo "Trimming,$SAMPLE_NAME,Reads Before,$READS_BEFORE" >> "$SUMMARY_FILE"
    echo "Trimming,$SAMPLE_NAME,Reads After,$READS_AFTER" >> "$SUMMARY_FILE"
    
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
echo "Reports directory: $REPORTS_DIR"

# run fastp with configurable parameters
# Use sample name for the report files to avoid long filenames with paths
HTML_REPORT="${REPORTS_DIR}/${SAMPLE_NAME}.html"
JSON_REPORT="${REPORTS_DIR}/${SAMPLE_NAME}.json"

cmd="fastp -i ${FILE} -I ${TWO} \
             -o ${TRIM1} -O ${TRIM2} \
             -h ${HTML_REPORT} -j ${JSON_REPORT} \
             -w ${fastp_threads} ${fastp_opts}"
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
# Extract key metrics from JSON report using jq if available
if command -v jq &> /dev/null; then
    total_reads_before=$(jq '.summary.before_filtering.total_reads' "$JSON_REPORT")
    total_reads_after=$(jq '.summary.after_filtering.total_reads' "$JSON_REPORT")
    q20_before=$(jq '.summary.before_filtering.q20_rate' "$JSON_REPORT")
    q20_after=$(jq '.summary.after_filtering.q20_rate' "$JSON_REPORT")
    
    echo "Trimming,$SAMPLE_NAME,Total Reads Before,$total_reads_before" >> "$SUMMARY_FILE"
    echo "Trimming,$SAMPLE_NAME,Total Reads After,$total_reads_after" >> "$SUMMARY_FILE"
    echo "Trimming,$SAMPLE_NAME,Q20 Before,$q20_before" >> "$SUMMARY_FILE"
    echo "Trimming,$SAMPLE_NAME,Q20 After,$q20_after" >> "$SUMMARY_FILE"
else
    # Fallback if jq is not available
    reads_before=$(zcat -f "$FILE" | wc -l | awk '{print $1/4}')
    reads_after=$(zcat -f "$TRIM1" | wc -l | awk '{print $1/4}')
    
    echo "Trimming,$SAMPLE_NAME,Reads Before,$reads_before" >> "$SUMMARY_FILE"
    echo "Trimming,$SAMPLE_NAME,Reads After,$reads_after" >> "$SUMMARY_FILE"
fi

echo "Trimming,$SAMPLE_NAME,Status,Completed" >> "$SUMMARY_FILE"

# Add logging information
echo "Sample: $SAMPLE_NAME" >> "$LOG_DIR/trim_summary.txt"
echo "Reads before: $(zcat -f "$FILE" | wc -l | awk '{print $1/4}')" >> "$LOG_DIR/trim_summary.txt"
echo "Reads after: $(zcat -f "$TRIM1" | wc -l | awk '{print $1/4}')" >> "$LOG_DIR/trim_summary.txt"
echo "-------------------" >> "$LOG_DIR/trim_summary.txt"

# Results are stored in the path specified by TRIM1 and TRIM2
# HTML and JSON reports are stored in the reports directory inside the trimmed directory
echo "HTML report: $HTML_REPORT"
echo "JSON report: $JSON_REPORT"