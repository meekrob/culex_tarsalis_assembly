#!/bin/bash

# Print the config file for inspection
echo "=== Current config.yaml ==="
cat config/config.yaml

# Function to detect sample patterns with validation
detect_samples() {
  python -c "
import os
import sys

SAMPLES = []
INCOMPLETE = []
raw_reads_dir = 'data/raw_reads'

if os.path.exists(raw_reads_dir):
    # First pass - find all potential sample names
    potential_samples = set()
    for f in os.listdir(raw_reads_dir):
        if f.endswith('.fastq.gz'):
            if '_R1_001.fastq.gz' in f:
                sample = f.replace('_R1_001.fastq.gz', '')
                potential_samples.add(sample)
            elif '_R1.fastq.gz' in f:
                sample = f.replace('_R1.fastq.gz', '')
                potential_samples.add(sample)
            elif '_R2_001.fastq.gz' in f:
                sample = f.replace('_R2_001.fastq.gz', '')
                potential_samples.add(sample)
            elif '_R2.fastq.gz' in f:
                sample = f.replace('_R2.fastq.gz', '')
                potential_samples.add(sample)
    
    # Second pass - validate each sample has both R1 and R2
    for sample in potential_samples:
        r1_exists = os.path.exists(os.path.join(raw_reads_dir, f'{sample}_R1_001.fastq.gz')) or os.path.exists(os.path.join(raw_reads_dir, f'{sample}_R1.fastq.gz'))
        r2_exists = os.path.exists(os.path.join(raw_reads_dir, f'{sample}_R2_001.fastq.gz')) or os.path.exists(os.path.join(raw_reads_dir, f'{sample}_R2.fastq.gz'))
        
        if r1_exists and r2_exists:
            SAMPLES.append(sample)
        else:
            INCOMPLETE.append(sample)
    
    # Print valid samples for processing
    print(' '.join(SAMPLES))
    
    # Print incomplete samples to stderr for reporting
    if INCOMPLETE:
        print(f'WARNING: Found {len(INCOMPLETE)} samples with missing paired files:', file=sys.stderr)
        for sample in INCOMPLETE:
            r1_file = f'{sample}_R1_001.fastq.gz' if os.path.exists(os.path.join(raw_reads_dir, f'{sample}_R1_001.fastq.gz')) else f'{sample}_R1.fastq.gz'
            r2_file = f'{sample}_R2_001.fastq.gz' if os.path.exists(os.path.join(raw_reads_dir, f'{sample}_R2_001.fastq.gz')) else f'{sample}_R2.fastq.gz'
            r1_status = 'FOUND' if os.path.exists(os.path.join(raw_reads_dir, r1_file)) else 'MISSING'
            r2_status = 'FOUND' if os.path.exists(os.path.join(raw_reads_dir, r2_file)) else 'MISSING'
            print(f'  - {sample}: R1 [{r1_status}], R2 [{r2_status}]', file=sys.stderr)
else:
    print('')
"
}

# Get samples
echo "=== Detecting samples ==="
ALL_SAMPLES=$(detect_samples)
SAMPLES_TO_USE=$ALL_SAMPLES

# Check if any samples were found
if [ -z "$SAMPLES_TO_USE" ]; then
  echo "ERROR: No valid paired samples found. Check your data directory."
  exit 1
else
  # Convert string to array and count properly
  SAMPLES_ARRAY=($SAMPLES_TO_USE)
  echo "Using ${#SAMPLES_ARRAY[@]} valid paired samples: $SAMPLES_TO_USE"
fi

# Create a temporary config file with samples and resolved paths
TEMP_CONFIG="config/temp_config.yaml"

# Generate a resolved config with explicit paths (no variables)
echo "Creating resolved config..."
python -c "
import yaml
import os

# Load the original config
with open('config/config.yaml', 'r') as f:
    config = yaml.safe_load(f)

# Resolve path variables
repo_root = '.'
data_dir = os.path.join(repo_root, 'data')
results_dir = os.path.join(repo_root, 'results')
logs_dir = os.path.join(repo_root, 'logs')
temp_dir = os.path.join(repo_root, 'temp')

# Update all paths to use resolved values (without './' prefix)
config['repo_root'] = repo_root
config['data_dir'] = data_dir
config['results_dir'] = results_dir
config['logs_dir'] = logs_dir
config['temp_dir'] = temp_dir

# Update nested paths with clean paths (no './' prefix)
config['transcriptome_assembly']['raw_reads_dir'] = os.path.normpath(os.path.join(data_dir, 'raw_reads'))
config['transcriptome_assembly']['output_dir'] = os.path.normpath(os.path.join(results_dir, 'transcriptome_assembly'))
config['transcriptome_assembly']['log_dir'] = os.path.normpath(os.path.join(logs_dir, 'transcriptome_assembly'))
config['transcriptome_assembly']['temp_dir'] = os.path.normpath(os.path.join(temp_dir, 'transcriptome_assembly'))

config['maker_annotator']['genome_dir'] = os.path.normpath(os.path.join(data_dir, 'genome'))
config['maker_annotator']['bam_file'] = os.path.normpath(os.path.join(data_dir, 'transcriptome.bam'))
config['maker_annotator']['output_dir'] = os.path.normpath(os.path.join(results_dir, 'maker_annotator'))
config['maker_annotator']['log_dir'] = os.path.normpath(os.path.join(logs_dir, 'maker_annotator'))
config['maker_annotator']['temp_dir'] = os.path.normpath(os.path.join(temp_dir, 'maker_annotator'))
config['maker_annotator']['sif_path'] = os.path.normpath(os.path.join(repo_root, 'pipelines/maker_annotator/braker.sif'))

config['repeat_annotator']['genome_dir'] = os.path.normpath(os.path.join(data_dir, 'genome'))
config['repeat_annotator']['repeat_lib'] = os.path.normpath(os.path.join(data_dir, 'repeats/mosquito_repeat_lib.fasta'))
config['repeat_annotator']['output_dir'] = os.path.normpath(os.path.join(results_dir, 'repeat_annotator'))
config['repeat_annotator']['log_dir'] = os.path.normpath(os.path.join(logs_dir, 'repeat_annotator'))
config['repeat_annotator']['temp_dir'] = os.path.normpath(os.path.join(temp_dir, 'repeat_annotator'))

# Add all samples
samples = '$SAMPLES_TO_USE'.split()
config['transcriptome_assembly']['samples'] = samples

# Write the resolved config
with open('$TEMP_CONFIG', 'w') as f:
    yaml.dump(config, f, default_flow_style=False)

print('Config created with explicit paths')
"

# Choose execution mode
echo "=== Select execution mode ==="
echo "1) Local dry run (for testing)"
echo "2) HPC execution (via SLURM)"
read -p "Choose mode (1/2): " mode

# Set targets
TARGETS="results/transcriptome_assembly/06_busco/bbnorm/run_diptera_odb10/short_summary.txt results/transcriptome_assembly/06_busco/trinity/run_diptera_odb10/short_summary.txt"

# Execute based on selected mode
if [[ "$mode" == "1" ]]; then
  echo "=== Running local dry run ==="
  # Direct command line arguments for local dry run
  snakemake \
    --configfile $TEMP_CONFIG \
    --cores 4 \
    --use-conda \
    --latency-wait 60 \
    --keep-going \
    --printshellcmds \
    --scheduler greedy \
    --dryrun \
    $TARGETS
    
elif [[ "$mode" == "2" ]]; then
  echo "=== Submitting to HPC via SLURM ==="
  # Direct command line arguments for SLURM execution
  snakemake \
    --configfile $TEMP_CONFIG \
    --executor slurm \
    --jobs 15 \
    --use-conda \
    --latency-wait 60 \
    --scheduler greedy \
    --default-resources partition=day-long-cpu time=24:00:00 mem=64G cpus=16 \
    --slurm-no-account \
    --slurm-logdir logs/ \
    $TARGETS
else
  echo "Invalid selection. Exiting."
  exit 1
fi 