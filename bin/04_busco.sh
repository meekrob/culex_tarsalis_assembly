#! /bin/bash

# slurm parameters, see config/parameters.txt
#SBATCH --partition=short-cpu
#SBATCH --time=01:00:00
#SBATCH --nodes=1
#SBATCH --cpus-per-task=24
#SBATCH --mem=32G
#SBATCH --job-name=busco
#SBATCH --output=logs/busco_%j.out
#SBATCH --error=logs/busco_%j.err

# Source configuration
source config/parameters.txt

# input file variables passed in as arguments from main_mosquito.sh
TX_FASTA=$1  # Path to transcriptome assembly fasta file
OUT=$2       # Output directory
BUSCO_DOWNLOADS=${3:-"./busco_downloads"}  # Path to store BUSCO datasets
ASSEMBLY_LABEL=${4:-"transcriptome"}  # Label for this assembly

# Create output directory if it doesn't exist
mkdir -p $OUT
mkdir -p $BUSCO_DOWNLOADS
mkdir -p logs

# activate conda env
source ~/.bashrc
conda activate cellSquito

echo "Starting BUSCO analysis"
echo "Input transcriptome: $TX_FASTA"
echo "Output directory: $OUT"
echo "BUSCO downloads path: $BUSCO_DOWNLOADS"
echo "Assembly label: $ASSEMBLY_LABEL"

# Check if input file exists
if [[ ! -f "$TX_FASTA" ]]; then
    echo "Error: Transcriptome file $TX_FASTA not found!"
    exit 1
fi

# run busco on the assembly from rnaspades using configurable parameters
cmd="busco -i $TX_FASTA --download_path $BUSCO_DOWNLOADS --lineage_dataset ${busco.lineage} --mode ${busco.mode} --cpu $SLURM_CPUS_PER_TASK --out $OUT"
echo "Executing command: $cmd"
time eval $cmd

# Improved error handling
if [[ $? -ne 0 ]]; then
    echo "Error: BUSCO analysis failed!" >&2
    exit 1
fi

# Check if BUSCO completed successfully and add to summary log
SUMMARY_FILE=$(find $OUT -name "short_summary.*.txt" | head -n 1)
if [[ -f "$SUMMARY_FILE" ]]; then
    echo "BUSCO analysis completed successfully!"
    echo "BUSCO summary:"
    cat $SUMMARY_FILE
    
    # Add to global BUSCO summary file
    echo "Results for $ASSEMBLY_LABEL" >> logs/busco_summary.txt
    cat $SUMMARY_FILE >> logs/busco_summary.txt
    echo "-------------------" >> logs/busco_summary.txt
else
    echo "Error: BUSCO analysis failed or summary file not found!"
    exit 1
fi

# store results in results/04_quality_analysis

# output error and log files to logs directory _jobid. err and .out respectively