#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
生成社交分享卡片（Open Graph / Twitter Card 配图）—— 博客改造 item 8

输出：docs/assets/images/social.png  （1200 x 630，符合主流社交平台预览尺寸）

实现说明：
  - 仅依赖 Pillow，不依赖 cairosvg / GTK，跨平台稳定可构建。
  - 中文字体优先使用系统自带 Microsoft YaHei（msyh.ttc），找不到时回退默认字体。
  - 站点名 / 副标题取自 mkdocs.yml 的 site_name / site_description，改站名后重跑即可。

用法：
  python Scripts/make_social_card.py
"""
import os
import re

import yaml
from PIL import Image, ImageDraw, ImageFont

VAULT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DOCS = os.path.join(VAULT, "docs")
MK = os.path.join(VAULT, "mkdocs.yml")
OUT = os.path.join(DOCS, "assets", "images", "social.png")

W, H = 1200, 630

# 候选中文字体（Windows 优先 msyh，macOS 备选）
FONT_CANDIDATES = [
    r"C:\Windows\Fonts\msyh.ttc",
    r"C:\Windows\Fonts\simhei.ttf",
    r"C:\Windows\Fonts\simsun.ttc",
    "/System/Library/Fonts/PingFang.ttc",
    "/usr/share/fonts/truetype/noto/NotoSansCJK-Regular.ttc",
]


def load_font(size, bold=False):
    for path in FONT_CANDIDATES:
        if os.path.isfile(path):
            try:
                return ImageFont.truetype(path, size, index=0)
            except Exception:
                continue
    # 回退：默认字体（可能无法渲染中文，仅兜底）
    return ImageFont.load_default()


def get_site_text():
    with open(MK, encoding="utf-8") as fh:
        text = fh.read()
    text = re.sub(r"!!python/name:", "", text)
    cfg = yaml.safe_load(text)
    name = (cfg.get("site_name") or "我的知识库").strip()
    desc = (cfg.get("site_description") or "").strip()
    return name, desc


def main():
    title, subtitle = get_site_text()

    img = Image.new("RGB", (W, H), (0x15, 0x65, 0xC0))  # Material Blue 800
    draw = ImageDraw.Draw(img)

    # 顶部高亮装饰条
    draw.rectangle([0, 0, W, 14], fill=(0x82, 0xB1, 0xFF))

    # 居中主标题
    title_font = load_font(86, bold=True)
    tb = draw.textbbox((0, 0), title, font=title_font)
    tw = tb[2] - tb[0]
    tx = (W - tw) // 2
    ty = H // 2 - 110
    draw.text((tx, ty), title, fill=(0xFF, 0xFF, 0xFF), font=title_font)

    # 标题下 accent 短横线
    line_w = 120
    draw.rectangle(
        [(W - line_w) // 2, ty + 110, (W + line_w) // 2, ty + 118],
        fill=(0xBB, 0xDE, 0xFB),
    )

    # 副标题
    if subtitle:
        sub_font = load_font(34)
        sb = draw.textbbox((0, 0), subtitle, font=sub_font)
        sw = sb[2] - sb[0]
        draw.text(
            ((W - sw) // 2, ty + 140),
            subtitle,
            fill=(0xE3, 0xF2, 0xFD),
            font=sub_font,
        )

    # 底部留白处的站点域名提示（取自 site_url 占位，增强品牌感）
    hint_font = load_font(24)
    draw.text(
        (W // 2, H - 70),
        "Obsidian Vault · MkDocs Material",
        fill=(0xBB, 0xDE, 0xFB),
        font=hint_font,
        anchor="mm",
    )

    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    img.save(OUT, "PNG")
    print(f"[✓] 社交分享卡片已生成：{OUT}  ({W}x{H})")


if __name__ == "__main__":
    main()
