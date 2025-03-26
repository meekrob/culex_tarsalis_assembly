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
    # Simple cat merge with compression
    cat ${cleaned_reads_r1} > merged_R1.fastq.gz
    """
} 