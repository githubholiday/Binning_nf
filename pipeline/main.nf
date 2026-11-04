#!/usr/bin/env nextflow
nextflow.enable.dsl=2

// ⚠️ 勿用 `python scripts/pipeline2main.py pipeline.yaml -o main.nf` 覆盖本文件：
//    align 需双输入（contigs + reads）join，生成器只支持单输入线性链，覆盖会丢失接线。
//    （资源配置仍可用 yaml2config.py 从 pipeline.yaml 重新生成。）

include { MetaSpades } from './modules/metaspades/process.nf'
include { MetaSpades_Align } from './modules/metaspades_align/process.nf'

params {
    samples = 'samples.csv'
    // 占位；权威值在项目 config（-c 指定）。缺声明则从非 project/ 目录启动报 outdir not declared
    outdir = 'results'
}

// 两份独立 channel（各消费一次）：本版本 .into 在 workflow 块内无法声明变量
// ⚠️ def 必须放 workflow 块外，否则报 "Unexpected input: '('"
def sampleCh() {
    Channel.fromPath(params.samples)
        .splitCsv(header: true)
        .map { row -> tuple(row.sample_id, file(row.r1), file(row.r2)) }
}

workflow {
    samples_for_assemble = sampleCh()
    samples_for_align    = sampleCh()

    assemble_out = MetaSpades(samples_for_assemble)

    // MetaSpades 只 emit assembly（组装目录）；从这里派生 final.contig.fa，
    // 与 reads 按 sample_id join 成 (id, contigs, r1, r2) 送入 align
    contig_ch = assemble_out
        .map { id, dir -> tuple(id, file("${dir}/final.contig.fa")) }

    align_in = contig_ch
        .join(samples_for_align, by: [0])
        .map { id, contigs, r1, r2 -> tuple(id, contigs, r1, r2) }

    align_out = MetaSpades_Align(align_in)
}
