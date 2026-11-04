#!/usr/bin/env nextflow
nextflow.enable.dsl=2

include { My_Process } from './process.nf'

// 模块模板：单独运行入口（流程内由 pipeline/main.nf 直接 include process.nf 并自行接线）
// 样本表三列 sample_id,r1,r2；其它输入表用 sample_id,<文件路径>
params {
    samples = 'samples.csv'
    outdir  = 'results'
}

workflow {
    samples_ch = Channel.fromPath(params.samples)
        .splitCsv(header: true)
        .map { row -> tuple(row.sample_id, file(row.r1), file(row.r2)) }

    // 多路输入：other_ch.join(samples_ch, by: [0]).map { id, in_fa, r1, r2 -> tuple(id, in_fa, r1, r2) }

    out = My_Process(samples_ch)
    out.result.view()
}

// 单独运行：nextflow run modules/<模块>/main.nf -profile sge
