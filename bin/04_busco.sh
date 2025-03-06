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

# input file variables passed in as arguments from main_mosquito.sh
TX_FASTA=$1  # Path to transcriptome assembly fasta file
OUT=$2       # Output directory
BUSCO_DOWNLOADS=${3:-"./busco_downloads"}  # Path to store BUSCO datasets

# Create output directory if it doesn't exist
mkdir -p $OUT
mkdir -p $BUSCO_DOWNLOADS

# activate conda env
source ~/.bashrc
conda activate cellSquito

echo "Starting BUSCO analysis"
echo "Input transcriptome: $TX_FASTA"
echo "Output directory: $OUT"
echo "BUSCO downloads path: $BUSCO_DOWNLOADS"

# Check if input file exists
if [[ ! -f "$TX_FASTA" ]]; then
    echo "Error: Transcriptome file $TX_FASTA not found!"
    exit 1
fi

# run busco on the assembly from rnaspades
cmd="busco -i $TX_FASTA --download_path $BUSCO_DOWNLOADS --lineage_dataset diptera_odb10 --mode transcriptome --cpu $SLURM_CPUS_PER_TASK --out $OUT"
echo "Executing command: $cmd"
time eval $cmd

# Check if BUSCO completed successfully
if [[ -f "$OUT/short_summary.*.txt" ]]; then
    echo "BUSCO analysis completed successfully!"
    echo "BUSCO summary:"
    cat $OUT/short_summary.*.txt
else
    echo "Error: BUSCO analysis failed or summary file not found!"
    exit 1
fi

# store results in results/04_quality_analysis

# output error and log files to logs directory _jobid. err and .out respectively