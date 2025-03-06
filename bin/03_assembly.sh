#! /bin/bash

# slurm parameters, see config/parameters.txt
#SBATCH --partition=medium-cpu
#SBATCH --time=24:00:00
#SBATCH --nodes=1
#SBATCH --cpus-per-task=16
#SBATCH --mem=64G
#SBATCH --job-name=rnaspades
# Log files will be specified when submitting the job

# input file variables passed in as arguments from main.sh
MERGED_R1=$1
MERGED_R2=$2
OUTPUT_DIR=$3
LOG_DIR=${4:-"logs/03_assembly"}
DEBUG_MODE=${5:-false}

# Create output directory if it doesn't exist
mkdir -p $OUTPUT_DIR
mkdir -p $LOG_DIR

# Create a log file for this assembly job
ASSEMBLY_LOG="$LOG_DIR/assembly_$(date +%Y%m%d_%H%M%S).log"
echo "Starting assembly job at $(date)" > $ASSEMBLY_LOG
echo "Merged R1: $MERGED_R1" >> $ASSEMBLY_LOG
echo "Merged R2: $MERGED_R2" >> $ASSEMBLY_LOG
echo "Output directory: $OUTPUT_DIR" >> $ASSEMBLY_LOG

# Debug mode: Check if output files already exist
if [[ "$DEBUG_MODE" == "true" && -s "$OUTPUT_DIR/transcripts.fasta" ]]; then
    echo "Debug mode: Assembly output already exists: $OUTPUT_DIR/transcripts.fasta. Skipping assembly." | tee -a $ASSEMBLY_LOG
    
    exit 0
fi

# Check if input files exist
if [[ ! -s "$MERGED_R1" || ! -s "$MERGED_R2" ]]; then
    echo "Error: One or both input files are missing or empty!" | tee -a $ASSEMBLY_LOG
    echo "MERGED_R1: $MERGED_R1 ($(du -h $MERGED_R1 2>/dev/null || echo 'missing'))" | tee -a $ASSEMBLY_LOG
    echo "MERGED_R2: $MERGED_R2 ($(du -h $MERGED_R2 2>/dev/null || echo 'missing'))" | tee -a $ASSEMBLY_LOG
    
    exit 1
fi

# Run rnaSPAdes
echo "Running rnaSPAdes..." | tee -a $ASSEMBLY_LOG

# Get start time for timing
start_time=$(date +%s)

# Run rnaSPAdes with appropriate parameters
rnaspades.py \
    --rna \
    -1 "$MERGED_R1" \
    -2 "$MERGED_R2" \
    -o "$OUTPUT_DIR" \
    -t 16 \
    -m 64 \
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
else
    echo "Error: Assembly failed!" | tee -a $ASSEMBLY_LOG
    exit 1
fi

