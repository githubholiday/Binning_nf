#!/bin/bash
# ==============================================================================
# metaSPAdes 组装流程 —— SGE 集群运行入口
#
# 目录分层：
#   pipeline/   流程本体（流程级）：nextflow.config / pipeline.yaml / modules/
#   project/    本项目（项目级）：nextflow.config / samples.csv / comparison.csv
#
# 用法（在 project/ 下执行，流程本体在 ../pipeline）：
#   bash ../run_sge.sh check      # 预检：环境、路径、配置
#   bash ../run_sge.sh inner      # 在计算节点上跑 nextflow 主进程（由 qsub 调用，一般不手动跑）
#   bash ../run_sge.sh submit     # 把 nextflow 主进程投递到队列（推荐，登录节点断开不影响流程）
#   bash ../run_sge.sh monitor    # 查看已投递任务与产出
#
# 可覆盖的环境变量：
#   NF_QUEUE   跑 nextflow 主进程用的队列（主进程本身很轻，micro.q 即可）   默认 micro.q
#   NF_MEM     主进程申请的内存                                              默认 8G
#   NF_JOB     主进程作业名                                                  默认 nf_metaspades
#   NF_ARGS    传给 nextflow run 的额外参数                                   默认 -resume
#   SGE_PROFILE  使用的 profile                                              默认 sge
# ==============================================================================
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$ROOT_DIR/project"
PIPELINE_DIR="$ROOT_DIR/pipeline"

NF_QUEUE="${NF_QUEUE:-micro.q}"
NF_MEM="${NF_MEM:-8G}"
NF_JOB="${NF_JOB:-nf_metaspades}"
NF_ARGS="${NF_ARGS:--resume}"
SGE_PROFILE="${SGE_PROFILE:-sge}"

cd "$PROJECT_DIR"

# 从【项目级】nextflow.config 取关键配置（保持与配置一致，不在脚本里重复维护路径）
cfg() {
    grep -E "^[[:space:]]*$1[[:space:]]*=" nextflow.config | head -1 \
        | sed -E "s/^[[:space:]]*$1[[:space:]]*=[[:space:]]*//; s/[[:space:]]*\/\/.*$//; s/^['\"]//; s/['\"]\$//"
}
OUTDIR="$(cfg outdir)"
WORKDIR="$(grep -E '^[[:space:]]*workDir[[:space:]]*=' nextflow.config | head -1 \
    | sed -E 's/^[[:space:]]*workDir[[:space:]]*=[[:space:]]*//; s/[[:space:]]*\/\/.*$//; s/^['"'"'"]//; s['"'"'"]$//')"

# 从任意配置文件取键值：cfgval <文件> <键>  （去引号、去行尾注释）
cfgval() {
    grep -E "^[[:space:]]*$2[[:space:]]*=" "$1" 2>/dev/null | head -1 \
        | sed -E "s/^[[:space:]]*$2[[:space:]]*=[[:space:]]*//; s/[[:space:]]*\/\/.*\$//; s/^['\"]//; s/['\"]\$//"
}

# ------------------------------------------------------------------------------
check() {
    echo "================ 预检 ================"
    echo "-- 流程本体: $PIPELINE_DIR"
    echo "-- 项目目录: $PROJECT_DIR"

    command -v nextflow >/dev/null 2>&1 || { echo "✗ 找不到 nextflow（需先安装并加入 PATH）"; exit 1; }
    echo "✓ nextflow: $(command -v nextflow)"; nextflow -version 2>/dev/null | head -2

    if command -v qsub >/dev/null 2>&1; then
        echo "✓ qsub: $(command -v qsub)"
    else
        echo "⚠ 找不到 qsub：当前节点不能投递作业（check / stub 测试仍可用）"
    fi

    if command -v singularity >/dev/null 2>&1; then
        echo "✓ singularity: $(command -v singularity)"
    elif command -v apptainer >/dev/null 2>&1; then
        echo "✓ apptainer: $(command -v apptainer)"
    else
        echo "⚠ 找不到 singularity/apptainer：若走容器模式必须安装（或改用集群已装的二进制）"
    fi

    echo "-- 流程级文件"
    for f in nextflow.config pipeline.yaml pipeline.generated.config main.nf; do
        [ -f "$PIPELINE_DIR/$f" ] && echo "  ✓ pipeline/$f" || echo "  ✗ 缺 pipeline/$f"
    done
    [ -d "$PIPELINE_DIR/modules/metaspades" ] && echo "  ✓ pipeline/modules/metaspades" || echo "  ✗ 缺模块目录"

    echo "-- 项目级文件"
    for f in nextflow.config samples.csv comparison.csv; do
        [ -f "$PROJECT_DIR/$f" ] && echo "  ✓ project/$f" || echo "  ✗ 缺 project/$f"
    done
    [ -f samples.csv ] && echo "    样本数：$(($(wc -l < samples.csv) - 1))"

    echo "-- 关键配置（项目级）"
    echo "  outdir  = $OUTDIR"
    echo "  workDir = $WORKDIR"

    echo "-- 路径检查"
    [ -d "$WORKDIR" ] || mkdir -p "$WORKDIR"
    [ -d "$OUTDIR" ]  || mkdir -p "$OUTDIR"
    touch "$WORKDIR/.wtest" 2>/dev/null && echo "  ✓ workDir 可写" || { echo "  ✗ workDir 不可写: $WORKDIR"; exit 1; }
    touch "$OUTDIR/.wtest"  2>/dev/null && echo "  ✓ outdir 可写"  || { echo "  ✗ outdir 不可写: $OUTDIR"; exit 1; }
    rm -f "$WORKDIR/.wtest" "$OUTDIR/.wtest"

    echo "-- 模块软件与环境（流程级配置中的占位，需按实际修改）"
    SIF_DIR="$(cfgval "$PIPELINE_DIR/modules/metaspades/config" sif_dir)"
    SIF_DIR="${SIF_DIR//\$\{projectDir\}/$PIPELINE_DIR}"
    META_BIN="$(cfgval "$PIPELINE_DIR/modules/metaspades/config" metaspades_bin)"
    DATA_ROOT="$(cfgval "$PIPELINE_DIR/nextflow.config" data_root)"
    echo "  sif_dir          = $SIF_DIR"
    echo "  metaspades_bin   = $META_BIN"
    echo "  容器镜像          = $SIF_DIR/metaspades.sif"
    echo "  容器 bind 根目录  = $DATA_ROOT"
    if [ -f "$SIF_DIR/metaspades.sif" ]; then
        echo "  ✓ 镜像文件存在"
    else
        echo "  ✗ 缺镜像文件 $SIF_DIR/metaspades.sif —— 需自行构建/拷贝（见 pipeline/sif/README.md）"
    fi
    if [ "$META_BIN" != "metaSPAdes.py" ] && [ ! -x "$META_BIN" ]; then
        echo "  ⚠ metaspades_bin=$META_BIN 非容器内命令且本地不可执行 —— 确认路径正确（相对路径会失效）"
    fi

    echo "-- 队列与资源"
    if command -v qconf >/dev/null 2>&1; then qconf -sql 2>/dev/null | awk '{print "  队列 " $1}'; fi
    echo "  本流程每任务申请：cpus=32  memory=250GB  queue=mid.q,sci.q（见 pipeline.yaml）"
    echo "  ⚠ 需确认所在队列允许 250GB 内存与 32 核，否则任务会被拒绝"
    echo "================ 预检结束 ================"
}

# ------------------------------------------------------------------------------
inner() {
    echo "[$(date '+%F %T')] nextflow 主进程启动：profile=$SGE_PROFILE args=$NF_ARGS"
    # 在项目目录启动：Nextflow 合并「流程目录的 nextflow.config」+「启动目录的 nextflow.config」
    nextflow run "$PIPELINE_DIR" -profile "$SGE_PROFILE" $NF_ARGS
    echo "[$(date '+%F %T')] nextflow 主进程结束，退出码 $?"
}

# ------------------------------------------------------------------------------
# 只跑单个模块（调试用）：nextflow run <模块>/main.nf -c <流程级 nextflow.config>
#   -c 是"软覆盖"：在默认配置集（启动目录=项目级 + 脚本所在目录=模块级）之上叠加流程级配置，
#   这样 singularity / profile / includeConfig 各模块 config 才会齐全。
module() {
    local mod="${1:-metaspades}"
    cd "$PROJECT_DIR"
    echo "[$(date '+%F %T')] 只跑模块 $mod（profile=$SGE_PROFILE args=$NF_ARGS）"
    nextflow run "$PIPELINE_DIR/modules/$mod/main.nf" -c "$PIPELINE_DIR/nextflow.config" \
        -profile "$SGE_PROFILE" $NF_ARGS
    echo "[$(date '+%F %T')] 模块 $mod 结束，退出码 $?"
}

# ------------------------------------------------------------------------------
submit() {
    check
    echo "== 投递 nextflow 主进程到队列 $NF_QUEUE =="
    cd "$PROJECT_DIR"
    qsub -q "$NF_QUEUE" -N "$NF_JOB" -cwd -V -j y \
         -o "$PROJECT_DIR/nf_master.log" -e "$PROJECT_DIR/nf_master.err" \
         -l h_vmem="$NF_MEM" \
         bash "$ROOT_DIR/run_sge.sh" inner
    echo "✓ 已投递。查看：qstat | grep $NF_JOB    日志：tail -f project/nf_master.log"
}

# ------------------------------------------------------------------------------
monitor() {
    echo "== 已投递任务 =="
    qstat 2>/dev/null | grep -E "job-ID|${NF_JOB}|qsub" || echo "  （无匹配作业）"
    echo "== 主进程日志 =="
    [ -f "$PROJECT_DIR/nf_master.log" ] && tail -30 "$PROJECT_DIR/nf_master.log" || echo "  nf_master.log 尚未生成"
    echo "== 产出 =="
    if [ -d "$OUTDIR" ]; then
        echo "  已发布样本数：$(find "$OUTDIR" -name final.contig.fa 2>/dev/null | wc -l)"
        find "$OUTDIR" -name final.contig.fa 2>/dev/null | head -5
    else
        echo "  outdir 尚未创建: $OUTDIR"
    fi
}

case "${1:-check}" in
    check)   check ;;
    inner)   inner ;;
    module)  module "${2:-metaspades}" ;;
    submit)  submit ;;
    monitor) monitor ;;
    *) echo "用法: bash run_sge.sh {check|inner|module [模块名]|submit|monitor}"; exit 1 ;;
esac
