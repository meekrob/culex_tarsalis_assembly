process RNASPADES {
    publishDir "${params.outdir}/assembly/rnaspades", mode: params.publish_dir_mode
    cpus 64
    memory '250 GB'
    time '168h'

    input:
    tuple path(left), path(right)

    output:
    path "rnaspades", emit: assembly

    script:
    """
    rnaspades.py \\
        --rna \\
        -1 ${left} \\
        -2 ${right} \\
        -o rnaspades \\
        -t ${task.cpus} \\
        -m ${task.memory.toGiga()}
    """
} 