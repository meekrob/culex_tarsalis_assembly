process BUSCO {
    publishDir "${params.outdir}/busco", mode: params.publish_dir_mode
    cpus 8
    memory '32 GB'
    time '24h'

    input:
    path assembly

    output:
    path "${assembly.baseName}", emit: busco_results

    script:
    """
    busco \\
        -i ${assembly}/transcripts.fasta \\
        -o ${assembly.baseName} \\
        -l eukaryota_odb10 \\
        -m transcriptome \\
        -c ${task.cpus} \\
        --out_path .
    """
} 