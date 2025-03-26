process SEQKIT_QC {
    tag "$sample_id"
    publishDir "${params.outdir}/seqkit_qc", mode: params.publish_dir_mode
    cpus 4
    memory '16 GB'
    time '24h'

    input:
    tuple val(sample_id), path(reads)

    output:
    tuple val(sample_id), path("${sample_id}_clean_R{1,2}.fastq.gz"), emit: cleaned_reads

    script:
    """
    # Run seqkit sana on R1
    seqkit sana -j ${task.cpus} ${reads[0]} -o ${sample_id}_sana_R1.fastq.gz

    # Run seqkit sana on R2
    seqkit sana -j ${task.cpus} ${reads[1]} -o ${sample_id}_sana_R2.fastq.gz

    # Create temporary output directory for paired reads
    mkdir -p paired_output

    # Run seqkit pair on sana outputs - using -O for output directory
    seqkit pair -j ${task.cpus} -1 ${sample_id}_sana_R1.fastq.gz -2 ${sample_id}_sana_R2.fastq.gz \
        -O paired_output -u

    # Rename the outputs to our desired filenames
    mv paired_output/${sample_id}_sana_R1.fastq.gz ${sample_id}_clean_R1.fastq.gz
    mv paired_output/${sample_id}_sana_R2.fastq.gz ${sample_id}_clean_R2.fastq.gz
    """
} 