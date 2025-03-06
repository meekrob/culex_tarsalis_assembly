#! /bin/bash

# slurm parameters, see config/parameters.txt
#SBATCH --partition=short-cpu
#SBATCH --time=01:00:00
#SBATCH --nodes=1
#SBATCH --cpus-per-task=2
#SBATCH --mem=16G
#SBATCH --job-name=cat_merge
# Log files will be specified when submitting the job

# input file variables passed in as arguments from main_mosquito.sh
R1_LIST=$1  # File containing list of R1 files to merge
R2_LIST=$2  # File containing list of R2 files to merge
OUT_R1=$3   # Output merged R1 file
OUT_R2=$4   # Output merged R2 file
LOG_DIR=${5:-"logs/02_merge"}  # Directory for logs

# Create output directory if it doesn't exist
mkdir -p $(dirname $OUT_R1)
mkdir -p $LOG_DIR

# activate conda env
source ~/.bashrc
conda activate cellSquito

echo "Merging R1 files from list: $R1_LIST"
echo "Merging R2 files from list: $R2_LIST"
echo "Output R1: $OUT_R1"
echo "Output R2: $OUT_R2"

# run cat for both r1 file list and r2 file list in parallel
# Create a function to merge files using xargs for parallel processing
merge_files() {
    list_file=$1
    output_file=$2
    echo "Starting merge for files in $list_file into $output_file"
    
    # Check if list file exists and has content
    if [[ ! -f "$list_file" || ! -s "$list_file" ]]; then
        echo "Error: List file $list_file doesn't exist or is empty!"
        exit 1
    fi
    
    # Use xargs to parallelize the cat operation
    cat $list_file | xargs cat > $output_file
    
    echo "Completed merge into $output_file"
}

# Run merges in parallel
merge_files $R1_LIST $OUT_R1 &
pid1=$!
merge_files $R2_LIST $OUT_R2 &
pid2=$!

# Wait for both to finish
wait $pid1 $pid2

# Check if both processes completed successfully
if [[ $? -eq 0 ]]; then
    echo "Merging completed successfully!"
    
    # Report file sizes
    echo "Merged R1 file size: $(du -h $OUT_R1 | cut -f1)"
    echo "Merged R2 file size: $(du -h $OUT_R2 | cut -f1)"
else
    echo "Error: Merging failed!"
    exit 1
fi

# store results in results/02_merge

# output error and log files to logs directory mergefq_jobid. err and .out respectively