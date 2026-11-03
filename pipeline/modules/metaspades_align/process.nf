#!/usr/bin/env nextflow
nextflow.enable.dsl=2

// metaSPAdes 组装 contigs 回帖：将宿主去除后剩余的（umap）双端 reads 回帖到 metaSPAdes 组装的 contigs，
// 产出过滤、排序并建索引的 BAM，供下游分箱（binning）/ 覆盖度计算使用。
// 对应手工命令：
//   bwa index contigs.fasta
//   bwa mem contigs.fasta r1 r2 -t 8 | samtools view -F 3584 -q 20 -bS - > aln.bam
//   samtools sort -@ 4 -m 2G aln.bam -o aln.sort.bam
//   samtools index aln.sort.bam

process MetaSpades_Align {
    tag "MetaSpades_Align on ${sample_id}"

    input:
    // contigs：上游 metaSPAdes 产出的组装结果（显式 fa 文件，由流程层注入）
    tuple val(sample_id), path(contigs), path(r1), path(r2)

    output:
    // 落点 = outdir/metaspades_align/<sample_id>.aln.sort.bam(.bai)（样本由文件名承载）
    tuple val(sample_id), path("${sample_id}.aln.sort.bam"),     emit: bam
    tuple val(sample_id), path("${sample_id}.aln.sort.bam.bai"), emit: bai

    script:
    // -F 3584 = 过滤 secondary(0x100)+supplementary(0x400)+duplicate(0x800)；-q 20 = 最小 MAPQ
    // bwa index 在同进程内对 contigs 建索引（.amb/.ann/.bwt/.pac/.sa，留在 work dir）
    def sortMem = params.bam_sort_mem ?: '2G'
    """
    ${params.bwa_bin} index ${contigs}
    ${params.bwa_bin} mem ${contigs} ${r1} ${r2} -t ${task.cpus} \
        | ${params.samtools_bin} view -F 3584 -q 20 -bS - \
        > ${sample_id}.aln.bam
    ${params.samtools_bin} sort -@ ${task.cpus} -m ${sortMem} ${sample_id}.aln.bam \
        -o ${sample_id}.aln.sort.bam
    ${params.samtools_bin} index ${sample_id}.aln.sort.bam
    """
}
