#!/bin/bash

# SLURM parameters
#SBATCH --partition=some-partition
#SBATCH --time=24:00:00
#SBATCH --nodes=1
#SBATCH --cpus-per-task=16
#SBATCH --mem=64G
#SBATCH --job-name=braker
# Log files will be specified when submitting the job

# Input arguments
GENOME_FASTA=$1
BAM_FILE=$2
OUTPUT_DIR=$3
LOG_DIR=${4:-"logs/braker"}
DEBUG_MODE=${5:-false}
SUMMARY_FILE=${6:-"logs/pipeline_summary.csv"}
SPECIES_NAME=$7  # e.g., "mosquito"

# Set Singularity image path
SIF_PATH=/nfs/home/jlamb/Projects/mosquito_denovo/pipelines/maker_annotator/braker.sif

# Create output and log directories
mkdir -p $OUTPUT_DIR
mkdir -p $LOG_DIR

# Create log file
BRAKER_LOG="$LOG_DIR/braker_$(date +%Y%m%d_%H%M%S).log"
echo "Starting Braker job at $(date)" > $BRAKER_LOG
echo "Genome: $GENOME_FASTA" >> $BRAKER_LOG
echo "BAM file: $BAM_FILE" >> $BRAKER_LOG
echo "Output directory: $OUTPUT_DIR" >> $BRAKER_LOG

# Determine directories to bind
GENOME_DIR=$(dirname $GENOME_FASTA)
BAM_DIR=$(dirname $BAM_FILE)
RepeatMasker_DIR

# Start timing
start_time=$(date +%s)

# Debug mode: Check if output files already exist
if [[ "$DEBUG_MODE" == "true" && -d "$OUTPUT_DIR/braker" && -f "$OUTPUT_DIR/braker/augustus.hints.gtf" ]]; then
    echo "Debug mode: BRAKER output already exists. Skipping BRAKER execution." | tee -a $BRAKER_LOG
    echo "BRAKER,$SPECIES_NAME,Status,Skipped (files exist)" >> "$SUMMARY_FILE"
    exit 0
fi

# Check if input files exist
if [[ ! -s "$GENOME_FASTA" ]]; then
    echo "Error: Genome FASTA file is missing or empty: $GENOME_FASTA" | tee -a $BRAKER_LOG
    echo "BRAKER,$SPECIES_NAME,Status,Failed (missing genome)" >> "$SUMMARY_FILE"
    exit 1
fi

if [[ ! -s "$BAM_FILE" ]]; then
    echo "Error: BAM file is missing or empty: $BAM_FILE" | tee -a $BRAKER_LOG
    echo "BRAKER,$SPECIES_NAME,Status,Failed (missing BAM)" >> "$SUMMARY_FILE"
    exit 1
fi

# Run Braker using Singularity
echo "Running Braker..." | tee -a $BRAKER_LOG

singularity exec \
    --bind $GENOME_DIR:/genome,$BAM_DIR:/bam,$OUTPUT_DIR:/output \
    $SIF_PATH \
    braker.pl --genome=/genome/$(basename $GENOME_FASTA) \
              --bam=/bam/$(basename $BAM_FILE) \
              --species=$SPECIES_NAME \
              --cores=$SLURM_CPUS_PER_TASK \
              --workingdir=/output \
              --softmasking \
              --gff3 \
              --UTR=on \
              2>> $BRAKER_LOG

# Check if BRAKER completed successfully
if [[ $? -eq 0 && -f "$OUTPUT_DIR/braker/augustus.hints.gtf" ]]; then
    end_time=$(date +%s)
    runtime=$((end_time - start_time))
    
    echo "BRAKER completed successfully in $runtime seconds" | tee -a $BRAKER_LOG
    
    # Count number of gene models predicted
    num_genes=$(grep -c "^#" "$OUTPUT_DIR/braker/augustus.hints.gtf" || echo "unknown")
    
    echo "Number of gene models: $num_genes" | tee -a $BRAKER_LOG
    
    # Add to summary file
    echo "BRAKER,$SPECIES_NAME,Status,Completed" >> "$SUMMARY_FILE"
    echo "BRAKER,$SPECIES_NAME,Runtime,$runtime seconds" >> "$SUMMARY_FILE"
    echo "BRAKER,$SPECIES_NAME,Gene Models,$num_genes" >> "$SUMMARY_FILE"
    
    # Create symlinks to important output files in the main output directory
    ln -sf "$OUTPUT_DIR/braker/augustus.hints.gtf" "$OUTPUT_DIR/augustus.hints.gtf"
    ln -sf "$OUTPUT_DIR/braker/augustus.hints.aa" "$OUTPUT_DIR/augustus.hints.aa"
    ln -sf "$OUTPUT_DIR/braker/augustus.hints.gff3" "$OUTPUT_DIR/augustus.hints.gff3"
    
    exit 0
else
    echo "Error: BRAKER failed!" | tee -a $BRAKER_LOG
    echo "BRAKER,$SPECIES_NAME,Status,Failed" >> "$SUMMARY_FILE"
    exit 1
fi