# mosquito_denovo

### Goal: Build a higher quality transcriptome pipeline to improve the reference transcriptome


### Pipeline Visualization
   ![Pipeline visualization](mosquito_denovo_pipeline.png)


### Project Structure:
mosquito_denovo/
├── input/
│   ├── raw_reads/                   # Raw untrimmed paired-end reads
│   ├── trimmed_reads/               # Trimmed reads after fastp
│   └── draft_transcriptome/         # Original "best" transcriptome
│
├── results/                         # Output files from each step of the pipeline
│   ├── 01_merge_trim/               # Results from merging and trimming steps
│   ├── 02_assembly/                 # De novo assembly results
│   ├── 03_busco/                    # BUSCO analysis outputs
│   └── 04_visualize/                # Visualization outputs and comparison graphs
│
├── scripts/
│   ├── mosquito_denovo.sh           # Main script that handles job submissions
│   ├── 01_merge_trim.sh             # Trim each read file and merge outputs
│   ├── 02_assembly.sh               # Assemble merged and trimmed RNA reads with draft transcriptome
│   ├── 03_busco.sh                  # Perform BUSCO analysis on original & new transcriptome
│   └── 04_visualize.sh              # Visualize BUSCO outputs and comparisons
│
├── logs/                            # Directory to store .out & .err logs
│
└── configs/
    ├── mosquito.yml                 # Conda environment specification
    └── data.tsv                     # Metadata table


### Tools:
- **zcat**: Merge paired-end RNA reads
- **fastp**: Trim and perform quality control
- **rnaSPAdes**: De novo transcriptome assembly
- **BUSCO**: Transcriptome assembly quality assessment
- **R**: Visualization and comparison graphs
