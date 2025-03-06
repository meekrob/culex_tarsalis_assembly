#! /bin/bash

# slurm parameters, see config/parameters.txt
#SBATCH --partition=short-cpu
#SBATCH --time=04:00:00
#SBATCH --nodes=1
#SBATCH --cpus-per-task=16
#SBATCH --mem=32G
#SBATCH --job-name=busco
# Log files will be specified when submitting the job

# input file variables passed in as arguments from main_mosquito.sh
TX_FASTA=$1    # Transcriptome fasta file
OUT=$2         # Output directory
BUSCO_DOWNLOADS=${3:-"./busco_downloads"}  # Directory for BUSCO downloads
ASSEMBLY_LABEL=${4:-"assembly"}  # Label for the assembly
LOG_DIR=${5:-"logs/04_busco"}  # Directory for logs
SUMMARY_FILE=${6:-"logs/pipeline_summary.csv"}  # Summary file path
DEBUG_MODE=${7:-false}  # Debug mode flag

# Source configuration
source config/parameters.txt

# Create output directory if it doesn't exist
mkdir -p $OUT
mkdir -p $LOG_DIR
mkdir -p $BUSCO_DOWNLOADS

# Debug mode: Check if output files already exist
SUMMARY_FILE_PATH="$OUT/short_summary.specific.${busco_lineage}.${ASSEMBLY_LABEL}.txt"
if [[ "$DEBUG_MODE" == "true" && -s "$SUMMARY_FILE_PATH" ]]; then
    echo "Debug mode: BUSCO summary already exists: $SUMMARY_FILE_PATH. Skipping BUSCO analysis."
    
    # Add entry to summary file
    echo "BUSCO,$ASSEMBLY_LABEL,Status,Skipped (files exist)" >> "$SUMMARY_FILE"
    
    # Extract key metrics from the summary file
    if [[ -f "$SUMMARY_FILE_PATH" ]]; then
        complete=$(grep "C:" "$SUMMARY_FILE_PATH" | cut -d'[' -f1 | awk '{print $1}')
        single=$(grep "C:" "$SUMMARY_FILE_PATH" | awk '{print $2}' | tr -d 'S:')
        duplicated=$(grep "C:" "$SUMMARY_FILE_PATH" | awk '{print $3}' | tr -d 'D:')
        fragmented=$(grep "F:" "$SUMMARY_FILE_PATH" | awk '{print $1}' | tr -d 'F:')
        missing=$(grep "M:" "$SUMMARY_FILE_PATH" | awk '{print $1}' | tr -d 'M:')
        
        echo "BUSCO,$ASSEMBLY_LABEL,Complete,$complete" >> "$SUMMARY_FILE"
        echo "BUSCO,$ASSEMBLY_LABEL,Single Copy,$single" >> "$SUMMARY_FILE"
        echo "BUSCO,$ASSEMBLY_LABEL,Duplicated,$duplicated" >> "$SUMMARY_FILE"
        echo "BUSCO,$ASSEMBLY_LABEL,Fragmented,$fragmented" >> "$SUMMARY_FILE"
        echo "BUSCO,$ASSEMBLY_LABEL,Missing,$missing" >> "$SUMMARY_FILE"
    fi
    
    exit 0
fi

# activate conda env
source ~/.bashrc
conda activate cellSquito

echo "Starting BUSCO analysis"
echo "Transcriptome: $TX_FASTA"
echo "Output directory: $OUT"
echo "BUSCO downloads: $BUSCO_DOWNLOADS"
echo "Assembly label: $ASSEMBLY_LABEL"

# run busco on the assembly from rnaspades using configurable parameters
cmd="busco -i $TX_FASTA --download_path $BUSCO_DOWNLOADS --lineage_dataset ${busco_lineage} --mode ${busco_mode} --cpu $SLURM_CPUS_PER_TASK --out $ASSEMBLY_LABEL -f"
echo "Executing command: $cmd"
time eval $cmd

# Check if BUSCO was successful
if [[ $? -ne 0 ]]; then
    echo "Error: BUSCO failed!" >&2
    echo "BUSCO,$ASSEMBLY_LABEL,Status,Failed" >> "$SUMMARY_FILE"
    exit 1
fi

# Move BUSCO output to the specified output directory
if [[ -d "$ASSEMBLY_LABEL" ]]; then
    mv $ASSEMBLY_LABEL/* $OUT/
    rmdir $ASSEMBLY_LABEL
fi

# Check if output files were created
if [[ ! -s "$SUMMARY_FILE_PATH" ]]; then
    echo "Error: BUSCO summary file is missing or empty!" >&2
    echo "BUSCO,$ASSEMBLY_LABEL,Status,Failed (missing output)" >> "$SUMMARY_FILE"
    exit 1
fi

echo "BUSCO analysis completed successfully!"

# Extract key metrics from the summary file
complete=$(grep "C:" "$SUMMARY_FILE_PATH" | cut -d'[' -f1 | awk '{print $1}')
single=$(grep "C:" "$SUMMARY_FILE_PATH" | awk '{print $2}' | tr -d 'S:')
duplicated=$(grep "C:" "$SUMMARY_FILE_PATH" | awk '{print $3}' | tr -d 'D:')
fragmented=$(grep "F:" "$SUMMARY_FILE_PATH" | awk '{print $1}' | tr -d 'F:')
missing=$(grep "M:" "$SUMMARY_FILE_PATH" | awk '{print $1}' | tr -d 'M:')

# Add BUSCO statistics to summary file
echo "BUSCO,$ASSEMBLY_LABEL,Status,Completed" >> "$SUMMARY_FILE"
echo "BUSCO,$ASSEMBLY_LABEL,Complete,$complete" >> "$SUMMARY_FILE"
echo "BUSCO,$ASSEMBLY_LABEL,Single Copy,$single" >> "$SUMMARY_FILE"
echo "BUSCO,$ASSEMBLY_LABEL,Duplicated,$duplicated" >> "$SUMMARY_FILE"
echo "BUSCO,$ASSEMBLY_LABEL,Fragmented,$fragmented" >> "$SUMMARY_FILE"
echo "BUSCO,$ASSEMBLY_LABEL,Missing,$missing" >> "$SUMMARY_FILE"

echo "BUSCO results saved to $OUT"
echo "BUSCO summary file: $SUMMARY_FILE_PATH"

# output error and log files to logs directory _jobid. err and .out respectively