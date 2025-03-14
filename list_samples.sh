#!/bin/bash

# Add this code to temporarily report the detected samples
cat << 'EOF' > debug_samples.py
import os
import yaml

with open("config/config.yaml", "r") as f:
    config = yaml.safe_load(f)

SAMPLES = []
raw_reads_dir = "data/raw_reads"

# More comprehensive pattern detection
for f in os.listdir(raw_reads_dir):
    if "R1" in f and f.endswith(".fastq.gz"):
        if "_R1_001.fastq.gz" in f:
            sample = f.replace("_R1_001.fastq.gz", "")
        elif "_R1.fastq.gz" in f:
            sample = f.replace("_R1.fastq.gz", "")
        else:
            continue
        SAMPLES.append(sample)

print(f"Found {len(SAMPLES)} samples: {SAMPLES}")
EOF

python debug_samples.py 