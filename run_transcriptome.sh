#!/bin/bash

snakemake \
  --executor slurm \
  --jobs 15 \
  --use-conda \
  --latency-wait 60 \
  --default-resources partition=day-long-cpu time=24:00:00 mem=64G cpus=16 \
  --slurm-logdir logs/ \
  results/transcriptome_assembly/06_busco/bbnorm/run_diptera_odb10/short_summary.txt \
  results/transcriptome_assembly/06_busco/trinity/run_diptera_odb10/short_summary.txt 