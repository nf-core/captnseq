# nf-core/captnseq: Changelog

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/)
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## v1.0.0dev - [unreleased<!-- TODO nf-core: replace with date on release -->]

Initial release of nf-core/captnseq, created with the [nf-core](https://nf-co.re/) template.

### `Added`

- Insertion-site calling, gene assignment and essentiality calling now run [captnseq-toolkit](https://github.com/simonjeanneau/captnseq-toolkit) (Bioconda), replacing the `bin/` scripts.
- `GENE_MATRICES` step (`captnseq-toolkit aggregate`): compiles the per-sample essentiality tables into run-level gene x sample tables of insertion counts, read counts and essentiality calls (`4_gene_insertion_counts.tsv`, `5_gene_read_counts.tsv`, `6_gene_essentiality.tsv`).

### `Fixed`

### `Dependencies`

| Tool             | Previous version | Current version |
| ---------------- | ---------------- | --------------- |
| captnseq-toolkit |                  | 0.2.0           |

### `Deprecated`
