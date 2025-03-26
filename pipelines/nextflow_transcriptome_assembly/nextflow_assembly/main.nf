#!/usr/bin/env nextflow
nextflow.enable.dsl=2

// Parameters are defined in nextflow.config
// This section should be removed from main.nf
// params {
//     input = "samples.txt"
//     outdir = "./results"
//     publish_dir_mode = "copy"
//     kmer_size = 25
//     target_depth = 100
//     assembler = "rnaspades"
//     skip_to_merge = false
//     repaired_reads_dir = "${params.outdir}/repair"
// }

// Include modules
include { FASTP } from './modules/local/fastp'
include { SEQKIT_QC } from './modules/local/seqkit_qc'
include { MERGE_R1 } from './modules/local/merge_r1'
include { MERGE_R2 } from './modules/local/merge_r2'
include { BBNORM } from './modules/local/bbnorm'
include { RNASPADES } from './modules/local/rnaspades'
include { TRINITY } from './modules/local/trinity'
include { BUSCO } from './modules/local/busco'

// Create log file for missing files
def logMissingFile(file_path) {
    def logFile = file("${params.outdir}/missing_files.log")
    if(!logFile.parent.exists()) {
        logFile.parent.mkdirs()
    }
    logFile.append("Missing file: ${file_path}\n")
    log.warn "Missing file: ${file_path} - skipping this sample"
}

// Input channel from samples.txt
Channel
    .fromPath(params.input, checkIfExists: true)
    .splitText()
    .map { line ->
        if (line.trim().startsWith('#')) return  // Skip comment lines
        def fields = line.trim().split(/\s+/)
        if (fields.size() >= 3) {
            def sample_id = fields[0]
            def r1_path = fields[1]
            def r2_path = fields[2]
            
            // Check if files exist without causing pipeline failure
            def r1 = file(r1_path)
            def r2 = file(r2_path)
            
            if (!r1.exists()) {
                logMissingFile(r1_path)
                return null
            }
            
            if (!r2.exists()) {
                logMissingFile(r2_path)
                return null
            }
            
            return [sample_id, [r1, r2]]
        }
        return null
    }
    .filter { it != null }  // Filter out skipped lines
    .set { read_pairs }

// Workflow
workflow {
    // Skip to merge if specified
    if (!params.skip_to_merge) {
        read_pairs.count().subscribe { count ->
            log.info "Processing ${count} samples"
        }
        
        // Trimming
        FASTP(read_pairs)
        
        // Clean and ensure proper pairing
        SEQKIT_QC(FASTP.out.trimmed_reads)
        
        // Extract and collect all R1 files
        SEQKIT_QC.out.cleaned_reads
            .map { sample_id, reads -> reads[0] }  // Get R1 files
            .collect()
            .set { all_r1_files }
            
        // Extract and collect all R2 files
        SEQKIT_QC.out.cleaned_reads
            .map { sample_id, reads -> reads[1] }  // Get R2 files
            .collect()
            .set { all_r2_files }
        
        // Merge R1 and R2 files in parallel
        MERGE_R1(all_r1_files)
        MERGE_R2(all_r2_files)
        
        // Set the merged reads for normalization
        merged_reads_ch = tuple(MERGE_R1.out.merged_r1, MERGE_R2.out.merged_r2)
    }
    else {
        // If skipping to merged files
        Channel
            .fromPath([
                "${params.outdir}/merging/merged_R1.fastq.gz", 
                "${params.outdir}/merging/merged_R2.fastq.gz"
            ])
            .collect()
            .set { merged_reads_ch }
            
        log.info "Skipping trimming and merging. Using existing files in ${params.outdir}/merging"
    }
    
    // Normalize merged reads
    BBNORM(merged_reads_ch)

    // Assembly (conditional based on params.assembler)
    if (params.assembler == "rnaspades") {
        RNASPADES(BBNORM.out.normalized_reads)
        assembly_ch = RNASPADES.out.assembly
    } else if (params.assembler == "trinity") {
        TRINITY(BBNORM.out.normalized_reads)
        assembly_ch = TRINITY.out.assembly
    } else {
        error "Invalid assembler specified: ${params.assembler}. Use 'rnaspades' or 'trinity'."
    }

    // Quality assessment with BUSCO
    BUSCO(assembly_ch)
} 