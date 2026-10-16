// Ported from pipeline_ref/Snakefile rule `produce_chr_counts` (lines
// 643-673) - a Snakemake `run:` block (inline Python, no separate script
// file). Pivots every sample's per-contig read counts into one wide TSV.
process PRODUCE_CHR_COUNTS {

    input:
    path chrcounts

    output:
    path "3_chr_count.tsv", emit: tsv

    script:
    """
    #!/usr/bin/env python3
    import glob
    import os
    import pandas as pd

    all_dfs = []
    for file in sorted(glob.glob("*.idxstats")):
        sample = os.path.basename(file).replace('.idxstats', '')
        df = pd.read_csv(file, sep='\\t', header=None, names=['chr', 'chrom_size', 'mapped_count', 'unmapped_count'])
        df['sample_name'] = sample
        df = df.pivot(index='sample_name', columns='chr', values='mapped_count')
        all_dfs.append(df)
    summary = pd.concat(all_dfs)
    summary = summary.fillna(0).astype(int)
    summary.index.name = 'sample_name'
    summary.to_csv("3_chr_count.tsv", sep='\\t')
    """
}
