# nf-denovo-transcriptome

A Nextflow pipeline for de novo eukaryotic transcriptome assembly. 

## Overview

This pipeline processes paired-end RNA-seq data through multiple steps to generate a high-quality transcriptome assembly:

1. **Trimming**: Removes adapters and low-quality sequences using fastp
2. **Repair**: Ensures paired reads are synchronized with BBMap's repair.sh
3. **Merging**: Combines reads from multiple samples into a single dataset
4. **Normalization**: Reduces redundancy via digital normalization with BBNorm
5. **Assembly**: Assembles transcripts using either rnaSPAdes or Trinity
6. **Quality Assessment**: Evaluates completeness using BUSCO

## Requirements

- Nextflow (21.10.0+)
- Conda or Mamba for dependency management
- Input file listing samples in tab-separated format

## Installation

No installation required other than Nextflow and Conda. The pipeline will automatically create the necessary environment with all dependencies.

```bash
# If you don't have mamba installed (recommended for faster conda installations)
conda install -c conda-forge mamba

# Clone the repository
git clone https://github.com/jakeelamb/nf-denovo-transcriptome.git
cd nf-denovo-transcriptome
```

## Usage

```bash
# Run with rnaSPAdes
nextflow run main.nf -profile slurm --assembler rnaspades

# Run with Trinity
nextflow run main.nf -profile slurm --assembler trinity

# With custom parameters
nextflow run main.nf --input my_samples.txt --outdir /path/to/results --kmer_size 27
```

## Input Format

Create a tab-separated file (default: `samples.txt`) with columns:
```
sample_id    /path/to/R1.fastq.gz    /path/to/R2.fastq.gz
```

## Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| `--input` | Sample sheet with sample_id, R1, R2 paths | `samples.txt` |
| `--outdir` | Output directory for results | `./results` |
| `--kmer_size` | k-mer size for normalization | `25` |
| `--target_depth` | Normalization target depth | `100` |
| `--assembler` | Assembly method (rnaspades or trinity) | `rnaspades` |
