// Run-level compilation of the per-sample essentiality tables into gene x sample matrices:
// insertion counts, read counts and binary essentiality (1 = essential).
// Runs `captnseq-toolkit aggregate` (https://github.com/simonjeanneau/captnseq-toolkit).
process GENE_MATRICES {

    conda "bioconda::captnseq-toolkit=0.2.0"
    container "quay.io/biocontainers/captnseq-toolkit:0.2.0--pyhdfd78af_0"

    input:
    path all_csv
    path essen_csv

    output:
    path "4_gene_insertion_counts.tsv", emit: insertion_counts
    path "5_gene_read_counts.tsv", emit: read_counts
    path "6_gene_essentiality.tsv", emit: essentiality
    tuple val("${task.process}"), val('captnseq-toolkit'), eval('captnseq-toolkit --version | sed "s/.* //"'), emit: versions_captnseq_toolkit, topic: versions

    script:
    """
    captnseq-toolkit aggregate \\
        --input-dir . \\
        --output-ic 4_gene_insertion_counts.tsv \\
        --output-rc 5_gene_read_counts.tsv \\
        --output-bt 6_gene_essentiality.tsv
    """
}
