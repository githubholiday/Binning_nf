#!/usr/bin/env nextflow
nextflow.enable.dsl=2

// ============================================================
// 模块 process.nf —— 通用注释示例（学习用，非真实步骤）
//
// 本文件【只定义 process】，不写 workflow、不写 params 块。
// 原因：纯 process 定义文件没有 workflow，若在此声明 params 块，
//       新版 Nextflow 会报 "Params block cannot be defined without an entry workflow"。
//       → 软件参数的【默认值】一律放在模块的 config 文件里（见同目录 config）。
//
// 输入文件约定（重要）：
//   - 所有输入文件都用显式文件参数（path(...) / file(...)），由上游或流程层以【文件对象】注入；
//   - 模块内【不做】输入路径拼接（例如不要 file("${outdir}/.../${id}/x.fa") 去猜路径）；
//   - 只有【模块内步骤之间的中间文件名】才允许拼接（如 "${sample_id}.tmp.bam"）。
//   输入路径的拼接/查找属于流程层的职责。
// ============================================================

process My_Process {
    tag "My_Process on ${sample_id}"

    input:
    // project 等透传字段用于下游分组；真正要运算的文件用 path(...) 接收
    tuple val(sample_id), val(project), path(in_fa), path(r1), path(r2)

    output:
    // 输出文件名带 sample_id（落点 = outdir/<模块名>/<sample_id>.result），样本由文件名承载，天然隔离
    tuple val(sample_id), val(project), path("${sample_id}.result"), emit: result

    script:
    // 软件命令里一律用 params.<xxx> 引用 config 里声明的二进制路径 / 参数
    // 资源用 ${task.cpus} / ${task.memory}，不要写死线程数
    def mem = params.sort_mem ?: '2G'
    """
    ${params.tool_bin} do-something ${in_fa} ${r1} ${r2} -t ${task.cpus} > ${sample_id}.result
    """
}
