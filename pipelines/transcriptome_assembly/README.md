# Transcriptome Assembly Pipeline

## Goal
Build a high-quality de novo mosquito transcriptome to improve the reference.

## Pipeline Steps
1. **Quality Trimming**: `fastp` for read trimming
2. **Merging**: Combines reads from multiple samples
3. **Pair Checking**: Validates paired-end consistency
4. **Normalization**: Two methods (BBNorm and Trinity) run in parallel
5. **Assembly**: `rnaSPAdes` for de novo assembly
6. **Quality Assessment**: `BUSCO` evaluation

## Usage
```bash
# Run with default paths (data/raw_reads/, results/transcriptome_assembly/)
sbatch pipelines/transcriptome_assembly/bin/main.sh

# Specify custom paths
sbatch pipelines/transcriptome_assembly/bin/main.sh /path/to/reads /path/to/results

# Debug mode (skips steps with existing outputs)
sbatch pipelines/transcriptome_assembly/bin/main.sh -d
```

## Directory Structure
- **Input**: `data/raw_reads/` (FASTQ files named with R1 and R2)
- **Output**: `results/transcriptome_assembly/`
  - `01_trimmed/`: Trimmed reads
  - `02_merged/`: Merged reads
  - `03_pairs/`: Paired reads
  - `04_normalized/`: Normalized reads (bbnorm/ and trinity/)
  - `05_assembly/`: Assembled transcripts
  - `06_busco/`: BUSCO results
- **Logs**: `logs/transcriptome_assembly/`
- **Temp**: `temp/transcriptome_assembly/`

## Notes
- Runs two normalization methods for comparison
- Check `logs/transcriptome_assembly/pipeline_summary.csv` for run statistics

### Pipeline Visualization
![Pipeline visualization](config/simple_mosquito_denovo.png)

### Steps to run pipeline: 

1. Clone and navigate into the repo
```bash
git clone git@github.com:meekrob/mosquito_denovo.git
cd mosquito_denovo
```

2. Ensure conda environments are available
```bash
# Check available environments
conda env list

# Required environments:
# - cellSquito (for most steps)
# - trinity (for Trinity normalization)
```

3. Run the pipeline
```bash
# Basic usage (creates pipeline-specific directories in your current location)
sbatch pipelines/transcriptome_assembly/bin/main.sh

# Specify custom data and results directories
sbatch pipelines/transcriptome_assembly/bin/main.sh /path/to/data /path/to/results
```

Each pipeline will create its own containerized directories:
- `transcriptome_assembly_data/` - Pipeline input data
- `transcriptome_assembly_results/` - Pipeline output results
- `transcriptome_assembly_logs/` - Pipeline logs
- `transcriptome_assembly_temp/` - Pipeline temporary files

**Important**: This pipeline runs two parallel normalization methods (BBNorm and Trinity) to compare their effectiveness, followed by separate assembly and quality assessment for each method.

### Comparison of Normalization Methods
The pipeline now performs two different read normalization approaches in parallel:
1. **BBNorm normalization**: Uses BBMap's BBNorm tool
2. **Trinity normalization**: Uses Trinity's in-silico normalization script

The results of both approaches are separately assembled and assessed, allowing you to compare which method produces better transcriptome assemblies.

### Tools:
- **fastp**: Trim and perform quality control
- **BBNorm**: Digital normalization (Method 1)
- **Trinity**: Digital normalization (Method 2)
- **rnaSPAdes**: De novo transcriptome assembly
- **BUSCO**: Transcriptome assembly quality assessment

