#!/usr/bin/env nextflow
nextflow.enable.dsl=2

include { MetaSpades_Align } from './process.nf'

// 本模块为下游步骤：需 (contigs + 双端 reads) 两路输入。
//   samples   = 样本表路径（CSV：sample_id,project,r1,r2）—— 与 metaspades 模块共用同一格式、同一份表
//   contig_fa = 组装 contigs 文件路径（单一 fa，供所有样本回帖）
//
// 【两种用法】
//   ① 独立运行（nextflow run modules/metaspades_align）：contigs 由本文件的 params.contig_fa 指定
//      （单文件，所有样本共用）；samples.csv 提供 r1/r2，与 metaspades 同格式。
//   ② 流程内运行（pipeline/main.nf）：contigs 不读 params，而是接收上游 MetaSpades 的【逐样本】输出通道
//      （每个样本回帖到自己的 final.contig.fa），reads 仍来自与 metaspades 同一份 samples.csv。
//      ⚠️ Nextflow 的 params 是启动期定值、不能接收通道，所以流程层用 channel 接线（assemble_out → join）
//         把上一步 contigs 喂给 process，而非写 params.contig_fa。模块 standalone 的 contig_fa 参数仅用于①。
// 输入均为显式文件参数，模块内不做路径拼接。
params {
    samples   = 'samples.csv'     // 样本表路径（CSV：sample_id,project,r1,r2）
    contig_fa = 'contigs.fasta'   // 组装 contigs 文件路径（仅独立运行①使用；流程内②由上游通道注入）
    outdir    = 'results'
}

workflow {
    contigs = file(params.contig_fa)

    samples_ch = Channel.fromPath(params.samples)
        .splitCsv(header: true)
        .map { row -> tuple(row.sample_id, row.project, contigs, file(row.r1), file(row.r2)) }

    align_out = MetaSpades_Align(samples_ch)
    align_out.bam.view()
    align_out.bai.view()
}
