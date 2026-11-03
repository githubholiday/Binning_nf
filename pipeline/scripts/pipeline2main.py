#!/usr/bin/env python3
"""pipeline2main.py —— 由 pipeline.yaml 生成 main.nf（自动串联流程）

按 pipeline.yaml 的 steps 声明生成流程入口：
  - include 各模块的 process.nf
  - 构建样本 channel（按 samples_columns / samples_types）
  - 按 input 接线串起各步骤：input: samples 表示接样本通道；
    input: <上一步 name> 表示接上一步的输出通道（带 emit 时接具名通道）

用法：
  python pipeline2main.py pipeline.yaml -o main.nf

约定：
  - pipeline.yaml 为扁平结构（顶层标量 + steps 列表），零依赖解析
  - 步骤输出变量名默认取 steps[i].output，未指定则用 <name>_out
  - 步骤输出为多通道且声明了 emit 时，下游引用为 <var>.<emit>
"""
import argparse
import os
import sys

from nfyaml import load_yaml, as_list


def _esc(s):
    return str(s).strip()


def build_samples_channel(cfg):
    """按 samples_columns / samples_types 生成样本 channel 代码。"""
    cols = [c.strip() for c in _esc(cfg.get('samples_columns', '')).split(',') if c.strip()]
    types = [t.strip() for t in _esc(cfg.get('samples_types', '')).split(',') if t.strip()]
    if not cols:
        return None, []
    if len(cols) != len(types):
        raise SystemExit("❌ samples_columns 与 samples_types 数量不一致")

    parts = []
    for col, typ in zip(cols, types):
        if typ == 'val':
            parts.append(f"row.{col}")
        elif typ == 'path':
            parts.append(f"file(row.{col})")
        else:
            raise SystemExit(f"❌ 未知的 samples_types 取值: {typ}（只支持 val / path）")

    tuple_expr = "tuple(" + ", ".join(parts) + ")"
    code = (
        "    samples_ch = Channel.fromPath(params.samples)\n"
        "        .splitCsv(header: true)\n"
        f"        .map {{ row -> {tuple_expr} }}"
    )
    return code, cols


def build_includes(steps):
    """按模块去重生成 include 语句。"""
    seen = {}
    for s in steps:
        mod = s.get('module')
        proc = s.get('process')
        if not mod or not proc:
            continue
        seen.setdefault(mod, set()).add(proc)

    lines = []
    for mod in sorted(seen):
        procs = sorted(seen[mod])
        lines.append(f"include {{ {', '.join(procs)} }} from './modules/{mod}/process.nf'")
    return lines


def build_workflow(cfg, steps):
    """生成 workflow 块。"""
    out = []
    out.append("workflow {")

    sample_code, _ = build_samples_channel(cfg)
    if sample_code:
        out.append("    // 样本通道（samples.csv）")
        out.append(sample_code)
        out.append("")

    # 记录每步的输出变量名，供下游引用
    out_var = {}
    for s in steps:
        name = s.get('name')
        if not name:
            continue
        out_var[name] = s.get('output') or f"{name}_out"

    for s in steps:
        name = s.get('name')
        proc = s.get('process')
        if not name or not proc:
            continue

        src = _esc(s.get('input', ''))
        if not src:
            raise SystemExit(f"❌ 步骤 {name} 缺少 input")
        if src == 'samples':
            ch = 'samples_ch'
        elif src in out_var:
            ch = out_var[src]
            emit = s.get('emit')
            # emit 属于"提供方"步骤：若被引用步骤声明了 emit 通道，则用具名通道
            src_step = next((x for x in steps if x.get('name') == src), None)
            if src_step and src_step.get('emit'):
                ch = f"{ch}.{src_step['emit']}"
        else:
            raise SystemExit(f"❌ 步骤 {name} 的 input '{src}' 既不是 samples 也不是已定义的步骤名")

        var = out_var[name]
        deps = ', '.join(as_list(s.get('depends_on')))
        out.append(f"    // {name}（module={s.get('module', '?')}, depends_on: [{deps}]）")
        out.append(f"    {var} = {proc}({ch})")

    out.append("}")
    return out


def gen_main(cfg):
    steps = cfg.get('steps', []) or []
    if not steps:
        raise SystemExit("❌ pipeline.yaml 未定义 steps")

    lines = []
    lines.append("#!/usr/bin/env nextflow")
    lines.append("nextflow.enable.dsl=2")
    lines.append("")
    lines.append("// ⚠️ 本文件由 pipeline2main.py 依据 pipeline.yaml 自动生成，请勿手改。")
    lines.append("//    改流程请改 pipeline.yaml，然后重跑：")
    lines.append("//    python scripts/pipeline2main.py pipeline.yaml -o main.nf")
    lines.append("")
    lines.extend(build_includes(steps))
    lines.append("")
    lines.append("params {")
    lines.append(f"    samples = '{_esc(cfg.get('samples_file', 'samples.csv'))}'")
    lines.append("}")
    lines.append("")
    lines.extend(build_workflow(cfg, steps))
    lines.append("")
    return "\n".join(lines)


def main():
    ap = argparse.ArgumentParser(description='pipeline.yaml -> main.nf（自动串联流程）')
    ap.add_argument('yaml', help='pipeline.yaml 路径')
    ap.add_argument('-o', '--output', default='main.nf', help='输出文件，默认 main.nf')
    args = ap.parse_args()

    cfg = load_yaml(args.yaml)
    out = gen_main(cfg)
    with open(args.output, 'w', encoding='utf-8') as f:
        f.write(out)
    print(f"[main.nf] {len(cfg.get('steps', []))} steps -> {args.output}")


if __name__ == '__main__':
    main()
