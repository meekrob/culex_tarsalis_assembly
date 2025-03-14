#!/bin/bash

# Print the config file for inspection
echo "=== Current config.yaml ==="
cat config/config.yaml

# Now let's get all samples
echo "=== Detecting samples ==="
ALL_SAMPLES=$(python -c "
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
    print(' '.join(SAMPLES))
else:
    print('')
")

# Get a subset for testing
TEST_SAMPLES=$(echo $ALL_SAMPLES | tr ' ' '\n' | head -5 | tr '\n' ' ')
echo "Using test samples: $TEST_SAMPLES"

# Create a temporary configuration with fixed paths AND specific samples
TEMP_CONFIG="config/config_fixed.yaml"

# Create JSON-formatted samples array
SAMPLES_JSON="["
for sample in $TEST_SAMPLES; do
  SAMPLES_JSON+="\"$sample\", "
done
SAMPLES_JSON=${SAMPLES_JSON%, }  # Remove trailing comma
SAMPLES_JSON+="]"

# Fix the config with specific samples
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
  samples: $SAMPLES_JSON
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

# First do a dry run to see what will happen
echo "=== Dry run to check workflow ==="
snakemake \
  --configfile $TEMP_CONFIG \
  --executor slurm \
  --scheduler greedy \
  --jobs 15 \
  --use-conda \
  --latency-wait 60 \
  --default-resources partition=day-long-cpu time=24:00:00 mem=64G cpus=16 \
  --slurm-logdir logs/ \
  --slurm-no-account \
  --dryrun \
  results/transcriptome_assembly/06_busco/bbnorm/run_diptera_odb10/short_summary.txt \
  results/transcriptome_assembly/06_busco/trinity/run_diptera_odb10/short_summary.txt

# Run the workflow if the dry run looks good
echo "=== Running workflow with fixed config ==="
snakemake \
  --configfile $TEMP_CONFIG \
  --executor slurm \
  --scheduler greedy \
  --jobs 15 \
  --use-conda \
  --latency-wait 60 \
  --default-resources partition=day-long-cpu time=24:00:00 mem=64G cpus=16 \
  --slurm-logdir logs/ \
  --slurm-no-account \
  results/transcriptome_assembly/06_busco/bbnorm/run_diptera_odb10/short_summary.txt \
  results/transcriptome_assembly/06_busco/trinity/run_diptera_odb10/short_summary.txt 