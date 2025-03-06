#! /bin/bash

# slurm parameters from config/parameters.txt
#SBATCH --partition=short-cpu
#SBATCH --time=00:30:00
#SBATCH --nodes=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=4G
#SBATCH --job-name=visualize
# Log files will be specified when submitting the job

# Source configuration
source config/parameters.txt

# input file variables passed in as arguments from main_mosquito.sh
BUSCO_DIR=$1     # Directory with BUSCO results
RNAQUAST_DIR=$2  # Directory with rnaQuast results
OUT_DIR=$3       # Output directory for visualizations
# Optional arguments for draft transcriptome comparison
DRAFT_BUSCO_DIR=${4:-""}  # Draft BUSCO results
DRAFT_RNAQUAST_DIR=${5:-""}  # Draft rnaQuast results
LOG_DIR=${6:-"logs/05_visualization"}  # Directory for logs

# Create necessary directories
mkdir -p $OUT_DIR
mkdir -p $LOG_DIR

# activate conda env
source ~/.bashrc
conda activate cellSquito

echo "Starting visualization of pipeline results"
echo "BUSCO results: $BUSCO_DIR"
echo "rnaQuast results: $RNAQUAST_DIR"
echo "Output directory: $OUT_DIR"

# Add draft transcriptome arguments if provided
if [[ -n "$DRAFT_BUSCO_DIR" && -n "$DRAFT_RNAQUAST_DIR" ]]; then
    echo "Draft BUSCO results: $DRAFT_BUSCO_DIR"
    echo "Draft rnaQuast results: $DRAFT_RNAQUAST_DIR"
    Rscript bin/visualize.R "$BUSCO_DIR" "$RNAQUAST_DIR" "$OUT_DIR" "$DRAFT_BUSCO_DIR" "$DRAFT_RNAQUAST_DIR"
else
    # Run R script for visualization (no draft)
    Rscript bin/visualize.R "$BUSCO_DIR" "$RNAQUAST_DIR" "$OUT_DIR"
fi

# Check if visualization completed successfully
if [[ $? -eq 0 ]]; then
    echo "Visualization completed successfully!"
    echo "Results are available in: $OUT_DIR"
else
    echo "Error: Visualization failed!"
    exit 1
fi