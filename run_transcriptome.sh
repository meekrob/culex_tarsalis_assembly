#!/bin/bash

snakemake \
  --cluster "sbatch -p {resources.partition} -t {resources.time} -c {resources.cpus} --mem={resources.mem} -o logs/{rule}/{wildcards}.out -e logs/{rule}/{wildcards}.err" \
  --jobs 15 \
  --use-conda \
  --latency-wait 60 \
  results/transcriptome_assembly/06_busco/bbnorm/run_diptera_odb10/short_summary.txt \
  results/transcriptome_assembly/06_busco/trinity/run_diptera_odb10/short_summary.txt 