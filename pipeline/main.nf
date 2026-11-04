#!/usr/bin/env nextflow
nextflow.enable.dsl=2

// ⚠️ 本文件在 pipeline2main.py 自动生成基础上【手写扩展】了 align 步骤：
//    align 需要同时消费 metaSPAdes 的 contigs 输出与原始 reads（双输入 join，按 sample_id），
//    pipeline2main.py 仅支持单输入线性链，无法表达此 join，故本段为手写。
//    ▶ 请勿再用 `python scripts/pipeline2main.py pipeline.yaml -o main.nf` 覆盖本文件，否则 align 接线会丢失。
//      （若需改流程，请直接编辑本文件；pipeline.generated.config 仍可正常用 yaml2config.py 重新生成。）

include { MetaSpades } from './modules/metaspades/process.nf'
include { MetaSpades_Align } from './modules/metaspades_align/process.nf'

params {
    samples = 'samples.csv'
}

// 样本通道工厂：DSL2 中一个 channel 只能被消费一次，
// 为避免 .into fork 在本版本 workflow 块内报错（无法声明变量），
// 这里用【顶层】函数构建两份独立 channel（CSV 解析极轻量，无副作用）。
// ⚠️ def 函数必须定义在 workflow 块【外部】（脚本顶层）：
//    写进 workflow 块会报 "Unexpected input: '('"
def sampleCh() {
    Channel.fromPath(params.samples)
        .splitCsv(header: true)
        .map { row -> tuple(row.sample_id, file(row.r1), file(row.r2)) }
}

workflow {
    samples_for_assemble = sampleCh()
    samples_for_align    = sampleCh()

    // assemble（module=metaspades）：消费 samples_for_assemble
    assemble_out = MetaSpades(samples_for_assemble)

    // align（module=metaspades_align）
    //   MetaSpades 输出是组装【目录】(sample_id, <dir>)，final.contig.fa 在目录内；
    //   流程层从目录派生 contig 文件对象，不做路径拼接，
    //   再与 samples_for_align 按 sample_id join 后送入 process
    //   （assemble_out 是 MetaSpades 单一 emit=assembly 通道，直接等于该目录通道，无 .contig 具名通道）
    contig_ch = assemble_out
        .map { id, dir -> tuple(id, file("${dir}/final.contig.fa")) }

    align_in = contig_ch
        .join(samples_for_align, by: [0])
        .map { id, contigs, r1, r2 -> tuple(id, contigs, r1, r2) }

    align_out = MetaSpades_Align(align_in)
}
