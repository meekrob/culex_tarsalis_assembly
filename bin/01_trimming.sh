#! /bin/bash

# slurm parameters, see config/parameters.txt
#SBATCH --partition=short-cpu
#SBATCH --time=01:00:00
#SBATCH --nodes=1
#SBATCH --cpus-per-task=17
#SBATCH --mem=8G
#SBATCH --job-name=fastp_trim
#SBATCH --output=logs/fastp_%j.out
#SBATCH --error=logs/fastp_%j.err

# Source configuration
source config/parameters.txt

# input file variables passed in as arguments from main_mosquito.sh
FILE=$1    # R1 input file
TWO=$2     # R2 input file  
TRIM1=$3   # R1 output file
TRIM2=$4   # R2 output file
SAMPLE_NAME=$5  # Sample name for logs/reporting
LOG_DIR=${6:-"logs"}  # Directory for logs

# Enhance input validation
for f in "$FILE" "$TWO"; do
    if [[ ! -f "$f" ]]; then
        echo "Error: Input file $f not found!" >&2
        exit 1
    fi
done

# Create output directory if it doesn't exist
mkdir -p $(dirname $TRIM1)
mkdir -p htmls  # Create directory for HTML reports
mkdir -p $LOG_DIR

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
             -h htmls/$(basename $FILE).html -j htmls/$(basename $FILE).json \
             -w ${fastp.threads} ${fastp.opts}"
echo "Executing command: $cmd"
time eval $cmd

# Improved error handling
if [[ $? -ne 0 ]]; then
    echo "Error: fastp failed for sample $SAMPLE_NAME" >&2
    exit 1
fi

# Check if output files were created
for f in "$TRIM1" "$TRIM2"; do
    if [[ ! -s "$f" ]]; then
        echo "Error: Output file $f is missing or empty!" >&2
        exit 1
    fi
done

echo "Trimming completed for sample $SAMPLE_NAME"

# Add logging information
echo "Sample: $SAMPLE_NAME" >> "$LOG_DIR/trim_summary.txt"
echo "Reads before: $(zcat -f "$FILE" | wc -l | awk '{print $1/4}')" >> "$LOG_DIR/trim_summary.txt"
echo "Reads after: $(zcat -f "$TRIM1" | wc -l | awk '{print $1/4}')" >> "$LOG_DIR/trim_summary.txt"
echo "-------------------" >> "$LOG_DIR/trim_summary.txt"

# Results are stored in the path specified by TRIM1 and TRIM2
# HTML and JSON reports are stored in the htmls directory