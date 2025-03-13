#!/bin/bash

#SBATCH --partition=short-cpu
#SBATCH --time=24:00:00
#SBATCH --nodes=1
#SBATCH --cpus-per-task=16
#SBATCH --mem=100G
#SBATCH --job-name=repeatmasker

# Input arguments
GENOME_FILE=$1
REPEAT_LIB=$2
RESULT_DIR=$3
LOG_DIR=$4
DEBUG_MODE=${5:-false}
SUMMARY_FILE=$6

# Create log file
RM_LOG="${LOG_DIR}/repeatmasker_$(basename "$GENOME_FILE")_$(date +%Y%m%d_%H%M%S).log"
echo "Starting RepeatMasker job at $(date)" > "$RM_LOG"
echo "Genome file: $GENOME_FILE" >> "$RM_LOG"
echo "Repeat library: $REPEAT_LIB" >> "$RM_LOG"
echo "Output directory: $RESULT_DIR" >> "$RM_LOG"

# Start timing
start_time=$(date +%s)

# Activate conda environment
source ~/.bashrc
conda activate repeatmasker

# Create output directory
mkdir -p "$RESULT_DIR"

# Run RepeatMasker
echo "Running RepeatMasker..." | tee -a "$RM_LOG"
RepeatMasker -s -lib "$REPEAT_LIB" "$GENOME_FILE" -pa 16 -dir "$RESULT_DIR" 2>&1 | tee -a "$RM_LOG"

# Check if RepeatMasker completed successfully
if [[ $? -eq 0 ]]; then
    end_time=$(date +%s)
    runtime=$((end_time - start_time))
    
    echo "RepeatMasker completed successfully in $runtime seconds" | tee -a "$RM_LOG"
    
    # Get basic statistics
    genome_name=$(basename "$GENOME_FILE")
    masked_file="${RESULT_DIR}/${genome_name}.masked"
    
    if [[ -f "$masked_file" ]]; then
        # Calculate masking percentage
        total_size=$(grep -v "^>" "$GENOME_FILE" | tr -d '\n' | wc -c)
        masked_count=$(grep -o "N" "$masked_file" | wc -l)
        mask_percent=$(awk "BEGIN {printf \"%.2f\", ($masked_count / $total_size) * 100}")
        
        echo "Total genome size: $total_size bp" | tee -a "$RM_LOG"
        echo "Masked bases: $masked_count bp" | tee -a "$RM_LOG"
        echo "Percent masked: ${mask_percent}%" | tee -a "$RM_LOG"
        
        # Add to summary file
        echo "RepeatMasker,$genome_name,Status,Completed" >> "$SUMMARY_FILE"
        echo "RepeatMasker,$genome_name,Runtime,$runtime seconds" >> "$SUMMARY_FILE"
        echo "RepeatMasker,$genome_name,Total Size,$total_size bp" >> "$SUMMARY_FILE"
        echo "RepeatMasker,$genome_name,Masked Bases,$masked_count bp" >> "$SUMMARY_FILE"
        echo "RepeatMasker,$genome_name,Percent Masked,$mask_percent%" >> "$SUMMARY_FILE"
    else
        echo "Warning: Masked file not found" | tee -a "$RM_LOG"
        echo "RepeatMasker,$genome_name,Status,Completed (no masked file)" >> "$SUMMARY_FILE"
    fi
    
    exit 0
else
    echo "Error: RepeatMasker failed!" | tee -a "$RM_LOG"
    echo "RepeatMasker,$(basename "$GENOME_FILE"),Status,Failed" >> "$SUMMARY_FILE"
    exit 1
fi