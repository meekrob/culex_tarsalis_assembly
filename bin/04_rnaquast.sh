#! /bin/bash

# slurm parameters, see config/parameters.txt
#SBATCH --partition=short-cpu
#SBATCH --time=01:00:00
#SBATCH --nodes=1
#SBATCH --cpus-per-task=24
#SBATCH --mem=32G
#SBATCH --job-name=rnaquast
#SBATCH --output=logs/rnaquast_%j.out
#SBATCH --error=logs/rnaquast_%j.err

# Source configuration
source config/parameters.txt

# input file variables passed in as arguments from main_mosquito.sh
ASSEMBLY=$1  # Path to the assembly fasta file
OUT=$2       # Output directory
left=$3      # R1 fastq file for read mapping
right=$4     # R2 fastq file for read mapping
other_opts=${5:-"${rnaQuast.opts}"}  # Additional options for rnaQuast

# Create output directory if it doesn't exist
mkdir -p $OUT

# activate conda env
source ~/.bashrc
conda activate cellSquito

echo "Starting rnaQuast analysis"
echo "Input assembly: $ASSEMBLY"
echo "Output directory: $OUT"
echo "Input R1: $left"
echo "Input R2: $right"
echo "Additional options: $other_opts"

# Check if input files exist
if [[ ! -f "$ASSEMBLY" ]]; then
    echo "Error: Assembly file $ASSEMBLY not found!"
    exit 1
fi

if [[ ! -f "$left" || ! -f "$right" ]]; then
    echo "Error: Read files not found!"
    exit 1
fi

# run rnaquast on the assembly from rnaspades
cmd="rnaquast.py --transcripts $ASSEMBLY -t ${rnaQuast.threads} -o $OUT -1 $left -2 $right $other_opts"
echo "Executing command: $cmd"
time eval $cmd

# Check if rnaQuast completed successfully
if [[ -f "$OUT/report.pdf" || -f "$OUT/report.html" ]]; then
    echo "rnaQuast analysis completed successfully!"
    echo "rnaQuast summary:"
    cat $OUT/report.txt
else
    echo "Error: rnaQuast analysis failed or report files not found!"
    exit 1
fi

# store results in results/04_quality_analysis

# output error and log files to logs directory rnaquast_jobid. err and .out respectively