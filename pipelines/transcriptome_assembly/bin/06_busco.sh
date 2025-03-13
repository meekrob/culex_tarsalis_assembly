#!/bin/bash

# slurm parameters, see config/parameters.txt
#SBATCH --partition=day-long-cpu
#SBATCH --time=24:00:00
#SBATCH --nodes=1
#SBATCH --cpus-per-task=16
#SBATCH --mem=32G
#SBATCH --job-name=busco
# Log files will be specified when submitting the job

# Input arguments
ASSEMBLY_FILE=$1
OUTPUT_DIR=$2
LOG_DIR=$3
DEBUG_MODE=${4:-false}
SUMMARY_FILE=$5
ASSEMBLY_TYPE=$6  # "bbnorm" or "trinity"

# Create output directory if it doesn't exist
mkdir -p $OUTPUT_DIR
mkdir -p $LOG_DIR
#
# Create a log file for this BUSCO job
BUSCO_LOG="${LOG_DIR}/busco_${ASSEMBLY_TYPE}_$(date +%Y%m%d_%H%M%S).log"
echo "Starting BUSCO analysis at $(date)" > "$BUSCO_LOG"
echo "Assembly file: $ASSEMBLY_FILE" >> "$BUSCO_LOG"
echo "Output directory: $OUTPUT_DIR" >> "$BUSCO_LOG"

# Check if input is gzipped
UNZIPPED_ASSEMBLY_FILE=$ASSEMBLY_FILE
if [[ "$ASSEMBLY_FILE" == *.gz ]]; then
    echo "Input assembly file is gzipped. Decompressing before BUSCO analysis..." | tee -a $BUSCO_LOG
    UNZIPPED_ASSEMBLY_FILE="${ASSEMBLY_FILE%.gz}"
    gunzip -c "$ASSEMBLY_FILE" > "$UNZIPPED_ASSEMBLY_FILE"
    echo "Decompressed to: $UNZIPPED_ASSEMBLY_FILE" | tee -a $BUSCO_LOG
fi

# Debug mode: Check if output files already exist
if [[ "$DEBUG_MODE" == "true" && -f "$OUTPUT_DIR/run_diptera_odb10/short_summary.txt" ]]; then
    echo "DEBUG: Skipping BUSCO analysis, output exists" | tee -a "$BUSCO_LOG"
    
    # Still record stats from existing run
    if [[ -f "$OUTPUT_DIR/run_diptera_odb10/short_summary.txt" ]]; then
        complete_buscos=$(grep "Complete BUSCOs" "$OUTPUT_DIR/run_diptera_odb10/short_summary.txt" | cut -f 2)
        complete_percent=$(grep "Complete BUSCOs" "$OUTPUT_DIR/run_diptera_odb10/short_summary.txt" | grep -oP "\d+\.\d+%")
        
        echo "Complete BUSCOs: $complete_buscos ($complete_percent)" | tee -a "$BUSCO_LOG"
        
        echo "BUSCO,$ASSEMBLY_TYPE,Status,Reused" >> "$SUMMARY_FILE"
        echo "BUSCO,$ASSEMBLY_TYPE,Complete,$complete_buscos" >> "$SUMMARY_FILE"
        echo "BUSCO,$ASSEMBLY_TYPE,Complete_Percent,$complete_percent" >> "$SUMMARY_FILE"
    fi
    
    exit 0
fi

# Check if input file exists
if [[ ! -s "$UNZIPPED_ASSEMBLY_FILE" ]]; then
    echo "Error: Input assembly file is missing or empty!" | tee -a $BUSCO_LOG
    echo "ASSEMBLY_FILE: $UNZIPPED_ASSEMBLY_FILE" | tee -a $BUSCO_LOG
    
    # Add summary entry
    echo "BUSCO,$ASSEMBLY_TYPE,Status,Failed (missing input)" >> "$SUMMARY_FILE"
    
    exit 1
fi

# Activate conda environment
source ~/.bashrc
conda activate cellSquito

# Run BUSCO
echo "Running BUSCO analysis..." | tee -a "$BUSCO_LOG"

# Get start time for timing
start_time=$(date +%s)

# Run BUSCO with appropriate parameters
busco \
    -i "$UNZIPPED_ASSEMBLY_FILE" \
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
    complete_buscos=$(grep "Complete BUSCOs" "$SUMMARY_FILE_PATH" | cut -f 2)
    complete_percent=$(grep "Complete BUSCOs" "$SUMMARY_FILE_PATH" | grep -oP "\d+\.\d+%")
    fragmented=$(grep "Fragmented BUSCOs" "$SUMMARY_FILE_PATH" | cut -f 2)
    missing=$(grep "Missing BUSCOs" "$SUMMARY_FILE_PATH" | cut -f 2)
    
    echo "Complete BUSCOs: $complete_buscos ($complete_percent)" | tee -a $BUSCO_LOG
    echo "Fragmented BUSCOs: $fragmented" | tee -a $BUSCO_LOG
    echo "Missing BUSCOs: $missing" | tee -a $BUSCO_LOG
    
    # Add summary entries
    echo "BUSCO,$ASSEMBLY_TYPE,Status,Completed" >> "$SUMMARY_FILE"
    echo "BUSCO,$ASSEMBLY_TYPE,Runtime,$runtime seconds" >> "$SUMMARY_FILE"
    echo "BUSCO,$ASSEMBLY_TYPE,Complete,$complete_buscos" >> "$SUMMARY_FILE"
    echo "BUSCO,$ASSEMBLY_TYPE,Complete_Percent,$complete_percent" >> "$SUMMARY_FILE"
    echo "BUSCO,$ASSEMBLY_TYPE,Fragmented,$fragmented" >> "$SUMMARY_FILE"
    echo "BUSCO,$ASSEMBLY_TYPE,Missing,$missing" >> "$SUMMARY_FILE"
else
    echo "Error: BUSCO failed!" | tee -a $BUSCO_LOG
    echo "BUSCO,$ASSEMBLY_TYPE,Status,Failed" >> "$SUMMARY_FILE"
    exit 1
fi

# Clean up decompressed file if we created one
if [[ "$ASSEMBLY_FILE" == *.gz && "$UNZIPPED_ASSEMBLY_FILE" != "$ASSEMBLY_FILE" ]]; then
    echo "Cleaning up temporary decompressed file..." | tee -a $BUSCO_LOG
    rm -f "$UNZIPPED_ASSEMBLY_FILE"
fi

# Move BUSCO output to the specified output directory if needed
if [[ -d "$BUSCO_RUN_DIR" && "$BUSCO_RUN_DIR" != "$OUTPUT_DIR" ]]; then
    cp -r $BUSCO_RUN_DIR/* $OUTPUT_DIR/
fi

echo "BUSCO results saved to $OUTPUT_DIR"

# output error and log files to logs directory _jobid. err and .out respectively