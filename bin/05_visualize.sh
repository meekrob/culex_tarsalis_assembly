#! /bin/bash

# slurm parameters - no specific parameters in the config file, using standard values
#SBATCH --partition=short-cpu
#SBATCH --time=00:30:00
#SBATCH --nodes=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=4G
#SBATCH --job-name=visualize
#SBATCH --output=logs/visualize_%j.out
#SBATCH --error=logs/visualize_%j.err

# input file variables passed in as arguments from main_mosquito.sh
BUSCO_DIR=$1     # Directory with BUSCO results
RNAQUAST_DIR=$2  # Directory with rnaQuast results
OUT_DIR=$3       # Output directory for visualizations

# Create output directory if it doesn't exist
mkdir -p $OUT_DIR

# activate conda env
source ~/.bashrc
conda activate cellSquito

echo "Starting visualization of pipeline results"
echo "BUSCO results: $BUSCO_DIR"
echo "rnaQuast results: $RNAQUAST_DIR"
echo "Output directory: $OUT_DIR"

# Run R script for visualization
Rscript bin/visualize.R "$BUSCO_DIR" "$RNAQUAST_DIR" "$OUT_DIR"

# Check if visualization completed successfully
if [[ $? -eq 0 ]]; then
    echo "Visualization completed successfully!"
    echo "Results are available in: $OUT_DIR"
else
    echo "Error: Visualization failed!"
    exit 1
fi