#!/bin/bash

# slurm parameters, see config/parameters.txt
#SBATCH --partition=short-cpu
#SBATCH --time=04:00:00
#SBATCH --nodes=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=16G
#SBATCH --job-name=rnaquast
# Log files will be specified when submitting the job

# input file variables passed in as arguments from main.sh
TRANSCRIPTOME=$1
OUTPUT_DIR=$2
LOG_DIR=${3:-"logs/04_rnaquast"}
DEBUG_MODE=${4:-false}

# Create output directory if it doesn't exist
mkdir -p $OUTPUT_DIR
mkdir -p $LOG_DIR

# Create a log file for this rnaQuast job
RNAQUAST_LOG="$LOG_DIR/rnaquast_$(date +%Y%m%d_%H%M%S).log"
echo "Starting rnaQuast job at $(date)" > $RNAQUAST_LOG
echo "Transcriptome: $TRANSCRIPTOME" >> $RNAQUAST_LOG
echo "Output directory: $OUTPUT_DIR" >> $RNAQUAST_LOG

# Debug mode: Check if output files already exist
if [[ "$DEBUG_MODE" == "true" && -f "$OUTPUT_DIR/report.pdf" ]]; then
    echo "Debug mode: rnaQuast output already exists: $OUTPUT_DIR/report.pdf. Skipping rnaQuast." | tee -a $RNAQUAST_LOG
    
    # Remove summary file entries
    # echo "rnaQuast,,Status,Skipped (files exist)" >> "$SUMMARY_FILE"
    
    exit 0
fi

# Check if input file exists
if [[ ! -s "$TRANSCRIPTOME" ]]; then
    echo "Error: Input transcriptome file is missing or empty!" | tee -a $RNAQUAST_LOG
    echo "TRANSCRIPTOME: $TRANSCRIPTOME" | tee -a $RNAQUAST_LOG
    
    # Remove summary file entry
    # echo "rnaQuast,,Status,Failed (missing input)" >> "$SUMMARY_FILE"
    
    exit 1
fi

# Run rnaQuast
echo "Running rnaQuast..." | tee -a $RNAQUAST_LOG

# Get start time for timing
start_time=$(date +%s)

# Run rnaQuast with appropriate parameters
rnaQUAST.py \
    --transcripts "$TRANSCRIPTOME" \
    --output_dir "$OUTPUT_DIR" \
    --threads 8 \
    2>> $RNAQUAST_LOG

# Check if rnaQuast completed successfully
if [[ $? -eq 0 && -f "$OUTPUT_DIR/report.pdf" ]]; then
    end_time=$(date +%s)
    runtime=$((end_time - start_time))
    
    echo "rnaQuast completed successfully in $runtime seconds" | tee -a $RNAQUAST_LOG
    
    # Extract rnaQuast statistics if available
    if [[ -f "$OUTPUT_DIR/basic_metrics.tsv" ]]; then
        num_transcripts=$(grep "Transcripts" "$OUTPUT_DIR/basic_metrics.tsv" | cut -f2)
        longest_transcript=$(grep "Longest transcript" "$OUTPUT_DIR/basic_metrics.tsv" | cut -f2)
        total_length=$(grep "Total length" "$OUTPUT_DIR/basic_metrics.tsv" | cut -f2)
        
        echo "Number of transcripts: $num_transcripts" | tee -a $RNAQUAST_LOG
        echo "Longest transcript: $longest_transcript" | tee -a $RNAQUAST_LOG
        echo "Total length: $total_length" | tee -a $RNAQUAST_LOG
        
        # Remove summary file entries
        # echo "rnaQuast,,Status,Completed" >> "$SUMMARY_FILE"
        # echo "rnaQuast,,Runtime,$runtime seconds" >> "$SUMMARY_FILE"
        # echo "rnaQuast,,Transcripts,$num_transcripts" >> "$SUMMARY_FILE"
        # echo "rnaQuast,,Longest,$longest_transcript" >> "$SUMMARY_FILE"
        # echo "rnaQuast,,Total Length,$total_length" >> "$SUMMARY_FILE"
    else
        echo "Warning: rnaQuast completed but basic_metrics.tsv not found" | tee -a $RNAQUAST_LOG
        # echo "rnaQuast,,Status,Completed (no metrics)" >> "$SUMMARY_FILE"
        # echo "rnaQuast,,Runtime,$runtime seconds" >> "$SUMMARY_FILE"
    fi
else
    echo "Error: rnaQuast failed!" | tee -a $RNAQUAST_LOG
    # echo "rnaQuast,,Status,Failed" >> "$SUMMARY_FILE"
    exit 1
fi