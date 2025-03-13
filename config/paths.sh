#!/bin/bash

# Centralized path configuration for mosquito_denovo pipelines
# Source this file in pipeline scripts to maintain consistent paths

# If REPO_ROOT isn't already set, try to detect it
if [[ -z "$REPO_ROOT" ]]; then
    # Get repository root regardless of where the script is called from
    SCRIPT_PATH="${BASH_SOURCE[0]}"
    if [[ -z "$SCRIPT_PATH" ]]; then
        # Fallback if BASH_SOURCE isn't available
        echo "ERROR: Could not determine script path. Please set REPO_ROOT manually."
        return 1
    fi
    SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
    export REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
fi

echo "Using repository root: $REPO_ROOT"

# Standard directories
export DATA_DIR="${REPO_ROOT}/data"
export RESULTS_DIR="${REPO_ROOT}/results"
export LOGS_DIR="${REPO_ROOT}/logs"
export TEMP_DIR="${REPO_ROOT}/temp"

# Create these directories if they don't exist
mkdir -p "$DATA_DIR" "$RESULTS_DIR" "$LOGS_DIR" "$TEMP_DIR"

# Data subdirectories
export RAW_READS_DIR="${DATA_DIR}/raw_reads"
export GENOME_DIR="${DATA_DIR}/genome"
export REPEATS_DIR="${DATA_DIR}/repeats"

# Create data subdirectories if they don't exist
mkdir -p "$RAW_READS_DIR" "$GENOME_DIR" "$REPEATS_DIR"

# Shared data files
export TRANSCRIPTOME_BAM="${DATA_DIR}/transcriptome.bam"
export REPEAT_LIBRARY="${REPEATS_DIR}/mosquito_repeat_lib.fasta"

# Function to create pipeline directories
setup_pipeline_dirs() {
    local pipeline_name=$1
    
    if [[ -z "$pipeline_name" ]]; then
        echo "ERROR: No pipeline name provided to setup_pipeline_dirs"
        return 1
    fi
    
    mkdir -p "${RESULTS_DIR}/${pipeline_name}"
    mkdir -p "${LOGS_DIR}/${pipeline_name}"
    mkdir -p "${TEMP_DIR}/${pipeline_name}"
    
    echo "Created directories for ${pipeline_name}"
    return 0
} 