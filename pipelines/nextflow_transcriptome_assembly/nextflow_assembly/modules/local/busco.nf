process BUSCO {
    publishDir "${params.outdir}/busco", mode: params.publish_dir_mode
    cpus 8
    memory '32 GB'
    time '2h'

    input:
    path assembly

    output:
    path "busco_output", emit: busco_results

    script:
    """
    # Debug: Print directory structure
    echo "Assembly directory contents:"
    ls -la ${assembly}
    
    # Safety check - ensure no previous busco_output exists
    rm -rf busco_output
    
    # Run BUSCO with a fixed output name
    busco \\
        -i ${assembly}/transcripts.fasta \\
        -o busco_output \\
        -l diptera_odb10 \\
        -m transcriptome \\
        -c ${task.cpus} \\
        --out_path .
    """
} 