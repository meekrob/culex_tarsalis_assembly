#!/bin/bash

# Centralized path configuration for mosquito_denovo pipelines
# Source this file in pipeline scripts to maintain consistent paths

# Get repository root regardless of where the script is called from
export REPO_ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"

# Standard directories
export DATA_DIR="${REPO_ROOT}/data"
export RESULTS_DIR="${REPO_ROOT}/results"
export LOGS_DIR="${REPO_ROOT}/logs"
export TEMP_DIR="${REPO_ROOT}/temp"

# Data subdirectories
export RAW_READS_DIR="${DATA_DIR}/raw_reads"
export GENOME_DIR="${DATA_DIR}/genome"
export REPEATS_DIR="${DATA_DIR}/repeats"

# Shared data files
export TRANSCRIPTOME_BAM="${DATA_DIR}/transcriptome.bam"
export REPEAT_LIBRARY="${REPEATS_DIR}/mosquito_repeat_lib.fasta"

# Function to create pipeline directories
setup_pipeline_dirs() {
    local pipeline_name=$1
    
    mkdir -p "${RESULTS_DIR}/${pipeline_name}"
    mkdir -p "${LOGS_DIR}/${pipeline_name}"
    mkdir -p "${TEMP_DIR}/${pipeline_name}"
    
    echo "Created directories for ${pipeline_name}"
} 