#!/usr/bin/env nextflow
nextflow.enable.dsl=2

// 对应原 metaspade.mk：$(METASPADES) -1 $(R1) -2 $(R2) -o $(outdir) -t $(threads)
// 差异：1) 二进制路径取自 params.metaspades_bin（非容器）；2) contigs 重命名为 final.contig.fa 供下游统一引用；
//      3) 追加 --memory，使实际内存与调度器申请量一致（否则自动探测节点内存易被 OOM kill）
// ⚠️ 本文件不写 params 块（纯 process 文件无 workflow，会报 "Params block cannot be defined without an entry workflow"）

process MetaSpades {
    tag "MetaSpades on ${sample_id}"

    input:
    tuple val(sample_id), path(r1), path(r2)

    output:
    // 整个组装目录，目录名 = sample_id → 落点 outdir/metaspades/<sample_id>/
    // （含 scaffolds.fasta / assembly_graph*.gfa / spades.log / final.contig.fa）
    tuple val(sample_id), path("${sample_id}", type: 'dir'), emit: assembly

    script:
    def memArg = task.memory ? "--memory ${task.memory.toGiga()}" : ''
    """
    ${params.metaspades_bin} -1 ${r1} -2 ${r2} -o ${sample_id} -t ${task.cpus} ${memArg}
    cp ${sample_id}/contigs.fasta ${sample_id}/final.contig.fa
    """
}
