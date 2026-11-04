#!/usr/bin/env nextflow
nextflow.enable.dsl=2

// 对应手工：
//   bwa index contigs.fasta
//   bwa mem contigs.fasta r1 r2 -t 8 | samtools view -F 3584 -q 20 -bS - | samtools sort -@ 4 -m 2G -o aln.sort.bam && samtools index
// -F 3584 = 过滤 secondary(0x100)+supplementary(0x400)+duplicate(0x800)；-q 20 = 最小 MAPQ
// bwa index 在同进程内建（.amb/.ann/.bwt/.pac/.sa 留在 work dir，不发布）

process MetaSpades_Align {
    tag "MetaSpades_Align on ${sample_id}"

    input:
    // contigs 由上游 MetaSpades 通道注入（流程内）或 params.contig_fa（单独运行）
    tuple val(sample_id), path(contigs), path(r1), path(r2)

    output:
    // 落点 outdir/metaspades_align/<sample_id>.aln.sort.bam(.bai)
    tuple val(sample_id), path("${sample_id}.aln.sort.bam"),     emit: bam
    tuple val(sample_id), path("${sample_id}.aln.sort.bam.bai"), emit: bai

    script:
    // SGE 陷阱：Nextflow 把 task.memory 均分到各 slot（h_vmem≈memory/cpus），
    // ulimit -v 限制的是【单进程】；sort 预分配 = 线程数×-m，必须 ≤ 单 slot 额度，
    // 否则报 couldn't allocate memory for bam_mem。故 sort 线程压到 2、
    // -m 按单 slot 额度的 80% 推导（20GB/8slot→2.5G/slot→-m 1G→预分配 2G）。
    // params.bam_sort_mem 可强制覆盖（自行承担 ulimit 风险）。
    def sortThreads = Math.min(2, task.cpus ?: 1)
    def perSlotMega = (task.memory ? task.memory.mega : 2048d) / (task.cpus ?: 1)
    def sortMem = params.bam_sort_mem ?: "${Math.max(256, (perSlotMega * 0.8 / sortThreads) as int)}M"
    """
    ${params.bwa_bin} index ${contigs}
    ${params.bwa_bin} mem ${contigs} ${r1} ${r2} -t ${task.cpus} \
        | ${params.samtools_bin} view -F 3584 -q 20 -bS - \
        > ${sample_id}.aln.bam
    ${params.samtools_bin} sort -@ ${sortThreads} -m ${sortMem} ${sample_id}.aln.bam \
        -o ${sample_id}.aln.sort.bam
    ${params.samtools_bin} index ${sample_id}.aln.sort.bam
    """
}
