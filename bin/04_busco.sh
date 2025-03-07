#!/bin/bash

# slurm parameters, see config/parameters.txt
#SBATCH --partition=short-cpu
#SBATCH --time=04:00:00
#SBATCH --nodes=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=16G
#SBATCH --job-name=busco
# Log files will be specified when submitting the job

# input file variables passed in as arguments from main.sh
TRANSCRIPTOME=$1
OUTPUT_DIR=$2
LOG_DIR=${3:-"logs/04_busco"}
DEBUG_MODE=${4:-false}
SUMMARY_FILE=${5:-"logs/pipeline_summary.csv"}

# Create output directory if it doesn't exist
mkdir -p $OUTPUT_DIR
mkdir -p $LOG_DIR

# Create a log file for this BUSCO job
BUSCO_LOG="$LOG_DIR/busco_$(date +%Y%m%d_%H%M%S).log"
echo "Starting BUSCO job at $(date)" > $BUSCO_LOG
echo "Transcriptome: $TRANSCRIPTOME" >> $BUSCO_LOG
echo "Output directory: $OUTPUT_DIR" >> $BUSCO_LOG

# Debug mode: Check if output files already exist
if [[ "$DEBUG_MODE" == "true" && -d "$OUTPUT_DIR" && -f "$OUTPUT_DIR/short_summary.txt" ]]; then
    echo "Debug mode: BUSCO output already exists: $OUTPUT_DIR/short_summary.txt. Skipping BUSCO." | tee -a $BUSCO_LOG
    
    # Add summary entry
    echo "BUSCO,,Status,Skipped (files exist)" >> "$SUMMARY_FILE"
    
    exit 0
fi

# Check if input file exists
if [[ ! -s "$TRANSCRIPTOME" ]]; then
    echo "Error: Input transcriptome file is missing or empty!" | tee -a $BUSCO_LOG
    echo "TRANSCRIPTOME: $TRANSCRIPTOME" | tee -a $BUSCO_LOG
    
    # Add summary entry
    echo "BUSCO,,Status,Failed (missing input)" >> "$SUMMARY_FILE"
    
    exit 1
fi

# Activate conda environment
source ~/.bashrc
conda activate cellSquito

# Run BUSCO
echo "Running BUSCO..." | tee -a $BUSCO_LOG

# Get start time for timing
start_time=$(date +%s)

# Run BUSCO with appropriate parameters
busco \
    -i "$TRANSCRIPTOME" \
    -o "$(basename $OUTPUT_DIR)" \
    -l diptera_odb10 \
    -m transcriptome \
    -c $SLURM_CPUS_PER_TASK \
    --out_path "$(dirname $OUTPUT_DIR)" \
    2>> $BUSCO_LOG

# Check if BUSCO completed successfully
BUSCO_RUN_DIR="$OUTPUT_DIR/run_diptera_odb10" 
SUMMARY_FILE_PATH="$BUSCO_RUN_DIR/short_summary.txt"

if [[ $? -eq 0 && -f "$SUMMARY_FILE_PATH" ]]; then
    end_time=$(date +%s)
    runtime=$((end_time - start_time))
    
    echo "BUSCO completed successfully in $runtime seconds" | tee -a $BUSCO_LOG
    
    # Extract BUSCO statistics
    complete=$(grep "Complete BUSCOs" "$SUMMARY_FILE_PATH" | grep -o "[0-9.]\+%")
    single=$(grep "Complete and single-copy BUSCOs" "$SUMMARY_FILE_PATH" | grep -o "[0-9]\+")
    duplicated=$(grep "Complete and duplicated BUSCOs" "$SUMMARY_FILE_PATH" | grep -o "[0-9]\+")
    fragmented=$(grep "Fragmented BUSCOs" "$SUMMARY_FILE_PATH" | grep -o "[0-9]\+")
    missing=$(grep "Missing BUSCOs" "$SUMMARY_FILE_PATH" | grep -o "[0-9]\+")
    total=$(grep "Total BUSCO groups searched" "$SUMMARY_FILE_PATH" | grep -o "[0-9]\+")
    
    echo "Complete BUSCOs: $complete" | tee -a $BUSCO_LOG
    echo "Complete and single-copy BUSCOs: $single" | tee -a $BUSCO_LOG
    echo "Complete and duplicated BUSCOs: $duplicated" | tee -a $BUSCO_LOG
    echo "Fragmented BUSCOs: $fragmented" | tee -a $BUSCO_LOG
    echo "Missing BUSCOs: $missing" | tee -a $BUSCO_LOG
    echo "Total BUSCO groups searched: $total" | tee -a $BUSCO_LOG
    
    # Add summary entries
    echo "BUSCO,,Status,Completed" >> "$SUMMARY_FILE"
    echo "BUSCO,,Runtime,$runtime seconds" >> "$SUMMARY_FILE"
    echo "BUSCO,,Complete,$complete" >> "$SUMMARY_FILE"
    echo "BUSCO,,Single-copy,$single" >> "$SUMMARY_FILE"
    echo "BUSCO,,Duplicated,$duplicated" >> "$SUMMARY_FILE"
    echo "BUSCO,,Fragmented,$fragmented" >> "$SUMMARY_FILE"
    echo "BUSCO,,Missing,$missing" >> "$SUMMARY_FILE"
    echo "BUSCO,,Total,$total" >> "$SUMMARY_FILE"
else
    echo "Error: BUSCO failed!" | tee -a $BUSCO_LOG
    echo "BUSCO,,Status,Failed" >> "$SUMMARY_FILE"
    exit 1
fi

# Move BUSCO output to the specified output directory if needed
if [[ -d "$BUSCO_RUN_DIR" && "$BUSCO_RUN_DIR" != "$OUTPUT_DIR" ]]; then
    cp -r $BUSCO_RUN_DIR/* $OUTPUT_DIR/
fi

echo "BUSCO results saved to $OUTPUT_DIR"

# output error and log files to logs directory _jobid. err and .out respectively