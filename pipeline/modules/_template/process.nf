#!/usr/bin/env nextflow
nextflow.enable.dsl=2

// 模块模板：复制整个 _template/ 到 modules/<模块名>/ 后替换 My_Process 与各占位符
// 本文件只定义 process（无 workflow），因此不能写 params 块——默认值放同目录 config
// 输入文件一律由上层以文件对象注入（path(...)），模块内不拼接输入路径

process My_Process {
    tag "My_Process on ${sample_id}"

    input:
    tuple val(sample_id), path(in_fa), path(r1), path(r2)

    output:
    tuple val(sample_id), path("${sample_id}.result"), emit: result

    script:
    def mem = params.sort_mem ?: '2G'
    """
    ${params.tool_bin} do-something ${in_fa} ${r1} ${r2} -t ${task.cpus} > ${sample_id}.result
    """
}
