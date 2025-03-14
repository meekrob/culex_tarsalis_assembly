#!/bin/bash

# Create profiles directory if it doesn't exist
mkdir -p profiles/local
mkdir -p profiles/slurm

# Create local profile for testing/dry runs
cat > profiles/local/config.yaml << EOF
cores: 4
use-conda: true
latency-wait: 60
keep-going: true
printshellcmds: true
scheduler: greedy
EOF

# Create SLURM profile for HPC execution
cat > profiles/slurm/config.yaml << EOF
executor: slurm
jobs: 15
use-conda: true
latency-wait: 60
scheduler: greedy
default-resources:
  - partition=day-long-cpu
  - time=24:00:00
  - mem=64G
  - cpus=16
slurm-no-account: true
slurm-logdir: logs/
EOF

echo "Profiles created successfully!"
echo ""
echo "To test locally (dry run):"
echo "  snakemake --profile profiles/local --dryrun [targets]"
echo ""
echo "To run on the HPC:"
echo "  snakemake --profile profiles/slurm [targets]" 