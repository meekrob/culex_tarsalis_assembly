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
    # Simple cat merge with compression
    cat ${cleaned_reads_r2} > merged_R2.fastq.gz
    """
} 