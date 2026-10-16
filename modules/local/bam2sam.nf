// Ported from nfcore_HTTM/modules/bam2sam.nf (originally: pipeline/Snakefile rule
// `bam2sam`). Converts the deduplicated BAM to SAM - SAM2SITES reads a SAM, not a BAM.
process BAM2SAM {
    tag "${meta.id}"

    input:
    tuple val(meta), path(dedup)

    output:
    tuple val(meta), path("${meta.id}-dedup.sam"), emit: dedup

    script:
    """
    samtools view --threads ${task.cpus} -S ${dedup} -o ${meta.id}-dedup.sam
    """
}
