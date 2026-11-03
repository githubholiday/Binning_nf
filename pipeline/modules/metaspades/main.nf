#!/usr/bin/env nextflow
nextflow.enable.dsl=2

include { MetaSpades } from './process.nf'

// 模块默认参数（单独运行时用，命令行可覆盖）
// samples.csv 四列：sample_id,project,r1,r2（由 config.ini [Sample] 节转换而来）
// project 对应 config.ini [Sample] 第二列（项目号），透传用于下游分组（不再进入输出路径）。
// 本模块为双端组装（-1/-2），与原 metaspade.mk 一致；r1/r2 必须都给出。
params {
    samples = 'samples.csv'   // 样本表路径；命令行 --samples 可覆盖
    // outdir 的【权威值】在项目级 nextflow.config（params.outdir），命令行 --outdir 可覆盖。
    // 这里仅声明占位：单独跑模块时配置链里若完全没声明 outdir，
    // 新版 Nextflow 严格参数检查会报 "Parameter 'outdir' was specified ... but not declared"。
    // 优先级：脚本 params < nextflow.config < -params-file < 命令行，故项目配置照常覆盖此占位。
    outdir  = 'results'
}

workflow {
    samples_ch = Channel.fromPath(params.samples)
        .splitCsv(header: true)
        .map { row ->
            tuple(row.sample_id, row.project, file(row.r1), file(row.r2))
        }

    // 组装目录含 final.contig.fa（重命名后的最终 contigs）；输出落点 outdir/metaspades/<sample_id>/
    metaspades_out = MetaSpades(samples_ch)
    assembly_ch = metaspades_out.assembly
    // 从组装目录派生最终 contigs，供下游直接引用；落点 outdir/metaspades/<sample_id>/final.contig.fa
    contig_ch = assembly_ch.map { id, proj, dir -> tuple(id, proj, file("${dir}/final.contig.fa")) }
    contig_ch.view()
    assembly_ch.view()
}
