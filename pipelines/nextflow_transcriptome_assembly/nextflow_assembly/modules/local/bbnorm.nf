process BBNORM {
    publishDir "${params.outdir}/normalization", mode: params.publish_dir_mode
    cpus 64
    memory '240 GB'
    time '156h'

    input:
    tuple path(left), path(right)

    output:
    tuple path("normalized_R1.fastq.gz"), path("normalized_R2.fastq.gz"), emit: normalized_reads
    path "histogram_{in,out}.txt", emit: histograms
    path "peaks.txt", emit: peaks

    script:
    """
    bbnorm.sh \\
        in1=${left} \\
        in2=${right} \\
        out1=normalized_R1.fastq.gz \\
        out2=normalized_R2.fastq.gz \\
        target=${params.target_depth} \\
        mindepth=5 \\
        maxdepth=100 \\
        passes=2 \\
        k=${params.kmer_size} \\
        prefilter=t \\
        prefiltersize=0.35 \\
        prehashes=2 \\
        prefilterbits=2 \\
        buildpasses=1 \\
        bits=16 \\
        hashes=3 \\
        threads=${task.cpus} \\
        interleaved=false \\
        ecc=f \\
        tossbadreads=f \\
        fixspikes=t \\
        deterministic=t \\
        hist=histogram_in.txt \\
        histout=histogram_out.txt \\
        peaks=peaks.txt \\
        zerobin=t \\
        pzc=t \\
        histlen=10000 \\
        minq=6 \\
        minprob=0.5 \\
        -Xmx${task.memory.toGiga()-10}g \\
        -eoom \\
        -da \\
        overwrite=t \\
        tmpdir="/nfs/home/jlamb/Projects/temp"
    """
} 