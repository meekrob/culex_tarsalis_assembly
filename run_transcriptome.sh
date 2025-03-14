#!/bin/bash

# Print the config file for inspection
echo "=== Current config.yaml ==="
cat config/config.yaml

# Create a temporary configuration with fixed paths
TEMP_CONFIG="config/config_fixed.yaml"

# Fix the raw_reads_dir in the config
cat > $TEMP_CONFIG << EOF
slurm:
  default:
    partition: "day-long-cpu"
  transcriptome:
    trimming:
      time: "24:00:00"
      cpus: 16
      mem: "64G"
    merge:
      time: "24:00:00"
      cpus: 16
      mem: "64G"
    pair_check:
      time: "24:00:00"
      cpus: 16
      mem: "64G"
    bbnorm:
      time: "24:00:00"
      cpus: 16
      mem: "64G"
    trinity_norm:
      time: "24:00:00"
      cpus: 16
      mem: "64G"
    assembly:
      partition: "day-long-cpu"
      time: "48:00:00"
      cpus: 32
      mem: "128G"
    busco:
      time: "24:00:00"
      cpus: 16
      mem: "64G"
  maker:
    braker:
      time: "72:00:00"
      cpus: 32
      mem: "128G"
  repeat:
    repeatmasker:
      time: "24:00:00"
      cpus: 16
      mem: "64G"

transcriptome_assembly:
  raw_reads_dir: "data/raw_reads"
  samples: []
  conda_env: "cellSquito"
  trinity_env: "trinity"
  temp_dir: "/tmp"

maker_annotator:
  species_name: "culex_tarsalis"
  conda_env: "braker"

repeat_annotator:
  genome_dir: "data/genome"
  repeat_lib: "data/repeats/mosquito_repeat_lib.fasta"
  conda_env: "repeatmasker"
EOF

echo "=== Fixed config created at $TEMP_CONFIG ==="

# Now let's print the samples we detect
echo "=== Detecting samples ==="
SAMPLES=$(python -c "
import os
SAMPLES = []
raw_reads_dir = 'data/raw_reads'
if os.path.exists(raw_reads_dir):
    for f in os.listdir(raw_reads_dir):
        if 'R1' in f and f.endswith('.fastq.gz'):
            if '_R1_001.fastq.gz' in f:
                sample = f.replace('_R1_001.fastq.gz', '')
            elif '_R1.fastq.gz' in f:
                sample = f.replace('_R1.fastq.gz', '')
            else:
                continue
            SAMPLES.append(sample)
    print(' '.join(SAMPLES[:5]))  # Just use 5 samples for testing
else:
    print('Error: Directory {raw_reads_dir} does not exist!')
")

echo "Using samples: $SAMPLES"

# Create a list of trimmed outputs based on detected samples
TRIM_TARGETS=""
for sample in $SAMPLES; do
  TRIM_TARGETS="$TRIM_TARGETS results/transcriptome_assembly/01_trimmed/${sample}_R1_trimmed.fastq.gz"
done

echo "=== PHASE 1: Running trimming for samples ==="
# Run the trimming phase first
snakemake \
  --configfile $TEMP_CONFIG \
  --executor slurm \
  --jobs 15 \
  --use-conda \
  --latency-wait 60 \
  --default-resources partition=day-long-cpu time=24:00:00 mem=64G cpus=16 \
  --slurm-logdir logs/ \
  --slurm-no-account \
  $TRIM_TARGETS

echo "=== PHASE 2: Running the rest of the workflow ==="
# Then run the rest of the workflow
snakemake \
  --configfile $TEMP_CONFIG \
  --executor slurm \
  --jobs 15 \
  --use-conda \
  --latency-wait 60 \
  --default-resources partition=day-long-cpu time=24:00:00 mem=64G cpus=16 \
  --slurm-logdir logs/ \
  --slurm-no-account \
  results/transcriptome_assembly/06_busco/bbnorm/run_diptera_odb10/short_summary.txt \
  results/transcriptome_assembly/06_busco/trinity/run_diptera_odb10/short_summary.txt 