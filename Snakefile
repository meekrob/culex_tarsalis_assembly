configfile: "config/config.yaml"

# Resolve path variables in config
import os
from string import Formatter

def resolve_path_templates(config_dict, root_vars=None):
    if root_vars is None:
        root_vars = {"repo_root": "."}
    
    resolved = {}
    for key, value in config_dict.items():
        if isinstance(value, dict):
            resolved[key] = resolve_path_templates(value, root_vars)
        elif isinstance(value, str):
            try:
                # Extract variable names from the string
                var_names = [fn for _, fn, _, _ in Formatter().parse(value) if fn is not None]
                # Resolve variables recursively
                if var_names:
                    template_vars = {**root_vars, **resolved}
                    for var_name in var_names:
                        if var_name in template_vars:
                            value = value.replace("{" + var_name + "}", template_vars[var_name])
            except Exception as e:
                pass
            resolved[key] = value
        else:
            resolved[key] = value
    return resolved

# Resolve all paths in the config
config = resolve_path_templates(config)

# Dynamically detect samples for transcriptome assembly
SAMPLES = []
if not config["transcriptome_assembly"]["samples"]:
    raw_reads_dir = config["transcriptome_assembly"]["raw_reads_dir"]
    if os.path.exists(raw_reads_dir):
        for f in os.listdir(raw_reads_dir):
            if "R1" in f and f.endswith(".fastq.gz"):
                if "_R1_001.fastq.gz" in f:
                    sample = f.replace("_R1_001.fastq.gz", "")
                elif "_R1.fastq.gz" in f:
                    sample = f.replace("_R1.fastq.gz", "")
                else:
                    continue
                SAMPLES.append(sample)
config["transcriptome_assembly"]["samples"] = SAMPLES

# Define pipeline targets
rule all:
    input:
        # Transcriptome Assembly targets
        expand("results/transcriptome_assembly/06_busco/{norm}/run_diptera_odb10/short_summary.txt",
               norm=["bbnorm", "trinity"]),
        # Maker Annotator target
        "results/maker_annotator/braker/augustus.hints.gff3",
        # Repeat Annotator target
        "results/repeat_annotator/genome.masked"

# Include subworkflows
include: "pipelines/transcriptome_assembly/Snakefile"
include: "pipelines/maker_annotator/Snakefile"
include: "pipelines/repeat_annotator/Snakefile"