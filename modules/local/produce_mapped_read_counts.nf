// Ported from pipeline_ref/Snakefile rule `produce_mapped_read_counts`
// (lines 592-621). Aggregates every sample's flagstat output into one
// summary TSV - the Snakefile's expand()-over-all-samples input is just
// channel cardinality here (.collect() in the calling workflow).
process PRODUCE_MAPPED_READ_COUNTS {

    input:
    path flagstats

    output:
    path "1_mapped_summary.tsv", emit: tsv

    script:
    """
    for file in *.flagstat; do
        line=\$(grep 'mapped (' \$file | head -n 1)
        count=\$(echo \$line | awk '{print \$1}')
        filename=\$(basename \$file .flagstat)-flagstat.txt
        echo -e "\$filename\\t\$count" >> 1_mapped_summary.tsv
    done
    """
}
