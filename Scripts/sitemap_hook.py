#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
MkDocs post-build hook — 生成 sitemap.xml（博客改造 item 9）

作用：
  - 在 mkdocs build 完成后，扫描 docs_dir 下所有非 hidden 的 .md 文件，
    按 MkDocs 默认目录 URL 规则生成 URL，输出到 site_dir/sitemap.xml。

为什么不直接用 mkdocs-sitemap-plugin？
  - 本环境镜像未提供该插件，且 hook 零依赖、更可控，能自动识别 hidden 页面。
  - 需要站点根 404.md / 标签页 等也出现在 sitemap 里？可以进一步扩展；
    目前行为与标准 sitemap 插件一致：列出所有公开页面。

配置：在 mkdocs.yml 顶层加
  hooks:
    - Scripts/sitemap_hook.py
"""
import os
import re
import xml.etree.ElementTree as ET
from datetime import datetime, timezone


def _is_hidden(path):
    """极简 front matter 解析：是否 hidden: true。"""
    try:
        with open(path, encoding="utf-8") as fh:
            head = fh.read(4096)
    except OSError:
        return False
    if not head.startswith("---"):
        return False
    m = re.match(r"^---\s*\n(.*?)\n---", head, re.DOTALL)
    if not m:
        return False
    return re.search(r"(?m)^\s*hidden\s*:\s*true\b\s*(#.*)?$", m.group(1)) is not None


def _md_to_url(rel):
    """把 docs 下的相对路径转成 MkDocs 默认目录 URL（含 / 结尾）。"""
    rel = rel.replace("\\", "/")
    if rel.endswith(".md"):
        rel = rel[:-3]
    parts = rel.rsplit("/", 1)
    base = parts[0] if len(parts) > 1 else ""
    name = parts[-1]
    if name in ("index", "README"):
        return (base + "/") if base else ""
    return rel + "/"


def on_post_build(config, **kwargs):
    site_url = (config.site_url or "").strip()
    if not site_url:
        print("[sitemap] site_url 未配置，跳过 sitemap.xml 生成")
        return

    site_url = site_url.rstrip("/") + "/"
    docs_dir = config.docs_dir
    site_dir = config.site_dir

    urls = []
    for root, _dirs, files in os.walk(docs_dir):
        for fn in files:
            if not fn.endswith(".md"):
                continue
            full = os.path.join(root, fn)
            if _is_hidden(full):
                continue
            rel = os.path.relpath(full, docs_dir).replace("\\", "/")
            if rel == "404.md":
                continue  # 404 页面不需要出现在 sitemap 中
            urls.append(_md_to_url(rel))

    urls.sort()

    ns = "http://www.sitemaps.org/schemas/sitemap/0.9"
    root = ET.Element("urlset", {"xmlns": ns})
    today = datetime.now(timezone.utc).strftime("%Y-%m-%d")

    for u in urls:
        loc = site_url + u
        url_el = ET.SubElement(root, "url")
        ET.SubElement(url_el, "loc").text = loc
        ET.SubElement(url_el, "lastmod").text = today
        ET.SubElement(url_el, "changefreq").text = "weekly"
        ET.SubElement(url_el, "priority").text = "0.5"

    ET.indent(root, space="  ")
    tree = ET.ElementTree(root)
    sitemap_path = os.path.join(site_dir, "sitemap.xml")
    tree.write(sitemap_path, encoding="utf-8", xml_declaration=True)
    print(f"[sitemap] 已生成 {sitemap_path}，包含 {len(urls)} 个 URL")
