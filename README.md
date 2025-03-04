# mosquito_denovo






Project Structure:
.
└── mosquito_denovo/
    ├── input/
    │   ├── raw_reads/
    │   ├── trimmed_reads/
    │   └── draft_transcriptome.fasta
    ├── results/
    │   ├── 01_merge_trimm/
    │   │   ├── .out
    │   │   └── .err
    │   ├── 02_assembly/
    │   │   ├── .out
    │   │   └── .err
    │   ├── 03_busco/
    │   │   ├── .out
    │   │   └── .error
    │   └── 04_visualize/
    │       ├── .out
    │       └── .err
    └── scripts/
        ├── mosquito_denovo.sh
        ├── 01_merge_trimm.sh
        ├── 02_assembly.sh
        ├── 03_busco.sh
        └── 04_visualize.sh

Tools: 
zcat: merge paired end rna reads
fastp: trim and quality quality control
mRNAspades: assembly 
Busco: Transcriptome assembly quality
Visualization: R to make pretty graph




Goal: Build a higher quality transcriptome pipeline to keep improve the reference transcriptome