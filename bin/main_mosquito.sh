#!/bin/bash



#define paths and variables

# Define directories (adjust these as needed)
raw_reads_dir="/data/raw_reads"           # Directory with raw fastq files
trimmed_dir="/data/trimmed" # Directory for fastp output
ref_transcriptome_dir="/data/ref_transcriptome" # Directory for transcriptome
merged_r1_file="${trimmed_dir}/merged_r1.fastq"  # Output of cat script
merged_r2_file="${trimmed_dir}/merged_r2.fastq"  # Output of cat script
assembly_dir="/results/assembly"             # Output directory for rnaSpades
busco_dir="/results/busco"               # Output directory for busco
rnaquast_dir="/results/rnaquast"         # Output directory for rnaquast

# Create output directories if they don’t exist
mkdir -p "$trimmed_dir" "$assembly_dir" "$busco_dir" "$rnaquast_dir"

### Step 1: Parse Raw Reads and Identify Pairs
# Find all R1 files and extract sample names
# example name: trimmed.Cxt-r2-35_R1_001.fastq.gz

R1_files=($(ls ${raw_reads_dir}/*_R1*.fastq))
samples=()
for file in "${R1_files[@]}"; do
	# Extract the filename without the path using the basename function
	filename=$(basename "$file")
	# Extract everything before '_R1' using parameter expansion
	samples+=("$sample")
done

# Optional: Print samples for verification
echo "Found ${#samples[@]} R1 files:"
for sample in "${samples[@]}"; do
    echo "Sample: $sample"
done










#
