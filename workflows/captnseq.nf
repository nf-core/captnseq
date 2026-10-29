/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    IMPORT MODULES / SUBWORKFLOWS / FUNCTIONS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
include { FASTQC                 } from '../modules/nf-core/fastqc/main'
include { MULTIQC                } from '../modules/nf-core/multiqc/main'
include { CUTADAPT               } from '../modules/nf-core/cutadapt/main'
include { FASTP                  } from '../modules/nf-core/fastp/main'
include { BWA_INDEX              } from '../modules/nf-core/bwa/index/main'
include { BWA_MEM                } from '../modules/nf-core/bwa/mem/main'
include { SAMTOOLS_VIEW as SAMTOOLS_VIEW_MAPQ    } from '../modules/nf-core/samtools/view/main'
include { SAMTOOLS_VIEW as SAMTOOLS_VIEW_DEDUP   } from '../modules/nf-core/samtools/view/main'
include { SAMTOOLS_VIEW as SAMTOOLS_VIEW_BAM2SAM } from '../modules/nf-core/samtools/view/main'
include { SAMTOOLS_SORT as SAMTOOLS_SORT_NAME    } from '../modules/nf-core/samtools/sort/main'
include { SAMTOOLS_SORT as SAMTOOLS_SORT_COORD   } from '../modules/nf-core/samtools/sort/main'
include { SAMTOOLS_FIXMATE       } from '../modules/nf-core/samtools/fixmate/main'
include { SAMTOOLS_MARKDUP       } from '../modules/nf-core/samtools/markdup/main'
include { SAMTOOLS_INDEX         } from '../modules/nf-core/samtools/index/main'
include { SAMTOOLS_FLAGSTAT      } from '../modules/nf-core/samtools/flagstat/main'
include { SAMTOOLS_IDXSTATS      } from '../modules/nf-core/samtools/idxstats/main'
include { BEDTOOLS_INTERSECT     } from '../modules/nf-core/bedtools/intersect/main'
include { SAM2SITES                  } from '../modules/local/sam2sites'
include { SITES2GENES                } from '../modules/local/sites2genes'
include { STATISTI_CALL              } from '../modules/local/statisti_call'
include { GENE_MATRICES              } from '../modules/local/gene_matrices'
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
    // Check the samplesheet reads and fail fast on missing/undersized
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
        [ meta, reads ]
    }

    //
    // Trimming
    //
    CUTADAPT(ch_reads)
    FASTP(CUTADAPT.out.reads.map { meta, reads -> [ meta, reads, [] ] }, false, false, false)

    //
    // Alignment: bwa mem -> keep reads above the mapping-quality threshold ->
    // name-sort -> fixmate -> coordinate-sort
    //
    def ch_genome_fasta = channel.value([ [ id: 'genome' ], file(params.genome_fasta, checkIfExists: true) ])
    BWA_INDEX(ch_genome_fasta)
    BWA_MEM(FASTP.out.reads, BWA_INDEX.out.index, [ [:], [] ], false)

    SAMTOOLS_VIEW_MAPQ(BWA_MEM.out.sam.map { meta, sam -> [ meta, sam, [] ] }, [ [:], [], [] ], [ [:], [] ], [ [:], [] ], '')
    SAMTOOLS_SORT_NAME(SAMTOOLS_VIEW_MAPQ.out.bam, [ [:], [], [] ], '')
    SAMTOOLS_FIXMATE(SAMTOOLS_SORT_NAME.out.bam, [ [:], [], [] ])
    SAMTOOLS_SORT_COORD(SAMTOOLS_FIXMATE.out.bam, [ [:], [], [] ], '')

    //
    // Duplicate marking and removal
    //
    SAMTOOLS_MARKDUP(SAMTOOLS_SORT_COORD.out.bam, [ [:], [], [] ])
    SAMTOOLS_VIEW_DEDUP(SAMTOOLS_MARKDUP.out.bam.map { meta, bam -> [ meta, bam, [] ] }, [ [:], [], [] ], [ [:], [] ], [ [:], [] ], '')
    SAMTOOLS_FLAGSTAT(SAMTOOLS_MARKDUP.out.bam.map { meta, bam -> [ meta, bam, [] ] })

    // Refuse to continue with a sample that has too few mapped reads
    SAMTOOLS_FLAGSTAT.out.flagstat.subscribe { meta, flagstat ->
        def mapped = (flagstat.readLines().find { line -> line.contains(' mapped (') }?.tokenize(' ')?.first() ?: '0') as long
        if (mapped < (params.min_mapped_reads as long)) {
            error("map_reads: only ${mapped} mapped reads for ${meta.id} (minimum ${params.min_mapped_reads}) - refusing to treat this as a successful output")
        }
    }

    //
    // Insertion-site calling on the deduplicated reads
    //
    SAMTOOLS_VIEW_BAM2SAM(SAMTOOLS_VIEW_DEDUP.out.bam.map { meta, bam -> [ meta, bam, [] ] }, [ [:], [], [] ], [ [:], [] ], [ [:], [] ], '')
    SAM2SITES(SAMTOOLS_VIEW_BAM2SAM.out.sam)

    //
    // Gene-level insertion stats and essentiality calling
    //
    def ch_genome_features = file(params.genome_features, checkIfExists: true)
    BEDTOOLS_INTERSECT(SAM2SITES.out.unstranded_unnormalized.map { meta, bg -> [ meta, ch_genome_features, bg ] }, [ [:], [] ], 'bed')
    SITES2GENES(BEDTOOLS_INTERSECT.out.intersect, ch_genome_features)
    STATISTI_CALL(SITES2GENES.out.tsv)

    //
    // Gene x sample matrices (insertion count, read count, essentiality) over all samples
    //
    GENE_MATRICES(
        STATISTI_CALL.out.all.map { _meta, csv -> csv }.collect(),
        STATISTI_CALL.out.essen.map { _meta, csv -> csv }.collect(),
    )

    //
    // Reporting - per-sample chr counts, then whole-run summaries
    //
    SAMTOOLS_INDEX(SAMTOOLS_VIEW_DEDUP.out.bam)
    SAMTOOLS_IDXSTATS(SAMTOOLS_VIEW_DEDUP.out.bam.join(SAMTOOLS_INDEX.out.index))

    PRODUCE_MAPPED_READ_COUNTS(SAMTOOLS_FLAGSTAT.out.flagstat.map { _meta, flagstat -> flagstat }.collect())
    PRODUCE_INSERTION_COUNTS(SAM2SITES.out.unstranded_unnormalized.map { _meta, bg -> bg }.collect())
    PRODUCE_CHR_COUNTS(SAMTOOLS_IDXSTATS.out.idxstats.map { _meta, idxstats -> idxstats }.collect())

    ch_multiqc_files = ch_multiqc_files.mix(CUTADAPT.out.log.map { _meta, log -> log })
    ch_multiqc_files = ch_multiqc_files.mix(FASTP.out.json.map { _meta, json -> json })
    ch_multiqc_files = ch_multiqc_files.mix(SAMTOOLS_FLAGSTAT.out.flagstat.map { _meta, flagstat -> flagstat })

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
