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
    def read1 = reads[0]
    def read2 = reads[1]
    """
    echo "=== STARTING SEQKIT_QC PROCESS v2 ==="
    echo "Working directory: \$(pwd)"
    echo "Files available:"
    ls -la
    echo "Sample ID: ${sample_id}"
    echo "Read1: ${read1}"
    echo "Read2: ${read2}"
    
    # Create output directory
    mkdir -p temp
    
    # Process R1
    echo "Processing R1..."
    seqkit sana -j ${task.cpus} -o temp/r1_sana.fastq.gz "${read1}"
    
    # Process R2
    echo "Processing R2..."
    seqkit sana -j ${task.cpus} -o temp/r2_sana.fastq.gz "${read2}"
    
    # Pair reads
    echo "Pairing reads..."
    mkdir -p temp/paired
    seqkit pair -j ${task.cpus} -1 temp/r1_sana.fastq.gz -2 temp/r2_sana.fastq.gz -O temp/paired -u
    
    # Rename outputs
    echo "Generating final outputs..."
    mv temp/paired/r1_sana.fastq.gz "${sample_id}_clean_R1.fastq.gz"
    mv temp/paired/r2_sana.fastq.gz "${sample_id}_clean_R2.fastq.gz"
    
    # Cleanup
    rm -rf temp
    echo "=== SEQKIT_QC PROCESS COMPLETED ==="
    """
} 