#!/bin/bash

#SBATCH --partition=short-cpu
#SBATCH --time=24:00:00
#SBATCH --nodes=1
#SBATCH --cpus-per-task=16
#SBATCH --mem=64G
#SBATCH --job-name=braker

# Load paths from central configuration
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
REPO_ROOT="$( cd "$SCRIPT_DIR/../../.." && pwd )"
source "${REPO_ROOT}/config/paths.sh"

# Input arguments
GENOME_FILE=$1
BAM_FILE=$2
RESULT_DIR=$3
LOG_DIR=$4
DEBUG_MODE=${5:-false}
SUMMARY_FILE=$6
SPECIES_NAME=${7:-"mosquito"}

# Set path to Singularity image (relative to repository)
SIF_PATH="${REPO_ROOT}/pipelines/maker_annotator/braker.sif"

# Create log file
BRAKER_LOG="${LOG_DIR}/braker_${SPECIES_NAME}_$(date +%Y%m%d_%H%M%S).log"
echo "Starting BRAKER job at $(date)" > "$BRAKER_LOG"
echo "Genome file: $GENOME_FILE" >> "$BRAKER_LOG"
echo "BAM file: $BAM_FILE" >> "$BRAKER_LOG"
echo "Species name: $SPECIES_NAME" >> "$BRAKER_LOG"
echo "Output directory: $RESULT_DIR" >> "$BRAKER_LOG"

# Start timing
start_time=$(date +%s)

# Check if SIF file exists
if [[ ! -f "$SIF_PATH" ]]; then
    echo "ERROR: Singularity image not found: $SIF_PATH" | tee -a "$BRAKER_LOG"
    echo "Please place braker.sif in the pipelines/maker_annotator/ directory." | tee -a "$BRAKER_LOG"
    exit 1
fi

# Create output directory
mkdir -p "$RESULT_DIR"

# Run BRAKER using Singularity
echo "Running BRAKER..." | tee -a "$BRAKER_LOG"
singularity exec "$SIF_PATH" braker.pl \
    --genome="$GENOME_FILE" \
    --bam="$BAM_FILE" \
    --species="$SPECIES_NAME" \
    --cores=16 \
    --workingdir="$RESULT_DIR" 2>&1 | tee -a "$BRAKER_LOG"

# Check if BRAKER completed successfully
if [[ $? -eq 0 ]]; then
    end_time=$(date +%s)
    runtime=$((end_time - start_time))
    
    echo "BRAKER completed successfully in $runtime seconds" | tee -a "$BRAKER_LOG"
    
    # Count gene models
    gff3_file="${RESULT_DIR}/augustus.hints.gff3"
    if [[ -f "$gff3_file" ]]; then
        gene_count=$(grep -c "\tgene\t" "$gff3_file")
        transcript_count=$(grep -c "\tmRNA\t" "$gff3_file")
        
        echo "Gene models found: $gene_count" | tee -a "$BRAKER_LOG"
        echo "Transcript models found: $transcript_count" | tee -a "$BRAKER_LOG"
        
        # Add to summary file
        echo "BRAKER,$SPECIES_NAME,Status,Completed" >> "$SUMMARY_FILE"
        echo "BRAKER,$SPECIES_NAME,Runtime,$runtime seconds" >> "$SUMMARY_FILE"
        echo "BRAKER,$SPECIES_NAME,Gene Count,$gene_count" >> "$SUMMARY_FILE"
        echo "BRAKER,$SPECIES_NAME,Transcript Count,$transcript_count" >> "$SUMMARY_FILE"
    else
        echo "Warning: GFF3 file not found" | tee -a "$BRAKER_LOG"
        echo "BRAKER,$SPECIES_NAME,Status,Completed (no gff3 file)" >> "$SUMMARY_FILE"
    fi
    
    exit 0
else
    echo "Error: BRAKER failed!" | tee -a "$BRAKER_LOG"
    echo "BRAKER,$SPECIES_NAME,Status,Failed" >> "$SUMMARY_FILE"
    exit 1
fi