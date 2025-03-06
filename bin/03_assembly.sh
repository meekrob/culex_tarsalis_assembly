#! /bin/bash

# slurm parameters, see config/parameters.txt
#SBATCH --partition=week-long-highmem
#SBATCH --time=7-00:00:00
#SBATCH --nodes=2
#SBATCH --cpus-per-task=32
#SBATCH --mem=250G
#SBATCH --job-name=rnaspades
# Log files will be specified when submitting the job

# Source configuration
source config/parameters.txt

# input file variables passed in as arguments from main_mosquito.sh
left=$1    # Merged and trimmed R1 file
right=$2   # Merged and trimmed R2 file
out=$3     # Output directory for assembly
other_opts=${4:-"${rnaSpades_opts}"}  # Additional options for rnaSPAdes (optional)
LOG_DIR=${5:-"logs/03_assembly"}  # Directory for logs

# Enhance input validation
for f in "$left" "$right"; do
    if [[ ! -f "$f" ]]; then
        echo "Error: Input file $f not found!" >&2
        exit 1
    fi
done

# Create necessary directories
mkdir -p $out
mkdir -p $LOG_DIR

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
cmd="rnaspades.py -t ${rnaSpades_threads} -1 $left -2 $right -o $out $other_opts" 
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
    echo "Assembly Statistics" > $LOG_DIR/assembly_stats.txt
    echo "Date: $(date)" >> $LOG_DIR/assembly_stats.txt
    echo "Input files: $left, $right" >> $LOG_DIR/assembly_stats.txt
    grep -A 10 "Assembly summary" $out/spades.log >> $LOG_DIR/assembly_stats.txt
else
    echo "Error: Assembly failed or transcripts.fasta not found!"
    exit 1
fi

# store results in results/03_assembly

# output error and log files to logs directory assembly_jobid. err and .out respectively

