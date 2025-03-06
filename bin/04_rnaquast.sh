#! /bin/bash

# slurm parameters, see config/parameters.txt
#SBATCH --partition=short-cpu
#SBATCH --time=04:00:00
#SBATCH --nodes=1
#SBATCH --cpus-per-task=16
#SBATCH --mem=32G
#SBATCH --job-name=rnaquast
# Log files will be specified when submitting the job

# input file variables passed in as arguments from main_mosquito.sh
TX_FASTA=$1    # Transcriptome fasta file
OUT=$2         # Output directory
LEFT=$3        # Left reads (for read mapping)
RIGHT=$4       # Right reads (for read mapping)
OPTS=${5:-""}  # Additional options for rnaQuast
LOG_DIR=${6:-"logs/04_rnaquast"}  # Directory for logs
SUMMARY_FILE=${7:-"logs/pipeline_summary.csv"}  # Summary file path
DEBUG_MODE=${8:-false}  # Debug mode flag

# Create output directory if it doesn't exist
mkdir -p $OUT
mkdir -p $LOG_DIR

# Debug mode: Check if output files already exist
if [[ "$DEBUG_MODE" == "true" && -s "$OUT/report.txt" ]]; then
    echo "Debug mode: rnaQuast report already exists: $OUT/report.txt. Skipping rnaQuast analysis."
    
    # Add entry to summary file
    echo "rnaQuast,,Status,Skipped (files exist)" >> "$SUMMARY_FILE"
    
    # Extract key metrics from the report file
    if [[ -f "$OUT/report.txt" ]]; then
        transcripts=$(grep "^Transcripts" "$OUT/report.txt" | awk '{print $NF}')
        total_length=$(grep "^Total length" "$OUT/report.txt" | head -n 1 | awk '{print $NF}')
        n50=$(grep "^Transcript N50" "$OUT/report.txt" | awk '{print $NF}')
        
        echo "rnaQuast,,Transcripts,$transcripts" >> "$SUMMARY_FILE"
        echo "rnaQuast,,Total Length,$total_length" >> "$SUMMARY_FILE"
        echo "rnaQuast,,N50,$n50" >> "$SUMMARY_FILE"
    fi
    
    exit 0
fi

# activate conda env
source ~/.bashrc
conda activate cellSquito

echo "Starting rnaQuast analysis"
echo "Transcriptome: $TX_FASTA"
echo "Output directory: $OUT"
echo "Left reads: $LEFT"
echo "Right reads: $RIGHT"
echo "Additional options: $OPTS"

# run rnaQuast on the assembly from rnaspades using configurable parameters
cmd="rnaQUAST.py --transcripts $TX_FASTA --output_dir $OUT --threads $SLURM_CPUS_PER_TASK"

# Add read mapping if reads are provided
if [[ -n "$LEFT" && -n "$RIGHT" && -f "$LEFT" && -f "$RIGHT" ]]; then
    cmd="$cmd --left $LEFT --right $RIGHT"
fi

# Add any additional options
if [[ -n "$OPTS" ]]; then
    cmd="$cmd $OPTS"
fi

echo "Executing command: $cmd"
time eval $cmd

# Check if rnaQuast was successful
if [[ $? -ne 0 ]]; then
    echo "Error: rnaQuast failed!" >&2
    echo "rnaQuast,,Status,Failed" >> "$SUMMARY_FILE"
    exit 1
fi

# Check if output files were created
if [[ ! -s "$OUT/report.txt" ]]; then
    echo "Error: rnaQuast report file is missing or empty!" >&2
    echo "rnaQuast,,Status,Failed (missing output)" >> "$SUMMARY_FILE"
    exit 1
fi

echo "rnaQuast analysis completed successfully!"

# Extract key metrics from the report file
transcripts=$(grep "^Transcripts" "$OUT/report.txt" | awk '{print $NF}')
total_length=$(grep "^Total length" "$OUT/report.txt" | head -n 1 | awk '{print $NF}')
n50=$(grep "^Transcript N50" "$OUT/report.txt" | awk '{print $NF}')

# Add rnaQuast statistics to summary file
echo "rnaQuast,,Status,Completed" >> "$SUMMARY_FILE"
echo "rnaQuast,,Transcripts,$transcripts" >> "$SUMMARY_FILE"
echo "rnaQuast,,Total Length,$total_length" >> "$SUMMARY_FILE"
echo "rnaQuast,,N50,$n50" >> "$SUMMARY_FILE"

echo "rnaQuast results saved to $OUT"
echo "rnaQuast report file: $OUT/report.txt"