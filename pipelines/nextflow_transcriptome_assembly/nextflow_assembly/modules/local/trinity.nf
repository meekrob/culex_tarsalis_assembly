process TRINITY {
    publishDir "${params.outdir}/assembly/trinity", mode: params.publish_dir_mode
    cpus 64
    memory '250 GB'
    time '168h'

    input:
    tuple path(left), path(right)

    output:
    path "trinity", emit: assembly

    script:
    """
    Trinity \\
        --seqType fq \\
        --left ${left} \\
        --right ${right} \\
        --no_normalize \\
        --CPU ${task.cpus} \\
        --max_memory ${task.memory.toGiga()}G \\
        --output trinity
    """
} 