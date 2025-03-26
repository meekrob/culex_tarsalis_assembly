# Transcriptome Assembly Pipeline

## Denovo mosquito transcriptome assembly pipeline

### Goal: Build a higher quality transcriptome pipeline to improve the reference transcriptome

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

