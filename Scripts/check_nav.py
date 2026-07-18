#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
导航校验脚本（博客改造 item 7）

作用：
  1. 解析 mkdocs.yml 的 nav 配置，逐个检查其中引用的 .md 文件是否真实存在；
  2. 扫描 docs/ 下全部 .md，列出「未被导航引用」的文件，并自动识别其中
     通过 front matter `hidden: true` 故意隐藏的页面（预期内，不报警）；
  3. 发现缺失文件时以非 0 退出码结束，方便接入 CI / 提交前检查。

用法：
  python Scripts/check_nav.py            # 常规校验
  python Scripts/check_nav.py --strict   # 把「未引用且非 hidden」也当作错误（零遗漏模式）

依赖：仅 PyYAML（mkdocs 已自带，无需额外安装）。
"""
import os
import re
import sys

import yaml

VAULT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DOCS = os.path.join(VAULT, "docs")
MK = os.path.join(VAULT, "mkdocs.yml")

# 这些协议开头的 nav 条目视为外链，跳过文件存在性检查
EXTERNAL_PREFIXES = ("http://", "https://", "mailto:", "//")

# MkDocs 会自动识别的特例页面（无需写进 nav），避免被误报为「遗漏文件」
KNOWN_EXCEPTIONS = {os.path.normpath(os.path.join(DOCS, "404.md"))}


def collect_nav_paths(nav, acc):
    """递归收集 nav 里所有指向本地文件的字符串路径。"""
    for item in nav:
        if isinstance(item, str):
            acc.append(item)
        elif isinstance(item, dict):
            for _key, value in item.items():
                if isinstance(value, str):
                    acc.append(value)
                elif isinstance(value, list):
                    collect_nav_paths(value, acc)
    return acc


def is_hidden(md_path):
    """极简 front matter 解析：判断文件是否 hidden: true。"""
    try:
        with open(md_path, encoding="utf-8") as fh:
            head = fh.read(4096)
    except OSError:
        return False
    if not head.startswith("---"):
        return False
    # 取第一个 --- 块
    m = re.match(r"^---\s*\n(.*?)\n---", head, re.DOTALL)
    if not m:
        return False
    body = m.group(1)
    # 允许行尾带注释，如 `hidden: true   # 说明`
    return re.search(r"(?m)^\s*hidden\s*:\s*true\b\s*(#.*)?$", body) is not None


def main():
    strict = "--strict" in sys.argv[1:]

    if not os.path.isfile(MK):
        print(f"[错误] 找不到 mkdocs.yml：{MK}")
        return 2
    with open(MK, encoding="utf-8") as fh:
        text = fh.read()
    # mkdocs.yml 里可能含 PyYAML 私有标签（如 mermaid fence 的
    # `!!python/name:pymdownx.superfences.fence_code_format`），safe_load 无法解析。
    # 本脚本只取 nav 结构，将其脱敏为普通字符串即可，无需解析为真实对象。
    text = re.sub(r"!!python/name:", "", text)
    cfg = yaml.safe_load(text)

    nav = cfg.get("nav", [])
    paths = collect_nav_paths(nav, [])

    errors = []
    referenced = set()
    for p in paths:
        if p.startswith(EXTERNAL_PREFIXES):
            continue
        full = os.path.normpath(os.path.join(DOCS, p))
        if not os.path.isfile(full):
            errors.append(p)
        else:
            referenced.add(full)

    # 扫描全部本地 md，找出孤儿（未被 nav 引用）
    all_md = set()
    for root, _dirs, files in os.walk(DOCS):
        for fn in files:
            if fn.endswith(".md"):
                all_md.add(os.path.normpath(os.path.join(root, fn)))

    orphans = sorted(all_md - referenced)
    hidden_orphans = [o for o in orphans if is_hidden(o)]
    real_orphans = [
        o for o in orphans
        if not is_hidden(o) and o not in KNOWN_EXCEPTIONS
    ]

    print("=" * 56)
    print("  导航文件校验  ·  check_nav.py")
    print("=" * 56)

    if errors:
        print(f"\n[✗] 导航引用了 {len(errors)} 个不存在的文件：")
        for e in errors:
            print(f"    - {e}")
    else:
        print(f"\n[✓] 导航引用的 {len(referenced)} 个本地文件全部存在。")

    print(f"\n[ℹ] 未被导航引用但故意隐藏（hidden:true）的页面 {len(hidden_orphans)} 个：")
    for o in hidden_orphans:
        print(f"    - {os.path.relpath(o, DOCS)}")

    if real_orphans:
        print(f"\n[!] 未被导航引用且非隐藏的 Markdown 文件 {len(real_orphans)} 个：")
        for o in real_orphans:
            print(f"    - {os.path.relpath(o, DOCS)}")
    else:
        print("\n[✓] 没有遗漏的（非隐藏）Markdown 文件。")

    print("\n" + "=" * 56)

    # 退出码判定
    if errors:
        print("结果：FAIL（导航存在失效链接）")
        return 1
    if strict and real_orphans:
        print("结果：FAIL（strict 模式：存在未纳入导航的文件）")
        return 1
    print("结果：PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())
