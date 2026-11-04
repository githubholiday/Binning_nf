#!/usr/bin/env nextflow
nextflow.enable.dsl=2

include { MetaSpades } from './process.nf'

// 单独运行入口（流程内由 pipeline/main.nf 直接 include process.nf）
// samples.csv 三列：sample_id,r1,r2；双端组装，r1/r2 必须都给
params {
    samples = 'samples.csv'
    outdir  = 'results'   // 占位，避免单独运行时 --outdir 触发严格参数检查
}

workflow {
    samples_ch = Channel.fromPath(params.samples)
        .splitCsv(header: true)
        .map { row ->
            tuple(row.sample_id, file(row.r1), file(row.r2))
        }

    metaspades_out = MetaSpades(samples_ch)
    assembly_ch = metaspades_out.assembly
    // 下游直接用 final.contig.fa，落点 outdir/metaspades/<sample_id>/final.contig.fa
    contig_ch = assembly_ch.map { id, dir -> tuple(id, file("${dir}/final.contig.fa")) }
    contig_ch.view()
    assembly_ch.view()
}
