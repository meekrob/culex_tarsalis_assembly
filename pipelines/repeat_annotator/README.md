# Repeat Annotation Pipeline

## Goal
Mask repetitive elements in a genome using RepeatMasker.

## Pipeline Steps
1. **RepeatMasker**: Masks repeats with a custom library

## Setup
1. **Create Repeat Library**:
```bash
mkdir -p data/repeats/dfam
cd data/repeats/dfam
# Download dfam files (e.g., wget https://dfam.org/releases/current/families/FamDB/dfam39_full.*.h5.gz)
gunzip dfam39*.gz
git clone git@github.com:Dfam-consortium/FamDB.git
./FamDB/famdb.py -i . families -f fasta_name -ad 'Diptera' > ../mosquito_repeat_lib.fasta
```

2. **Conda Environment**:
```bash
conda env create -f config/environment.yml -n repeatmasker
```

## Usage
```bash
# Run with default paths (data/genome/, data/repeats/mosquito_repeat_lib.fasta)
sbatch pipelines/repeat_annotator/bin/main.sh

# Specify custom paths
sbatch pipelines/repeat_annotator/bin/main.sh /path/to/genome /path/to/results
```

## Directory Structure
- **Input**:
  - `data/genome/` (FASTA file)
  - `data/repeats/mosquito_repeat_lib.fasta`
- **Output**: `results/repeat_annotator/` (masked genome)
- **Logs**: `logs/repeat_annotator/`
- **Temp**: `temp/repeat_annotator/`