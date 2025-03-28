process MERGE_R2 {
    publishDir "${params.outdir}/merging", mode: params.publish_dir_mode
    cpus 2
    memory '8 GB'
    time '12h'

    input:
    path cleaned_reads_r2

    output:
    path "merged_R2.fastq.gz", emit: merged_r2

    script:
    """
    # Create temporary file for merging
    touch temp_R2.fastq.gz
    
    # Merge files with error checking
    for file in ${cleaned_reads_r2}; do
        if [ -f "\$file" ]; then
            cat "\$file" >> temp_R2.fastq.gz
        else
            echo "Error: File \$file not found" >&2
            exit 1
        fi
    done
    
    # Move to final output
    mv temp_R2.fastq.gz merged_R2.fastq.gz
    """
} 