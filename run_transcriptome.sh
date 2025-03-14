#!/bin/bash

# First, let's print the detected samples for debugging
echo "Detected samples:"
python -c "
import os, yaml
with open('config/config.yaml', 'r') as f:
    config = yaml.safe_load(f)
raw_reads_dir = config['transcriptome_assembly']['raw_reads_dir']
SAMPLES = []
for f in os.listdir(raw_reads_dir):
    if 'R1' in f and f.endswith('.fastq.gz'):
        if '_R1_001.fastq.gz' in f:
            sample = f.replace('_R1_001.fastq.gz', '')
        elif '_R1.fastq.gz' in f:
            sample = f.replace('_R1.fastq.gz', '')
        else:
            continue
        SAMPLES.append(sample)
print(f'Found {len(SAMPLES)} samples')
print(f'First 5 samples: {SAMPLES[:5]}')
"

# Now run the workflow with SLURM, without needing an account
snakemake \
  --executor slurm \
  --jobs 15 \
  --use-conda \
  --latency-wait 60 \
  --default-resources partition=day-long-cpu time=24:00:00 mem=64G cpus=16 \
  --slurm-logdir logs/ \
  --slurm-no-account \
  results/transcriptome_assembly/06_busco/bbnorm/run_diptera_odb10/short_summary.txt \
  results/transcriptome_assembly/06_busco/trinity/run_diptera_odb10/short_summary.txt 