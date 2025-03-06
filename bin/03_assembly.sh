#! /bin/bash

# slurm parameters, see config/parameters.txt
#SBATCH --partition=week-long-highmem
#SBATCH --time=7-00:00:00
#SBATCH --nodes=2
#SBATCH --cpus-per-task=32
#SBATCH --mem=250G
#SBATCH --job-name=rnaspades
#SBATCH --output=logs/assembly_%j.out
#SBATCH --error=logs/assembly_%j.err

# Source configuration
source config/parameters.txt

# input file variables passed in as arguments from main_mosquito.sh
left=$1    # Merged and trimmed R1 file
right=$2   # Merged and trimmed R2 file
out=$3     # Output directory for assembly
other_opts=${4:-"${rnaSpades.opts}"}  # Additional options for rnaSPAdes (optional)

# Enhance input validation
for f in "$left" "$right"; do
    if [[ ! -f "$f" ]]; then
        echo "Error: Input file $f not found!" >&2
        exit 1
    fi
done

# Create output directory if it doesn't exist
mkdir -p $out

# activate conda env
source ~/.bashrc
conda activate cellSquito

echo "Starting RNA-Seq assembly with rnaSPAdes"
echo "Input R1: $left"
echo "Input R2: $right" 
echo "Output directory: $out"
echo "Additional options: $other_opts"

# Set up temporary directory for rnaSPAdes - more flexible approach
TMP="${TMPDIR:-$HOME/tmp}"
mkdir -p $TMP
export TMPDIR=$TMP
echo "Using temporary directory: $TMPDIR"

# run rnaspades with configurable threads
cmd="rnaspades.py -t ${rnaSpades.threads} -1 $left -2 $right -o $out $other_opts" 
echo "Executing command: $cmd"
time eval $cmd

# Improved error handling
if [[ $? -ne 0 ]]; then
    echo "Error: rnaSPAdes assembly failed!" >&2
    exit 1
fi

# Check if assembly completed successfully
if [[ -f "$out/transcripts.fasta" ]]; then
    echo "Assembly completed successfully!"
    echo "Assembly statistics:"
    grep -A 4 "Assembly summary" $out/spades.log
    
    # Add some basic stats to a log file
    mkdir -p logs
    echo "Assembly Statistics" > logs/assembly_stats.txt
    echo "Date: $(date)" >> logs/assembly_stats.txt
    echo "Input files: $left, $right" >> logs/assembly_stats.txt
    grep -A 10 "Assembly summary" $out/spades.log >> logs/assembly_stats.txt
else
    echo "Error: Assembly failed or transcripts.fasta not found!"
    exit 1
fi

# store results in results/03_assembly

# output error and log files to logs directory assembly_jobid. err and .out respectively

