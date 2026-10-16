/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    IMPORT MODULES / SUBWORKFLOWS / FUNCTIONS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
include { FASTQC                 } from '../modules/nf-core/fastqc/main'
include { MULTIQC                } from '../modules/nf-core/multiqc/main'
include { CUTADAPT                } from '../modules/local/cutadapt'
include { FASTP                   } from '../modules/local/fastp'
include { BWA_INDEX                } from '../modules/local/bwa_index'
include { BWA_MEM                  } from '../modules/local/bwa_mem'
include { SAMTOOLS_SORT             } from '../modules/local/samtools_sort'
include { MARK_DUPLICATES           } from '../modules/local/mark_duplicates'
include { FLAGSTAT                  } from '../modules/local/flagstat'
include { BAM2SAM                   } from '../modules/local/bam2sam'
include { SAM2SITES                 } from '../modules/local/sam2sites'
include { INTERSECT                 } from '../modules/local/intersect'
include { SITES2GENES               } from '../modules/local/sites2genes'
include { STATISTI_CALL             } from '../modules/local/statisti_call'
include { GREP_OTHER_CHROMOSOMES    } from '../modules/local/grep_other_chromosomes'
include { PRODUCE_MAPPED_READ_COUNTS } from '../modules/local/produce_mapped_read_counts'
include { PRODUCE_INSERTION_COUNTS   } from '../modules/local/produce_insertion_counts'
include { PRODUCE_CHR_COUNTS         } from '../modules/local/produce_chr_counts'
include { paramsSummaryMap       } from 'plugin/nf-schema'
include { paramsSummaryMultiqc   } from '../subworkflows/nf-core/utils_nfcore_pipeline'
include { softwareVersionsToYAML } from '../subworkflows/nf-core/utils_nfcore_pipeline'
include { methodsDescriptionText } from '../subworkflows/local/utils_nfcore_captnseq_pipeline'

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    RUN MAIN WORKFLOW
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

workflow CAPTNSEQ {

    take:
    ch_samplesheet // channel: [ meta, [ fastq_1, fastq_2 ] ] - from --input
    multiqc_config
    multiqc_logo
    multiqc_methods_description
    outdir

    main:

    def ch_versions = channel.empty()
    def ch_multiqc_files = channel.empty()

    //
    // MODULE: Run FastQC
    //
    FASTQC(ch_samplesheet)
    ch_multiqc_files = ch_multiqc_files.mix(FASTQC.out.zip.map{ _meta, file -> file })

    //
    // Reshape samplesheet into (meta, r1, r2) and fail fast on missing/undersized
    // FASTQs - ports the pre-flight check from the original hand-rolled main.nf.
    // This pipeline is paired-end only (BWA read-group / cutadapt / fastp paired
    // flags all assume it), so single-end samplesheet rows are rejected here too.
    //
    def ch_reads = ch_samplesheet.map { meta, reads ->
        if (meta.single_end || reads.size() < 2) {
            error("Sample '${meta.id}' has no fastq_2 - captnseq requires paired-end reads for every sample.")
        }
        reads.each { fq ->
            // fq is a Nextflow/NIO Path (from nf-schema), not a String like the
            // original YAML-parsed values - use its own .size(), not `as File`.
            if (fq.size() < params.min_fastq_size_bytes as long) {
                error(
                    "FASTQ for '${meta.id}' is suspiciously small (${fq.size()} bytes, " +
                    "below params.min_fastq_size_bytes=${params.min_fastq_size_bytes}): ${fq}\n" +
                    "Fix or remove this sample from the samplesheet, or raise " +
                    "min_fastq_size_bytes if this is a false positive on a genuinely " +
                    "low-coverage sample."
                )
            }
        }
        [ meta, reads[0], reads[1] ]
    }

    //
    // Trimming, alignment, dedup, insertion-site calling
    //
    CUTADAPT(ch_reads)
    FASTP(CUTADAPT.out.reads)

    BWA_INDEX(file(params.genome_fasta, checkIfExists: true))
    BWA_MEM(FASTP.out.reads, BWA_INDEX.out.index)
    SAMTOOLS_SORT(BWA_MEM.out.sam)

    MARK_DUPLICATES(SAMTOOLS_SORT.out.bam)
    FLAGSTAT(MARK_DUPLICATES.out.markeddup)

    BAM2SAM(MARK_DUPLICATES.out.dedup)
    SAM2SITES(BAM2SAM.out.dedup)

    //
    // Gene-level insertion stats and essentiality calling
    //
    def ch_genome_features = file(params.genome_features, checkIfExists: true)
    INTERSECT(SAM2SITES.out.unstranded_unnormalized, ch_genome_features)
    SITES2GENES(INTERSECT.out.bed, ch_genome_features)
    STATISTI_CALL(SITES2GENES.out.tsv)

    //
    // Reporting - per-sample chr counts, then whole-run summaries
    //
    GREP_OTHER_CHROMOSOMES(MARK_DUPLICATES.out.dedup)

    PRODUCE_MAPPED_READ_COUNTS(FLAGSTAT.out.flagstat.collect())
    PRODUCE_INSERTION_COUNTS(SAM2SITES.out.unstranded_unnormalized.map { meta, bg -> bg }.collect())
    PRODUCE_CHR_COUNTS(GREP_OTHER_CHROMOSOMES.out.chr_count.map { meta, tsv -> tsv }.collect())

    ch_multiqc_files = ch_multiqc_files.mix(CUTADAPT.out.log)
    ch_multiqc_files = ch_multiqc_files.mix(FASTP.out.json)
    ch_multiqc_files = ch_multiqc_files.mix(FLAGSTAT.out.flagstat)

    //
    // Collate and save software versions
    //
    def topic_versions = channel.topic("versions")
        .distinct()
        .branch { entry ->
            versions_file: entry instanceof Path
            versions_tuple: true
        }

    def topic_versions_string = topic_versions.versions_tuple
        .map { process, tool, version ->
            [ process[process.lastIndexOf(':')+1..-1], "  ${tool}: ${version}" ]
        }
        .groupTuple(by:0)
        .map { process, tool_versions ->
            tool_versions.unique().sort()
            "${process}:\n${tool_versions.join('\n')}"
        }

    def ch_collated_versions = softwareVersionsToYAML(ch_versions.mix(topic_versions.versions_file))
        .mix(topic_versions_string)
        .collectFile(
            storeDir: "${outdir}/pipeline_info",
            name: 'nf_core_'  +  'captnseq_software_'  + 'mqc_'  + 'versions.yml',
            sort: true,
            newLine: true
        )

    //
    // MODULE: MultiQC
    //
    ch_multiqc_files = ch_multiqc_files.mix(ch_collated_versions)
    def ch_summary_params = paramsSummaryMap(workflow, parameters_schema: "nextflow_schema.json")
    def ch_workflow_summary = channel.value(paramsSummaryMultiqc(ch_summary_params))
    ch_multiqc_files = ch_multiqc_files.mix(ch_workflow_summary.collectFile(name: 'workflow_summary_mqc.yaml'))
    def ch_multiqc_custom_methods_description = multiqc_methods_description
        ? file(multiqc_methods_description, checkIfExists: true)
        : file("${projectDir}/assets/methods_description_template.yml", checkIfExists: true)
    def ch_methods_description = channel.value(methodsDescriptionText(ch_multiqc_custom_methods_description))
    ch_multiqc_files = ch_multiqc_files.mix(ch_methods_description.collectFile(name: 'methods_description_mqc.yaml', sort: true))
    MULTIQC(
        ch_multiqc_files.flatten().collect().map { files ->
            [
                [id: 'captnseq'],
                files,
                multiqc_config
                    ? file(multiqc_config, checkIfExists: true)
                    : file("${projectDir}/assets/multiqc_config.yml", checkIfExists: true),
                multiqc_logo ? file(multiqc_logo, checkIfExists: true) : [],
                [],
                [],
            ]
        }
    )
    emit:multiqc_report = MULTIQC.out.report.map { _meta, report -> [report] }.toList() // channel: /path/to/multiqc_report.html
    versions       = ch_versions                 // channel: [ path(versions.yml) ]
}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    THE END
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
