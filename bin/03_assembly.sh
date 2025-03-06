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

# input file variables passed in as arguments from main_mosquito.sh
left=$1    # Merged and trimmed R1 file
right=$2   # Merged and trimmed R2 file
out=$3     # Output directory for assembly
other_opts=${4:-""}  # Additional options for rnaSPAdes (optional)

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

# Set up temporary directory for rnaSPAdes
mkdir -p $HOME/tmp
export TMP=$HOME/tmp
export TMPDIR=$TMP
echo "Using temporary directory: $TMPDIR"

# run rnaspades 
cmd="rnaspades.py -t $SLURM_CPUS_PER_TASK -1 $left -2 $right -o $out $other_opts" 
echo "Executing command: $cmd"
time eval $cmd

# Check if assembly completed successfully
if [[ -f "$out/transcripts.fasta" ]]; then
    echo "Assembly completed successfully!"
    echo "Assembly statistics:"
    grep -A 4 "Assembly summary" $out/spades.log
else
    echo "Error: Assembly failed or transcripts.fasta not found!"
    exit 1
fi

# store results in results/03_assembly

# output error and log files to logs directory assembly_jobid. err and .out respectively

