configfile: "config/config.yaml"

# Dynamically detect samples for transcriptome assembly
import os
SAMPLES = []
if not config["transcriptome_assembly"]["samples"]:
    raw_reads_dir = config["transcriptome_assembly"]["raw_reads_dir"]
    for f in os.listdir(raw_reads_dir):
        if f.endswith(("R1.fastq.gz", "_1.fastq.gz")):
            sample = f.replace("_R1.fastq.gz", "").replace("_1.fastq.gz", "")
            SAMPLES.append(sample)
config["transcriptome_assembly"]["samples"] = SAMPLES

# Define pipeline targets
rule all:
    input:
        # Transcriptome Assembly targets
        expand("{results_dir}/transcriptome_assembly/06_busco/{norm}/run_diptera_odb10/short_summary.txt",
               results_dir=config["results_dir"], norm=["bbnorm", "trinity"]),
        # Maker Annotator target
        f"{config['maker_annotator']['output_dir']}/braker/augustus.hints.gff3",
        # Repeat Annotator target
        f"{config['repeat_annotator']['output_dir']}/{os.path.basename(config['repeat_annotator']['genome_dir'])}.masked"

# Include subworkflows
include: "pipelines/transcriptome_assembly/Snakefile"
include: "pipelines/maker_annotator/Snakefile"
include: "pipelines/repeat_annotator/Snakefile"