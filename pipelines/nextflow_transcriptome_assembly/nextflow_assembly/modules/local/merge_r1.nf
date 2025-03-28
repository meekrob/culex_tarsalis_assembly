process MERGE_R1 {
    publishDir "${params.outdir}/merging", mode: params.publish_dir_mode
    cpus 2
    memory '8 GB'
    time '12h'

    input:
    path cleaned_reads_r1

    output:
    path "merged_R1.fastq.gz", emit: merged_r1

    script:
    """
    # Create temporary file for merging
    touch temp_R1.fastq.gz
    
    # Merge files with error checking
    for file in ${cleaned_reads_r1}; do
        if [ -f "\$file" ]; then
            cat "\$file" >> temp_R1.fastq.gz
        else
            echo "Error: File \$file not found" >&2
            exit 1
        fi
    done
    
    # Move to final output
    mv temp_R1.fastq.gz merged_R1.fastq.gz
    """
} 