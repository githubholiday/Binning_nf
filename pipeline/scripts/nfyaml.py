#!/usr/bin/env python3
"""nfyaml —— YAML 读取（零依赖兜底）

优先用 PyYAML；未安装时用内置极简解析器，仅支持本流程约定的扁平结构：
    - 顶层标量：key: value
    - 顶层列表：key: 下跟 "  - key: value" 的扁平键值项
不支持：嵌套映射、多行字符串、块标量。行尾注释（空白后 #）会被剥离。

用法：
    from nfyaml import load_yaml
    cfg = load_yaml('pipeline.yaml')
"""
import re
import sys

try:
    import yaml  # noqa: F401
    _HAVE_YAML = True
except ImportError:
    _HAVE_YAML = False


def _strip_comment(s):
    """剥离行尾注释：空白后紧跟 # 起为注释；引号内内容与 abc#def 不受影响。"""
    out = []
    quote = None
    for i, ch in enumerate(s):
        if quote:
            out.append(ch)
            if ch == quote:
                quote = None
            continue
        if ch in ("'", '"'):
            quote = ch
            out.append(ch)
            continue
        if ch == '#' and (i == 0 or s[i - 1] in ' \t'):
            break
        out.append(ch)
    return ''.join(out).strip()


def _scalar(val):
    val = _strip_comment(val)
    if val == '':
        return ''
    if val.startswith('[') and val.endswith(']'):
        inner = val[1:-1]
        return [x.strip().strip("'\"") for x in inner.split(',') if x.strip()]
    if (val.startswith("'") and val.endswith("'")) or (val.startswith('"') and val.endswith('"')):
        return val[1:-1]
    return val


def parse_yaml_min(text):
    """极简解析：顶层 key:value 标量 + 顶层列表（列表项为扁平标量字段）。"""
    data = {}
    cur_list = None
    cur_item = None
    for raw in text.splitlines():
        line = raw.rstrip()
        if not line.strip() or line.lstrip().startswith('#'):
            continue
        # 顶层 key: value（无缩进）
        if not line.startswith(' '):
            m = re.match(r'^([A-Za-z_]\w*):\s*(.*)$', line)
            if m:
                key, val = m.group(1), m.group(2)
                if val.strip() == '':
                    # 可能是列表头（后面跟 "  - key: value"）
                    cur_list = []
                    cur_item = None
                    data[key] = cur_list
                else:
                    cur_list = None
                    data[key] = _scalar(val)
                continue
        # 列表项起始：  - key: value
        if cur_list is not None:
            m = re.match(r'^\s*-\s+([A-Za-z_]\w*):\s*(.*)$', line)
            if m:
                cur_item = {}
                cur_list.append(cur_item)
                cur_item[m.group(1)] = _scalar(m.group(2))
                continue
            # 当前列表项的字段
            m = re.match(r'^\s+([A-Za-z_]\w*):\s*(.*)$', line)
            if m and cur_item is not None:
                cur_item[m.group(1)] = _scalar(m.group(2))
                continue
    return data


def load_yaml(path):
    """读取 YAML，返回 dict。PyYAML 可用则用之，否则用内置极简解析器。"""
    with open(path, 'r', encoding='utf-8') as f:
        text = f.read()
    if _HAVE_YAML:
        return yaml.safe_load(text) or {}
    print("ℹ️  未检测到 PyYAML，使用内置极简解析器（YAML 需保持扁平结构，勿用嵌套映射/多行字符串）。",
          file=sys.stderr)
    return parse_yaml_min(text)


def as_list(v):
    """把标量/列表统一成列表。"""
    if v is None:
        return []
    if isinstance(v, list):
        return v
    s = str(v).strip()
    if s.startswith('[') and s.endswith(']'):
        return [x.strip().strip("'\"") for x in s[1:-1].split(',') if x.strip()]
    return [s]
