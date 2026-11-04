#!/usr/bin/env bash
# ============================================================
# nfscan.sh —— 一键扫描所有 nextflow 项目的状态（任意目录可执行）
#
# 原理：nextflow 没有全局 run 数据库，每个 run 的元数据都存在【启动目录】
#   的 .nextflow/history 与 work/ 里（nextflow log 无 -dir 参数）。
#   本脚本找出扫描根下所有启动目录，逐个读取 history（秒级、不启 JVM），
#   并对最近一次 run 调 nextflow log 汇总各 process 进度与失败 workdir。
#
# 用法：
#   nfscan.sh <根目录>...          扫描根目录下所有启动目录（含任务进度）
#   nfscan.sh -q <根目录>...       快速模式：只读 history，不启动 JVM（无任务进度）
#   nfscan.sh -f <根目录>...       只显示有失败任务的项目
#   nfscan.sh -n <N>               每项目显示最近 N 次 run（默认 3）
#   默认根目录可写入 ~/.nfscan.conf：  roots=(/annogene/.../238 /other/path)
#   扫描深度默认 6 层，-d <N> 可改。
# ============================================================
set -uo pipefail

N_RUNS=3 QUICK=0 ONLY_FAIL=0 MAXDEPTH=6
ROOTS=()
while [ $# -gt 0 ]; do
    case "$1" in
        -q) QUICK=1 ;;
        -f) ONLY_FAIL=1 ;;
        -n) N_RUNS="$2"; shift ;;
        -d) MAXDEPTH="$2"; shift ;;
        -h|--help) sed -n '2,19p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *)  ROOTS+=("$1") ;;
    esac
    shift
done
if [ ${#ROOTS[@]} -eq 0 ] && [ -f "$HOME/.nfscan.conf" ]; then
    # shellcheck disable=SC1090
    source "$HOME/.nfscan.conf"      # 提供 roots=(...)
    ROOTS=("${roots[@]}")
fi
[ ${#ROOTS[@]} -eq 0 ] && { echo "用法: nfscan.sh <根目录>...   （或配置 ~/.nfscan.conf）"; exit 1; }

# ---- 收集所有启动目录，按最近活动时间排序（新的在前） ----
MAPFILE=()
tmp=$(mktemp)
for r in "${ROOTS[@]}"; do
    find "$r" -maxdepth "$MAXDEPTH" -type f -path '*/.nextflow/history' 2>/dev/null |
    while read -r h; do
        d=$(dirname "$(dirname "$h")")
        printf '%s\t%s\n' "$(stat -c %Y "$h" 2>/dev/null || echo 0)" "$d"
    done
done | sort -rn > "$tmp"
while IFS=$'\t' read -r _ d; do MAPFILE+=("$d"); done < "$tmp"
rm -f "$tmp"

[ ${#MAPFILE[@]} -eq 0 ] && { echo "（扫描根下没有发现任何 nextflow 启动目录）"; exit 0; }

nfail_total=0
for d in "${MAPFILE[@]}"; do
    hist="$d/.nextflow/history"
    [ -f "$hist" ] || continue
    total=$(grep -c . "$hist")

    # ---- run 级摘要（纯 history，不启 JVM）----
    head_line=$(tail -n 1 "$hist" | awk -F'\t' '{printf "%s | %s | %s", $3, $1, $4}')
    printf '── %s\n' "$d"
    printf '   run: %s   (共 %s 次)\n' "$head_line" "$total"
    tail -n "$N_RUNS" "$hist" | awk -F'\t' \
        '{printf "     · %-22s %-9s %-8s %s\n", $3, $1, $4, $2}'

    # ---- 任务级进度（需 nextflow log，每个项目 ~3s JVM）----
    [ "$QUICK" = 1 ] && { printf '\n'; continue; }
    if ! command -v nextflow >/dev/null 2>&1; then
        printf '   (nextflow 不在 PATH，跳过任务进度；加 -q 消除本提示)\n\n'
        continue
    fi
    run=$(tail -n 1 "$hist" | awk -F'\t' 'NF{print $3}')
    log_out=$( cd "$d" && nextflow log "$run" -f name,status,exit,workdir 2>/dev/null )
    if [ -z "$log_out" ]; then
        printf '   (任务明细不可用：可能是刚启动或 cache 被清理)\n\n'
        continue
    fi

    progress=$(printf '%s\n' "$log_out" | awk -F'\t' '
        NR==1 && $1=="name" {next}
        NF {
            n=$1; s=$2; w=$4
            if (!(n in seen)) { seen[n]=1; ord[++m]=n }
            if (s=="COMPLETED" || s=="CACHED") ok[n]++
            else if (s ~ /FAIL|ABORT/) { bad[n]++; if (!(n in fw)) { fw[n]=w; fe[n]=$3 } }
        }
        END {
            line=""
            for (i=1; i<=m; i++) {
                n=ord[i]
                line = line (line=="" ? "" : " | ") n ": ✓" ok[n]+ca[n]+0 " ✗" bad[n]+0
            }
            print (line=="" ? "(无任务记录)" : line)
        }')
    printf '   进度: %s\n' "$progress"

    fails=$(printf '%s\n' "$log_out" | awk -F'\t' '
        NR==1 && $1=="name" {next}
        $2 ~ /FAIL|ABORT/ && NF {printf "%s\t%s\t%s\n", $1, $3, $4}')
    if [ -n "$fails" ]; then
        nfail=$(printf '%s\n' "$fails" | grep -c .)
        nfail_total=$((nfail_total + nfail))
        printf '   失败 (%s 个，看报错直接复制执行)：\n' "$nfail"
        printf '%s\n' "$fails" | while IFS=$'\t' read -r p e w; do
            printf '     · %-24s exit=%-5s %s\n       tail -40 %s/.command.err\n' "$p" "$e" "$w" "$w"
        done
    elif [ "$ONLY_FAIL" = 1 ]; then
        printf '\n' && continue        # -f 模式下隐藏无失败的项目
    fi
    printf '\n'
done

[ "$nfail_total" -gt 0 ] && printf '⚠ 共 %s 个失败任务（上方已给出查看命令）\n' "$nfail_total"
exit 0
