#!/usr/bin/env bash
# ============================================================
# nfstatus.sh —— Nextflow 运行状态速查
#
# 为什么需要它：
#   nextflow log 读的是【当前工作目录】下的 .nextflow/history，没有 -dir 参数，
#   换一个目录就查不到历史。本脚本负责 cd 到位再查，并给出三种视图。
#
# 用法：
#   nfstatus.sh -p <项目根目录>        总览：扫描根目录下所有 run 目录的最近一次运行
#   nfstatus.sh <运行目录>             单目录：最近 10 次 run（不给参数=当前目录）
#   nfstatus.sh -t <运行目录> [run名]  任务明细：状态/退出码/workdir（默认最近一次 run）
#   nfstatus.sh -e <运行目录> [run名]  只看失败任务，并给出 .command.err 查看命令
#
# 说明：
#   - 概览模式（-p / 单目录）只读 .nextflow/history，不启动 JVM，秒回
#   - 明细模式（-t / -e）调用 nextflow log，需要 nextflow 在 PATH 里
#   - 也可以直接看运行报告：<outdir>/pipeline_info/trace.txt（含 workdir 列）
# ============================================================
set -uo pipefail

FIELD='name,status,exit,workdir'

usage() {
    sed -n '3,20p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
}

# 最近一次 run 名（读 history 最后一行，避免启动 JVM）
latest_run() {
    local hist="$1/.nextflow/history"
    [ -f "$hist" ] || return 1
    tail -n 1 "$hist" 2>/dev/null | awk -F'\t' 'NF {print $3}'
}

# 单目录最近 N 次 run
runs_table() {
    local dir="$1" n="${2:-10}" hist="$1/.nextflow/history"
    if [ ! -f "$hist" ]; then
        printf '  (没有 %s —— 该目录不是 nextflow 启动目录)\n' "$hist"
        return 1
    fi
    printf '  %-24s %-9s %-6s %s\n' 'TIME' 'DURATION' 'STATUS' 'RUN NAME'
    tail -n "$n" "$hist" | awk -F'\t' '{printf "  %-22s %-9s %-6s %s\n", $1, $2, $4, $3}'
}

# 扫描项目根目录下所有 run 目录
scan_root() {
    local root="$1"
    printf '%-56s %-24s %-9s %-6s %s\n' 'RUN DIR' 'LAST RUN' 'DURATION' 'STATUS' 'RUN NAME'
    printf '%s\n' "$(printf '%.0s-' $(seq 1 120))"
    find "$root" -maxdepth 6 -type f -path '*/.nextflow/history' 2>/dev/null | sort | while read -r hist; do
        dir=$(dirname "$(dirname "$hist")")
        last=$(tail -n 1 "$hist" 2>/dev/null)
        [ -n "$last" ] || continue
        printf '%-56s ' "${dir#"$root"/}"
        printf '%s\n' "$last" | awk -F'\t' '{printf "%-22s %-9s %-5s %s\n", $1, $2, $4, $3}'
    done
}

# 任务明细
tasks_table() {
    local dir="$1" run="${2:-}"
    [ -n "$run" ] || run=$(latest_run "$dir")
    [ -n "$run" ] || { printf '  没有可用的 run 记录\n'; return 1; }
    printf '== run: %s ==\n' "$run"
    printf '  %-28s %-11s %-5s %s\n' 'TASK' 'STATUS' 'EXIT' 'WORKDIR'
    ( cd "$dir" && nextflow log "$run" -f "$FIELD" 2>/dev/null ) |
        awk -F'\t' 'NR==1 && $1=="name" {next} NF {printf "  %-28s %-10s %-5s %s\n", $1, $2, $3, $4}'
}

# 失败任务 + 日志路径
failed_tasks() {
    local dir="$1" run="${2:-}" out n
    [ -n "$run" ] || run=$(latest_run "$dir")
    printf '== 失败任务（run: %s）==\n' "$run"
    out=$( cd "$dir" && nextflow log "$run" -f "$FIELD" 2>/dev/null )
    n=$(printf '%s\n' "$out" | awk -F'\t' 'NR==1 && $1=="name" {next} $2 ~ /FAIL|ABORT/ {c++} END{print c+0}')
    if [ "$n" = "0" ]; then
        printf '  没有失败任务\n'
        return 0
    fi
    printf '%s\n' "$out" | awk -F'\t' 'NR==1 && $1=="name" {next} $2 ~ /FAIL|ABORT/ {printf "  %-28s %-8s exit=%-4s %s\n", $1, $2, $3, $4}'
    printf '\n  查看报错（直接复制执行）：\n'
    printf '%s\n' "$out" | awk -F'\t' 'NR==1 && $1=="name" {next} $2 ~ /FAIL|ABORT/ {printf "    tail -40 %s/.command.err\n", $4}'
    printf '\n  注意：staging 阶段失败（输入文件不存在等）看 .command.err；\n'
    printf '        SPAdes 等软件自身报错看 workdir 下的软件日志（如 <sample>_metaspades/spades.log）\n'
}

case "${1:-}" in
    -h|--help) usage ;;
    -p) MODE=scan;  ROOT="${2:-$PWD}" ;;
    -t) MODE=tasks; DIR="${2:-$PWD}";  RUN="${3:-}" ;;
    -e) MODE=fail;  DIR="${2:-$PWD}";  RUN="${3:-}" ;;
    "") MODE=run;   DIR="$PWD" ;;
    *)  MODE=run;   DIR="$1" ;;
esac

case "$MODE" in
    scan)
        printf '== 项目总览: %s ==\n' "$ROOT"
        scan_root "$ROOT"
        printf '\n看明细：nfstatus.sh -t <运行目录>    看失败日志：nfstatus.sh -e <运行目录>\n'
        ;;
    run)
        printf '== 运行目录: %s ==\n' "$DIR"
        runs_table "$DIR" 10
        printf '\n看任务明细：nfstatus.sh -t %s\n' "$DIR"
        printf '看失败日志：nfstatus.sh -e %s\n' "$DIR"
        ;;
    tasks) tasks_table "$DIR" "$RUN" ;;
    fail)  failed_tasks "$DIR" "$RUN" ;;
esac
