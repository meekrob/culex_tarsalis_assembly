#! /bin/bash

# slurm parameters, see config/parameters.txt
#SBATCH --partition=week-long
#SBATCH --time=24:00:00
#SBATCH --nodes=2
#SBATCH --cpus-per-task=32
#SBATCH --mem=128G
#SBATCH --job-name=rnaspades
# Log files will be specified when submitting the job

# input file variables passed in as arguments from main_mosquito.sh
left=$1    # R1 input file (merged)
right=$2   # R2 input file (merged)
out=$3     # Output directory
other_opts=${4:-""}  # Additional options for rnaspades
LOG_DIR=${5:-"logs/03_assembly"}  # Directory for logs
SUMMARY_FILE=${6:-"logs/pipeline_summary.csv"}  # Summary file path
DEBUG_MODE=${7:-false}  # Debug mode flag

# Create output directory if it doesn't exist
mkdir -p $out
mkdir -p $LOG_DIR

# Debug mode: Check if output files already exist
if [[ "$DEBUG_MODE" == "true" && -s "$out/transcripts.fasta" ]]; then
    echo "Debug mode: Assembly file already exists: $out/transcripts.fasta. Skipping assembly."
    
    # Add entry to summary file
    echo "Assembly,,Status,Skipped (files exist)" >> "$SUMMARY_FILE"
    
    # Extract some basic stats for the summary file if possible
    if [[ -f "$out/spades.log" ]]; then
        # Try to extract stats from log file
        num_transcripts=$(grep -m 1 "transcripts:" "$out/spades.log" | awk '{print $NF}' || echo "Unknown")
        total_length=$(grep -m 1 "Total length:" "$out/spades.log" | awk '{print $NF}' || echo "Unknown")
        n50=$(grep -m 1 "N50:" "$out/spades.log" | awk '{print $NF}' || echo "Unknown")
        
        echo "Assembly,,Number of Transcripts,$num_transcripts" >> "$SUMMARY_FILE"
        echo "Assembly,,Total Length,$total_length" >> "$SUMMARY_FILE"
        echo "Assembly,,N50,$n50" >> "$SUMMARY_FILE"
    else
        # If log not available, count transcripts directly
        num_transcripts=$(grep -c "^>" "$out/transcripts.fasta" || echo "Unknown")
        echo "Assembly,,Number of Transcripts,$num_transcripts" >> "$SUMMARY_FILE"
    fi
    
    exit 0
fi

# activate conda env
source ~/.bashrc
conda activate cellSquito

echo "Starting RNA-Seq assembly with rnaSPAdes"
echo "Left reads: $left"
echo "Right reads: $right"
echo "Output directory: $out"
echo "Additional options: $other_opts"

# run rnaspades with configurable threads
cmd="rnaspades.py -t ${SLURM_CPUS_PER_TASK} -1 $left -2 $right -o $out $other_opts"
echo "Executing command: $cmd"
time eval $cmd

# Check if assembly was successful
if [[ $? -ne 0 ]]; then
    echo "Error: rnaSPAdes failed!" >&2
    echo "Assembly,,Status,Failed" >> "$SUMMARY_FILE"
    exit 1
fi

# Check if output files were created
if [[ ! -s "$out/transcripts.fasta" ]]; then
    echo "Error: Output file $out/transcripts.fasta is missing or empty!" >&2
    echo "Assembly,,Status,Failed (missing output)" >> "$SUMMARY_FILE"
    exit 1
fi

echo "Assembly completed successfully!"

# Extract assembly statistics
num_transcripts=$(grep -c "^>" "$out/transcripts.fasta")
total_length=$(grep -v "^>" "$out/transcripts.fasta" | tr -d '\n' | wc -c)

# Calculate N50 (this is a simplified approach)
# For a more accurate N50, consider using a dedicated tool like assembly-stats
echo "Calculating N50..."
# Extract sequence lengths
grep -v "^>" "$out/transcripts.fasta" | awk 'BEGIN{RS=">";FS="\n"}NR>1{seq="";for(i=2;i<=NF;i++)seq=seq$i;print length(seq)}' > "$out/seq_lengths.txt"
# Sort lengths in descending order
sort -nr "$out/seq_lengths.txt" > "$out/seq_lengths_sorted.txt"
# Calculate total length
total=$(awk '{sum+=$1}END{print sum}' "$out/seq_lengths.txt")
# Find N50
half_total=$(echo "$total/2" | bc)
sum=0
while read length; do
    sum=$((sum + length))
    if [[ $sum -ge $half_total ]]; then
        n50=$length
        break
    fi
done < "$out/seq_lengths_sorted.txt"

# Add assembly statistics to summary file
echo "Assembly,,Status,Completed" >> "$SUMMARY_FILE"
echo "Assembly,,Number of Transcripts,$num_transcripts" >> "$SUMMARY_FILE"
echo "Assembly,,Total Length,$total_length" >> "$SUMMARY_FILE"
echo "Assembly,,N50,$n50" >> "$SUMMARY_FILE"

# Save assembly statistics to a file
echo "Assembly Statistics" > "$out/assembly_stats.txt"
echo "-------------------" >> "$out/assembly_stats.txt"
echo "Number of transcripts: $num_transcripts" >> "$out/assembly_stats.txt"
echo "Total length: $total_length" >> "$out/assembly_stats.txt"
echo "N50: $n50" >> "$out/assembly_stats.txt"

echo "Assembly statistics saved to $out/assembly_stats.txt"
echo "Transcripts saved to $out/transcripts.fasta"

