#!/bin/bash

# slurm parameters, see config/parameters.txt
#SBATCH --partition=week-long-highmem
#SBATCH --time=168:00:00
#SBATCH --nodes=1
#SBATCH --cpus-per-task=64
#SBATCH --mem=250G
#SBATCH --job-name=rnaspades
# Log files will be specified when submitting the job

# input file variables passed in as arguments from main.sh
MERGED_R1=$1
MERGED_R2=$2
OUTPUT_DIR=$3
LOG_DIR=${4:-"logs/03_assembly"}
DEBUG_MODE=${5:-false}
SUMMARY_FILE=${6:-"logs/pipeline_summary.csv"}

# Create output directory if it doesn't exist
mkdir -p $OUTPUT_DIR
mkdir -p $LOG_DIR

# Create a log file for this assembly job
ASSEMBLY_LOG="$LOG_DIR/assembly_$(date +%Y%m%d_%H%M%S).log"
echo "Starting assembly job at $(date)" > $ASSEMBLY_LOG
echo "Merged R1: $MERGED_R1" >> $ASSEMBLY_LOG
echo "Merged R2: $MERGED_R2" >> $ASSEMBLY_LOG
echo "Output directory: $OUTPUT_DIR" >> $ASSEMBLY_LOG

# Debug mode: Check if output files already exist - VERY IMPORTANT to check for the file
if [[ "$DEBUG_MODE" == "true" && -s "$OUTPUT_DIR/transcripts.fasta" ]]; then
    echo "Debug mode: Assembly output already exists: $OUTPUT_DIR/transcripts.fasta. Skipping assembly." | tee -a $ASSEMBLY_LOG
    
    # Add entry to summary
    echo "Assembly,,Status,Skipped (files exist)" >> "$SUMMARY_FILE"
    exit 0
fi

# Check if input files exist
if [[ ! -s "$MERGED_R1" || ! -s "$MERGED_R2" ]]; then
    echo "Error: One or both input files are missing or empty!" | tee -a $ASSEMBLY_LOG
    echo "MERGED_R1: $MERGED_R1 ($(du -h $MERGED_R1 2>/dev/null || echo 'missing'))" | tee -a $ASSEMBLY_LOG
    echo "MERGED_R2: $MERGED_R2 ($(du -h $MERGED_R2 2>/dev/null || echo 'missing'))" | tee -a $ASSEMBLY_LOG
    
    # Add error to summary
    echo "Assembly,,Status,Failed (missing input)" >> "$SUMMARY_FILE"
    exit 1
fi

# Activate conda
source ~/.bashrc
conda activate cellSquito

# Run rnaSPAdes
echo "Running rnaSPAdes..." | tee -a $ASSEMBLY_LOG

# Get start time for timing
start_time=$(date +%s)

# Set up temporary directory
TMP="${TMPDIR:-$HOME/tmp}"
mkdir -p $TMP
export TMPDIR=$TMP
echo "Using temporary directory: $TMPDIR" | tee -a $ASSEMBLY_LOG

# Calculate memory in GB from SLURM_MEM_PER_NODE (which is in MB)
if [[ -n "$SLURM_MEM_PER_NODE" ]]; then
    # Convert MB to GB, round down
    MEM_GB=$((SLURM_MEM_PER_NODE / 1024))
    # Reserve a small amount for system overhead (5%)
    SPADES_MEM=$((MEM_GB * 95 / 100))
else
    # Default to 240GB if SLURM_MEM_PER_NODE is not set
    SPADES_MEM=240
fi

# Run rnaSPAdes with appropriate parameters
rnaspades.py \
    --rna \
    -1 "$MERGED_R1" \
    -2 "$MERGED_R2" \
    -o "$OUTPUT_DIR" \
    -t $SLURM_CPUS_PER_TASK \
    -m $SPADES_MEM \
    2>> $ASSEMBLY_LOG

# Check if rnaSPAdes completed successfully
if [[ $? -eq 0 && -s "$OUTPUT_DIR/transcripts.fasta" ]]; then
    end_time=$(date +%s)
    runtime=$((end_time - start_time))
    
    echo "Assembly completed successfully in $runtime seconds" | tee -a $ASSEMBLY_LOG
    
    # Get assembly statistics
    num_transcripts=$(grep -c "^>" "$OUTPUT_DIR/transcripts.fasta")
    assembly_size=$(grep -v "^>" "$OUTPUT_DIR/transcripts.fasta" | tr -d '\n' | wc -c)
    assembly_size_mb=$(awk "BEGIN {printf \"%.2f\", $assembly_size / 1000000}")
    
    echo "Number of transcripts: $num_transcripts" | tee -a $ASSEMBLY_LOG
    echo "Assembly size: $assembly_size_mb Mb" | tee -a $ASSEMBLY_LOG
    
    # Add to summary file
    echo "Assembly,,Status,Completed" >> "$SUMMARY_FILE"
    echo "Assembly,,Runtime,$runtime seconds" >> "$SUMMARY_FILE"
    echo "Assembly,,Transcripts,$num_transcripts" >> "$SUMMARY_FILE"
    echo "Assembly,,Size,$assembly_size_mb Mb" >> "$SUMMARY_FILE"
else
    echo "Error: Assembly failed!" | tee -a $ASSEMBLY_LOG
    echo "Assembly,,Status,Failed" >> "$SUMMARY_FILE"
    exit 1
fi

