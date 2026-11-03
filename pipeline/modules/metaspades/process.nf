#!/usr/bin/env nextflow
nextflow.enable.dsl=2

// metaSPAdes 宏基因组组装模块
// 对应原 metaspade.mk 的 MetaSpades target：
//   $(METASPADES) -1 $(R1) -2 $(R2) -o $(outdir) -t $(threads)
// 差异说明：
//   1) 容器化后二进制内置，默认 metaSPAdes.py；本地非容器运行可用 params.metaspades_bin 指定实际路径
//   2) 最终 contigs 重命名为 final.contig.fa（原 contigs.fasta），便于下游统一引用
//   3) 追加 --memory，使 metaSPAdes 实际内存与调度器申请量一致（否则自动探测节点内存易被 OOM kill）

// 注意：metaspades_bin 的【权威值】在 modules/metaspades/config 的 params 块里（模块软件与环境配置）。
// 本文件【不能】定义 params 块——纯 process 定义文件没有 workflow，新版 Nextflow 会报
// "Params block cannot be defined without an entry workflow"（Nextflow 26.10 实测）。
// 软件参数默认值一律放模块 config；优先级：脚本 params < nextflow.config < -params-file < 命令行。

process MetaSpades {
    tag "MetaSpades on ${sample_id}"

    input:
    tuple val(sample_id), path(r1), path(r2)

    output:
    // 完整组装目录（名=sample_id）：scaffolds.fasta / assembly_graph*.gfa / before_rr.fasta /
    // spades.log / final.contig.fa（重命名后的最终 contigs）等，供下游分箱、QUAST 使用
    // 样本维度靠【目录名(sample_id)】区分，发布到 outdir/metaspades/<sample_id>/
    // （publishDir 路径本身不含 sample_id，避免 outdir/<模块>/<sample>/<sample>_xxx 双层嵌套）
    tuple val(sample_id), path("${sample_id}", type: 'dir'), emit: assembly

    script:
    def memArg = task.memory ? "--memory ${task.memory.toGiga()}" : ''
    """
    ${params.metaspades_bin} -1 ${r1} -2 ${r2} -o ${sample_id} -t ${task.cpus} ${memArg}
    cp ${sample_id}/contigs.fasta ${sample_id}/final.contig.fa
    """
}
