// Main, deduplicated-reads branch of insertion-site calling - feeds
// intersect/sites2genes/statisti_call (essentiality) and produce_insertion_counts.
// Runs `captnseq-toolkit sam2sites` (https://github.com/simonjeanneau/captnseq-toolkit).
process SAM2SITES {
    tag "${meta.id}"

    conda "bioconda::captnseq-toolkit=0.1.2"
    container "quay.io/biocontainers/captnseq-toolkit:0.1.2--pyhdfd78af_0"

    input:
    tuple val(meta), path(sam)

    output:
    tuple val(meta), path("${meta.id}.bed"), emit: bed
    tuple val(meta), path("${meta.id}-stranded.bg"), emit: stranded
    tuple val(meta), path("${meta.id}-unstranded.bg"), emit: unstranded
    tuple val(meta), path("${meta.id}-stranded_unnormalized.bg"), emit: stranded_unnormalized
    tuple val(meta), path("${meta.id}-unstranded_unnormalized.bg"), emit: unstranded_unnormalized
    tuple val("${task.process}"), val('captnseq-toolkit'), eval('captnseq-toolkit --version | sed "s/.* //"'), emit: versions_captnseq_toolkit, topic: versions

    script:
    """
    captnseq-toolkit sam2sites \\
        --sam ${sam} \\
        --norm-value ${params.sam2sites_params.norm_value} \\
        --read-len-threshold ${params.sam2sites_params.read_len_threshold} \\
        --score-threshold ${params.sam2sites_params.score_threshold} \\
        --pos-offset-fwd ${params.sam2sites_params.pos_offset_fwd} \\
        --pos-offset-rev ${params.sam2sites_params.pos_offset_rev} \\
        --bed-output ${meta.id}.bed \\
        --normalized-output ${meta.id}-stranded.bg \\
        --unstranded-output ${meta.id}-unstranded.bg \\
        --unnormalized-output ${meta.id}-stranded_unnormalized.bg \\
        --unstranded-unnormalized-output ${meta.id}-unstranded_unnormalized.bg
    """
}
