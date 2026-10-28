// Assigns insertion sites to genes and counts them per gene.
// Runs `captnseq-toolkit sites2genes` (https://github.com/simonjeanneau/captnseq-toolkit).
process SITES2GENES {
    tag "${meta.id}"

    conda "bioconda::captnseq-toolkit=0.2.0"
    container "quay.io/biocontainers/captnseq-toolkit:0.2.0--pyhdfd78af_0"

    input:
    tuple val(meta), path(sample)
    path features

    output:
    tuple val(meta), path("${meta.id}-genes_insertions.tsv"), emit: tsv
    tuple val("${task.process}"), val('captnseq-toolkit'), eval('captnseq-toolkit --version | sed "s/.* //"'), emit: versions_captnseq_toolkit, topic: versions

    script:
    """
    captnseq-toolkit sites2genes \\
        --features ${features} \\
        --sample ${sample} \\
        --length-pc-start ${params.sites2genes_params.length_pc_start} \\
        --length-pc-stop ${params.sites2genes_params.length_pc_stop} \\
        --output ${meta.id}-genes_insertions.tsv
    """
}
