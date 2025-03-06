#! /bin/bash

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

# Create output directory if it doesn't exist
mkdir -p $OUTPUT_DIR
mkdir -p $LOG_DIR

# Create a log file for this BUSCO job
BUSCO_LOG="$LOG_DIR/busco_$(date +%Y%m%d_%H%M%S).log"
echo "Starting BUSCO job at $(date)" > $BUSCO_LOG
echo "Transcriptome: $TRANSCRIPTOME" >> $BUSCO_LOG
echo "Output directory: $OUTPUT_DIR" >> $BUSCO_LOG

# Debug mode: Check if output files already exist
if [[ "$DEBUG_MODE" == "true" && -d "$OUTPUT_DIR/run_diptera_odb10" && -f "$OUTPUT_DIR/run_diptera_odb10/short_summary.txt" ]]; then
    echo "Debug mode: BUSCO output already exists: $OUTPUT_DIR/run_diptera_odb10/short_summary.txt. Skipping BUSCO." | tee -a $BUSCO_LOG
    
    # Remove summary file entries
    # echo "BUSCO,,Status,Skipped (files exist)" >> "$SUMMARY_FILE"
    
    exit 0
fi

# Check if input file exists
if [[ ! -s "$TRANSCRIPTOME" ]]; then
    echo "Error: Input transcriptome file is missing or empty!" | tee -a $BUSCO_LOG
    echo "TRANSCRIPTOME: $TRANSCRIPTOME" | tee -a $BUSCO_LOG
    
    # Remove summary file entry
    # echo "BUSCO,,Status,Failed (missing input)" >> "$SUMMARY_FILE"
    
    exit 1
fi

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
    -c 8 \
    --out_path "$(dirname $OUTPUT_DIR)" \
    2>> $BUSCO_LOG

# Check if BUSCO completed successfully
if [[ $? -eq 0 && -f "$OUTPUT_DIR/run_diptera_odb10/short_summary.txt" ]]; then
    end_time=$(date +%s)
    runtime=$((end_time - start_time))
    
    echo "BUSCO completed successfully in $runtime seconds" | tee -a $BUSCO_LOG
    
    # Extract BUSCO statistics
    complete=$(grep "Complete BUSCOs" "$OUTPUT_DIR/run_diptera_odb10/short_summary.txt" | grep -o "[0-9.]\+%")
    single=$(grep "Complete and single-copy BUSCOs" "$OUTPUT_DIR/run_diptera_odb10/short_summary.txt" | grep -o "[0-9]\+")
    duplicated=$(grep "Complete and duplicated BUSCOs" "$OUTPUT_DIR/run_diptera_odb10/short_summary.txt" | grep -o "[0-9]\+")
    fragmented=$(grep "Fragmented BUSCOs" "$OUTPUT_DIR/run_diptera_odb10/short_summary.txt" | grep -o "[0-9]\+")
    missing=$(grep "Missing BUSCOs" "$OUTPUT_DIR/run_diptera_odb10/short_summary.txt" | grep -o "[0-9]\+")
    total=$(grep "Total BUSCO groups searched" "$OUTPUT_DIR/run_diptera_odb10/short_summary.txt" | grep -o "[0-9]\+")
    
    echo "Complete BUSCOs: $complete" | tee -a $BUSCO_LOG
    echo "Complete and single-copy BUSCOs: $single" | tee -a $BUSCO_LOG
    echo "Complete and duplicated BUSCOs: $duplicated" | tee -a $BUSCO_LOG
    echo "Fragmented BUSCOs: $fragmented" | tee -a $BUSCO_LOG
    echo "Missing BUSCOs: $missing" | tee -a $BUSCO_LOG
    echo "Total BUSCO groups searched: $total" | tee -a $BUSCO_LOG
    
    # Remove summary file entries
    # echo "BUSCO,,Status,Completed" >> "$SUMMARY_FILE"
    # echo "BUSCO,,Runtime,$runtime seconds" >> "$SUMMARY_FILE"
    # echo "BUSCO,,Complete,$complete" >> "$SUMMARY_FILE"
    # echo "BUSCO,,Single-copy,$single" >> "$SUMMARY_FILE"
    # echo "BUSCO,,Duplicated,$duplicated" >> "$SUMMARY_FILE"
    # echo "BUSCO,,Fragmented,$fragmented" >> "$SUMMARY_FILE"
    # echo "BUSCO,,Missing,$missing" >> "$SUMMARY_FILE"
    # echo "BUSCO,,Total,$total" >> "$SUMMARY_FILE"
else
    echo "Error: BUSCO failed!" | tee -a $BUSCO_LOG
    # echo "BUSCO,,Status,Failed" >> "$SUMMARY_FILE"
    exit 1
fi

# Move BUSCO output to the specified output directory
if [[ -d "$OUTPUT_DIR/run_diptera_odb10" ]]; then
    mv $OUTPUT_DIR/run_diptera_odb10/* $OUTPUT_DIR/
    rmdir $OUTPUT_DIR/run_diptera_odb10
fi

echo "BUSCO results saved to $OUTPUT_DIR"
echo "BUSCO summary file: $OUTPUT_DIR/run_diptera_odb10/short_summary.txt"

# output error and log files to logs directory _jobid. err and .out respectively