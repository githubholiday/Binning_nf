#!/usr/bin/env python3
"""yaml2config.py —— pipeline.yaml -> pipeline.generated.config（Nextflow withName 块）

读取 pipeline.yaml（步骤顺序 + 每步资源 + 调度器 + 容器），生成 pipeline.generated.config，
其中包含每个 process 的 withName { executor / queue / cpus / memory / container } 块。
流程级 nextflow.config 用 includeConfig 引入（放在各模块 config 之后），故覆盖模块默认资源。

依赖：优先用 PyYAML；未安装时自动回退到内置极简解析器（见 nfyaml.py）。

用法：
  python yaml2config.py pipeline.yaml -o pipeline.generated.config
  python yaml2config.py pipeline.yaml            # 默认输出 pipeline.generated.config
"""
import argparse
import re
import sys

from nfyaml import load_yaml, as_list


def is_num(v):
    return bool(re.fullmatch(r'-?\d+', str(v)))


def q_scalar(v):
    """数值裸写，字符串加单引号（executor/queue/memory/cpus）。"""
    s = str(v).strip().strip("'\"")
    if is_num(s):
        return s
    return "'" + s.replace("'", "\\'") + "'"


def q_container(v):
    """容器值用双引号，保留 ${params.xxx} 插值。"""
    s = str(v).strip().strip("'\"")
    return '"' + s + '"'


def gen_config(cfg):
    steps = cfg.get('steps', []) or []
    lines = []
    lines.append("// AUTO-GENERATED from pipeline.yaml by yaml2config.py —— 编辑请改 pipeline.yaml 后重新生成，勿手改本文件")
    lines.append("// 步骤顺序 manifest（实际执行顺序由 main.nf 的 channel DAG 决定）：")
    for s in steps:
        deps = as_list(s.get('depends_on'))
        lines.append(f"//   {s.get('name', '?'):12s} depends_on: [{', '.join(deps)}]")
    lines.append("")
    lines.append("process {")
    for s in steps:
        proc = s.get('process')
        if not proc:
            continue
        lines.append(f"    withName: '{proc}' {{")
        if s.get('executor'):
            lines.append(f"        executor  = {q_scalar(s['executor'])}")
        if s.get('queue'):
            lines.append(f"        queue     = {q_scalar(s['queue'])}")
        if s.get('cpus'):
            lines.append(f"        cpus      = {q_scalar(s['cpus'])}")
        if s.get('memory'):
            lines.append(f"        memory    = {q_scalar(s['memory'])}")
        if s.get('container'):
            lines.append(f"        container = {q_container(s['container'])}")
        lines.append("    }")
    lines.append("}")
    return "\n".join(lines) + "\n"


def main():
    ap = argparse.ArgumentParser(
        description='pipeline.yaml -> pipeline.generated.config (Nextflow withName blocks)')
    ap.add_argument('yaml', help='pipeline.yaml 路径')
    ap.add_argument('-o', '--output', default='pipeline.generated.config',
                    help='输出文件，默认 pipeline.generated.config')
    args = ap.parse_args()

    cfg = load_yaml(args.yaml)
    if not cfg.get('steps'):
        print("⚠️  pipeline.yaml 未定义 steps，未生成配置。", file=sys.stderr)
        sys.exit(1)
    out = gen_config(cfg)
    with open(args.output, 'w', encoding='utf-8') as f:
        f.write(out)
    print(f"[generated] {len(cfg['steps'])} steps -> {args.output}")


if __name__ == '__main__':
    main()
