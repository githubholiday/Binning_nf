#!/usr/bin/env nextflow
nextflow.enable.dsl=2

include { MetaSpades_Align } from './process.nf'

// 单独运行入口。两种 contigs 来源：
//   ① 本文件 param：contig_fa 单文件，所有样本共用（nextflow run modules/metaspades_align/main.nf）
//   ② 流程内（pipeline/main.nf）：接收上游逐样本通道，不使用 params.contig_fa
//      （params 是启动期定值，无法接通道，故流程层用 join 接线）
params {
    samples   = 'samples.csv'     // 与 metaspades 同一份表：sample_id,r1,r2
    contig_fa = 'contigs.fasta'
    outdir    = 'results'
}

workflow {
    contigs = file(params.contig_fa)

    samples_ch = Channel.fromPath(params.samples)
        .splitCsv(header: true)
        .map { row -> tuple(row.sample_id, contigs, file(row.r1), file(row.r2)) }

    align_out = MetaSpades_Align(samples_ch)
    align_out.bam.view()
    align_out.bai.view()
}
