// Essentiality calling: classifies genes as essential / ambiguous / non-essential.
// Runs `captnseq-toolkit essentiality` (https://github.com/simonjeanneau/captnseq-toolkit),
// a Python port of the TRADIS essentiality script.
process STATISTI_CALL {
    tag "${meta.id}"

    conda "bioconda::captnseq-toolkit=0.2.0"
    container "quay.io/biocontainers/captnseq-toolkit:0.2.0--pyhdfd78af_0"

    input:
    tuple val(meta), path(s2g)

    output:
    tuple val(meta), path("${meta.id}-genes_insertions.essen.csv"),    emit: essen
    tuple val(meta), path("${meta.id}-genes_insertions.ambig.csv"),    emit: ambig
    tuple val(meta), path("${meta.id}-genes_insertions.all.csv"),      emit: all
    tuple val(meta), path("${meta.id}-genes_insertions.nonessen.csv"), emit: nonessen
    tuple val(meta), path("${meta.id}-genes_insertions_QC_and_changepoint_plots.pdf"), emit: qc_pdf, optional: true
    tuple val("${task.process}"), val('captnseq-toolkit'), eval('captnseq-toolkit --version | sed "s/.* //"'), emit: versions_captnseq_toolkit, topic: versions

    script:
    """
    captnseq-toolkit essentiality \\
        --input ${s2g} \\
        --output-all ${meta.id}-genes_insertions.all.csv \\
        --output-essen ${meta.id}-genes_insertions.essen.csv \\
        --output-ambig ${meta.id}-genes_insertions.ambig.csv \\
        --output-nonessen ${meta.id}-genes_insertions.nonessen.csv
    """
}
