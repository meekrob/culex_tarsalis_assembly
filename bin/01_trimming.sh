#! /bin/bash

# slurm parameters, see config/parameters.txt
#SBATCH --partition=short-cpu
#SBATCH --time=01:00:00
#SBATCH --nodes=1
#SBATCH --cpus-per-task=17
#SBATCH --mem=8G
#SBATCH --job-name=fastp_trim
#SBATCH --output=logs/fastp_%j.out
#SBATCH --error=logs/fastp_%j.err

# input file variables passed in as arguments from main_mosquito.sh
FILE=$1    # R1 input file
TWO=$2     # R2 input file  
TRIM1=$3   # R1 output file
TRIM2=$4   # R2 output file
SAMPLE_NAME=$5  # Sample name for logs/reporting

# Create output directory if it doesn't exist
mkdir -p $(dirname $TRIM1)
mkdir -p htmls  # Create directory for HTML reports

# activate conda env
source ~/.bashrc
conda activate cellSquito

echo "Processing sample: $SAMPLE_NAME"
echo "Input R1: $FILE"
echo "Input R2: $TWO"
echo "Output R1: $TRIM1"
echo "Output R2: $TRIM2"

# run fastp 
cmd="fastp -i ${FILE} -I ${TWO} \
             -o ${TRIM1} -O ${TRIM2} \
             -h htmls/$(basename $FILE).html -j htmls/$(basename $FILE).json \
             -w $((SLURM_CPUS_PER_TASK-1)) --dedup"
echo "Executing command: $cmd"
time eval $cmd

echo "Trimming completed for sample $SAMPLE_NAME"

# Results are stored in the path specified by TRIM1 and TRIM2
# HTML and JSON reports are stored in the htmls directory