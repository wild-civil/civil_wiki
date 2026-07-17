#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
知识库自动分类脚本
==================

扫描所有 Inbox/ 里的 Markdown 笔记，按关键词命中数把笔记归类到对应领域，
并把结果写入笔记 frontmatter 的 `category` 与 `tags`。

用法：
    python Scripts/classify.py

说明：
    - 已带 `category` 且属于已知领域的笔记会被跳过（不重复搬运）。
    - 至少需要命中 1 个关键词才会归类；否则留在原 Inbox 等手动处理。
    - 想新增/调整领域，改下面的 DOMAINS 即可（并新建同名文件夹）。
"""

import os
import re
import shutil

# ---------------------------------------------------------------------------
# 配置：领域 -> 关键词
# ---------------------------------------------------------------------------
DOMAINS = {
    "工作与项目": {
        "tag": "工作",
        "keywords": [
            "工作", "项目", "会议", "周报", "月报", "日报", "需求", "客户",
            "甲方", "乙方", "汇报", "排期", "里程碑", "复盘", "OKR", "KPI",
            "任务", "迭代", "sprint", "PRD", "需求评审", "立项", "交付",
            "团队", "绩效", "述职", "协作",
        ],
    },
    "技术与编程": {
        "tag": "技术",
        "keywords": [
            "代码", "编程", "程序", "算法", "前端", "后端", "全栈", "数据库",
            "SQL", "Python", "python", "Java", "java", "JavaScript", "js",
            "Go", "golang", "C++", "部署", "服务器", "API", "接口", "bug",
            "Bug", "调试", "debug", "Git", "git", "框架", "配置", "开发",
            "运维", "Docker", "docker", "Kubernetes", "k8s", "Linux", "linux",
            "终端", "命令行", "脚本", "函数", "类", "数据结构", "网络",
            "React", "Vue", "Node", "测试", "架构", "云服务", "模型", "AI",
            "大模型", "prompt", "Prompt", "正则", "缓存", "并发", "性能",
        ],
    },
    "阅读与学习": {
        "tag": "阅读",
        "keywords": [
            "读书", "阅读", "书评", "读后感", "读书笔记", "课程", "学习",
            "文章", "摘录", "观点", "知识点", "总结", "干货", "笔记", "课堂",
            "讲座", "教程", "mooc", "kindle", "电子书", "摘抄", "金句", "思考",
        ],
    },
    "生活与兴趣": {
        "tag": "生活",
        "keywords": [
            "旅行", "旅游", "游记", "美食", "菜谱", "做饭", "电影", "音乐",
            "歌曲", "爱好", "灵感", "生活", "日常", "兴趣", "健身", "摄影",
            "游戏", "动漫", "穿搭", "家居", "宠物", "植物", "咖啡", "茶",
            "手工", "绘画", "运动", "健康生活", "记录",
        ],
    },
}

VAULT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CONTENT = os.path.join(VAULT, "docs")  # MkDocs 文档源（笔记实际所在目录）
THRESHOLD = 1  # 至少命中几个关键词才归类


# ---------------------------------------------------------------------------
# 极简 frontmatter 解析（仅处理本项目用到的标量 / 列表，无需第三方库）
# ---------------------------------------------------------------------------
def parse_frontmatter(content):
    """返回 (frontmatter文本 或 None, 正文)"""
    m = re.match(r"^---\n(.*?)\n---\n?(.*)$", content, re.DOTALL)
    if m:
        return m.group(1), m.group(2)
    return None, content


def parse_fm(fm_text):
    data = {}
    lines = fm_text.split("\n")
    i = 0
    while i < len(lines):
        line = lines[i]
        if not line.strip() or line.lstrip().startswith("#"):
            i += 1
            continue
        if ":" in line:
            key, _, val = line.partition(":")
            key = key.strip()
            val = val.strip()
            if val in ("", "|"):
                items = []
                j = i + 1
                while j < len(lines) and (
                    lines[j].startswith("  - ") or lines[j].startswith("  * ")
                ):
                    items.append(lines[j].strip()[2:].strip())
                    j += 1
                data[key] = items
                i = j
                continue
            if val.startswith("[") and val.endswith("]"):
                inner = val[1:-1].strip()
                items = [x.strip().strip('"').strip("'") for x in inner.split(",") if x.strip()]
                data[key] = items
            else:
                data[key] = val.strip('"').strip("'")
        i += 1
    return data


def dump_fm(data):
    lines = []
    for k, v in data.items():
        if isinstance(v, list):
            if not v:
                lines.append(f"{k}: []")
            elif len(v) == 1:
                lines.append(f"{k}: [{v[0]}]")
            else:
                lines.append(f"{k}:")
                for item in v:
                    lines.append(f"  - {item}")
        else:
            lines.append(f"{k}: {v}")
    return "\n".join(lines)


# ---------------------------------------------------------------------------
# 分类逻辑
# ---------------------------------------------------------------------------
def derive_title(filename, body):
    base = filename[:-3] if filename.endswith(".md") else filename
    base = base.replace("-", " ").replace("_", " ")
    m = re.search(r"^#\s+(.+)$", body, re.MULTILINE)
    if m:
        return m.group(1).strip()
    return base


def classify(title, body):
    text = (title + "\n" + title + "\n" + body)  # 标题权重加倍
    scores = {}
    for domain, info in DOMAINS.items():
        s = 0
        for kw in info["keywords"]:
            c = text.count(kw)
            if c:
                s += c
        scores[domain] = s
    best = max(scores, key=scores.get)
    return best if scores[best] >= THRESHOLD else None


def unique_path(dest_dir, filename):
    dest = os.path.join(dest_dir, filename)
    if not os.path.exists(dest):
        return dest
    base, ext = os.path.splitext(filename)
    i = 1
    while os.path.exists(os.path.join(dest_dir, f"{base}_{i}{ext}")):
        i += 1
    return os.path.join(dest_dir, f"{base}_{i}{ext}")


# ---------------------------------------------------------------------------
# 主流程
# ---------------------------------------------------------------------------
def main():
    inbox_dirs = [os.path.join(CONTENT, "Inbox")] + [
        os.path.join(CONTENT, d, "Inbox") for d in DOMAINS
    ]
    moved, skipped, unclassified = [], [], []

    print(f"知识库路径：{CONTENT}\n扫描收件箱：")
    for inbox in inbox_dirs:
        print(f"  - {os.path.relpath(inbox, CONTENT)}")
    print("-" * 50)

    for inbox in inbox_dirs:
        if not os.path.isdir(inbox):
            continue
        for fn in sorted(os.listdir(inbox)):
            if not fn.endswith(".md") or fn.startswith("."):
                continue
            src = os.path.join(inbox, fn)
            if os.path.isdir(src):
                continue

            with open(src, encoding="utf-8") as f:
                content = f.read().replace("\r\n", "\n")

            fm_text, body = parse_frontmatter(content)
            meta = parse_fm(fm_text) if fm_text is not None else {}

            # 已经带 category 的（含收件箱指南/已手动归类）一律跳过，不重复搬运
            if meta.get("category"):
                skipped.append((fn, meta["category"]))
                continue

            title = derive_title(fn, body)
            domain = classify(title, body)
            if domain is None:
                unclassified.append(fn)
                continue

            dest_dir = os.path.join(CONTENT, domain)
            dest = unique_path(dest_dir, fn)
            shutil.move(src, dest)

            meta["category"] = domain
            tag = DOMAINS[domain]["tag"]
            tags = meta.get("tags", [])
            if isinstance(tags, str):
                tags = [tags]
            if tag not in tags:
                tags.append(tag)
            meta["tags"] = tags

            new_fm = dump_fm(meta)
            new_content = "---\n" + new_fm + "\n---\n" + body
            with open(dest, "w", encoding="utf-8") as f:
                f.write(new_content)

            moved.append((fn, domain))

    # 报告
    print(f"✅ 已归类：{len(moved)} 篇")
    for fn, d in moved:
        print(f"   {fn}  ->  {d}/")
    if skipped:
        print(f"\n⏭  已跳过（已有分类）：{len(skipped)} 篇")
        for fn, d in skipped:
            print(f"   {fn}  ({d})")
    if unclassified:
        print(f"\n❓ 未匹配，留在原处：{len(unclassified)} 篇")
        for fn in unclassified:
            print(f"   {fn}")
    if not moved and not unclassified and not skipped:
        print("（收件箱为空，无需处理）")
    print("-" * 50)


if __name__ == "__main__":
    main()
