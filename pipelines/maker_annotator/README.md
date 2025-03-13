# Genome Annotation Pipeline (BRAKER)

## Goal
Annotate a genome using RNA-seq evidence with BRAKER.

## Pipeline Steps
1. **BRAKER**: Gene prediction with RNA-seq BAM file

## Usage
```bash
# Run with default paths (data/genome/, results/maker_annotator/)
sbatch pipelines/maker_annotator/bin/main.sh

# Specify custom paths
sbatch pipelines/maker_annotator/bin/main.sh /path/to/genome /path/to/results

# Debug mode
sbatch pipelines/maker_annotator/bin/main.sh -d
```

## Directory Structure
- **Input**:
  - `data/genome/` (FASTA file: *.fa or *.fasta)
  - `data/transcriptome.bam` (RNA-seq BAM file)
- **Output**: `results/maker_annotator/braker/` (e.g., augustus.hints.gtf)
- **Logs**: `logs/maker_annotator/`
- **Temp**: `temp/maker_annotator/`

## Setup
- Place braker.sif in pipelines/maker_annotator/
- Ensure data/transcriptome.bam exists or modify main.sh to accept a BAM path argument

# 
create conda env, install singularity if not already installed, and build the container


```
mkdir tmp #make a tmp dir 

export SINGULARITY_TMPDIR=/path/to/tmp # set singularity tmp dir

singularity build braker3.sif docker://teambraker/braker3:latest # build the singularity container
```
# should now have a .sif file and we can remove the tmp dir



# nead to download diptera protein database from ncbi using id 7141
check here for api documentation: https://www.ezlab.org/orthodb_v12_userguide.html#downloads

