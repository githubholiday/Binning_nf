#!/usr/bin/env nextflow
nextflow.enable.dsl=2

// ============================================================
// 模块 main.nf —— 通用注释示例（学习用，非真实步骤）
//
// 本文件让模块能【独立运行】。流程层面（pipeline/main.nf）串联时无需本文件，
// 而是 include 本模块的 process.nf 并自行接线。
//
// 输入文件约定（重要，与 process.nf 一致）：
//   - 所有输入文件都是【显式文件参数】：从 CSV 表读路径 → file(...) 转成文件对象传入；
//   - 模块内【不做】输入路径拼接；多路输入按共同键（sample_id）join 即可。
// ============================================================
include { My_Process } from './process.nf'

// 模块默认参数（单独运行时用，命令行可覆盖）
//   - 样本表 samples.csv：标准三列显式路径 sample_id,r1,r2
//   - 其它输入映射表（如 contigs）：sample_id,<具体文件路径>
params {
    samples = 'samples.csv'
    outdir  = 'results'
}

workflow {
    // reads 端：标准样本表 → 文件对象
    samples_ch = Channel.fromPath(params.samples)
        .splitCsv(header: true)
        .map { row -> tuple(row.sample_id, file(row.r1), file(row.r2)) }

    // 若有多路输入，按共同键 join 后再送入 process：
    //   other_ch.join(samples_ch, by: [0, 1])
    //     .map { id, proj, in_fa, r1, r2 -> tuple(id, proj, in_fa, r1, r2) }

    out = My_Process(samples_ch)
    out.result.view()
}

// 单独运行：
//   nextflow run modules/<模块>/main.nf -profile sge
// 流程级运行（串联）：
//   nextflow run main.nf -profile sge
