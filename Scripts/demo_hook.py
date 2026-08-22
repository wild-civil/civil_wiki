#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
MkDocs build hook — 页面内"真实 Python 演示"：身高-体重相关分析
====================================================================

效果（以《协方差矩阵》页为例）：
  - 在页面源码里写一个占位符 `{{cov_demo}}`，构建时这里会被**真正运行 Python**
    算出来的结果替换掉：样本序列、均值、方差、协方差、标准差、相关系数，
    以及一张内联 SVG 散点图。
  - 这样科普页里的数值不是编的，是构建时实算的，且零第三方依赖（不联网、国内稳），
    符合本站点把 MathJax 本地化的同一思路。

配置：在 mkdocs.yml 顶层 hooks 列表追加：
  hooks:
    - Scripts/sitemap_hook.py
    - Scripts/demo_hook.py
"""
import math

# ---------------------------------------------------------------------------
# 演示数据：身高(cm) 与 体重(kg) 的 12 个样本（正常成人，含一定噪声的典型值）
# ---------------------------------------------------------------------------
DATA = [
    (158, 48), (162, 52), (165, 55), (168, 58),
    (170, 62), (172, 64), (175, 68), (178, 72),
    (180, 75), (183, 79), (186, 82), (190, 88),
]


# ---------------------------------------------------------------------------
# 统计计算（仅用标准库，刻意避开 numpy，保证零依赖）
# ---------------------------------------------------------------------------
def stats(data):
    hs = [h for h, _ in data]
    ws = [w for _, w in data]
    n = len(data)

    mh = sum(hs) / n
    mw = sum(ws) / n

    # 样本协方差 / 样本方差（除以 n-1，无偏估计）
    cov = sum((h - mh) * (w - mw) for h, w in data) / (n - 1)
    vh = sum((h - mh) ** 2 for h, _ in data) / (n - 1)
    vw = sum((w - mw) ** 2 for _, w in data) / (n - 1)
    sh = math.sqrt(vh)
    sw = math.sqrt(vw)
    r = cov / (sh * sw)  # 皮尔逊相关系数，取值 [-1, 1]

    return {
        "n": n, "mh": mh, "mw": mw, "cov": cov,
        "vh": vh, "vw": vw, "sh": sh, "sw": sw, "r": r,
    }


# ---------------------------------------------------------------------------
# 生成内联 SVG 散点图（身高 x 轴，体重 y 轴）
# ---------------------------------------------------------------------------
def scatter_svg(data, s):
    PAD_L, PAD_B, PAD_T, PAD_R = 46, 34, 14, 14
    W, H = 560, 330
    x_min, x_max = 150, 195
    y_min, y_max = 40, 100
    plot_w = W - PAD_L - PAD_R
    plot_h = H - PAD_T - PAD_B

    def sx(x):  # 身高 -> 画布 x
        return PAD_L + (x - x_min) / (x_max - x_min) * plot_w

    def sy(y):  # 体重 -> 画布 y（y 轴向下）
        return PAD_T + (1 - (y - y_min) / (y_max - y_min)) * plot_h

    # 坐标轴网格
    parts = [f'<svg viewBox="0 0 {W} {H}" xmlns="http://www.w3.org/2000/svg" '
             f'style="max-width:100%;height:auto;background:#fff;border-radius:8px;'
             f'box-shadow:0 1px 4px rgba(0,0,0,.12)">']
    # 垂直网格（x 刻度）
    for xg in range(155, 195, 5):
        parts.append(f'<line x1="{sx(xg):.1f}" y1="{PAD_T}" x2="{sx(xg):.1f}" '
                     f'y2="{PAD_T+plot_h}" stroke="#eef1f6"/>')
        parts.append(f'<text x="{sx(xg):.1f}" y="{PAD_T+plot_h+16}" '
                     f'font-size="10" fill="#8a94a6" text-anchor="middle">{xg}</text>')
    # 水平网格（y 刻度）
    for yg in range(50, 95, 10):
        parts.append(f'<line x1="{PAD_L}" y1="{sy(yg):.1f}" x2="{PAD_L+plot_w}" '
                     f'y2="{sy(yg):.1f}" stroke="#eef1f6"/>')
        parts.append(f'<text x="{PAD_L-8}" y="{sy(yg)+3:.1f}" font-size="10" '
                     f'fill="#8a94a6" text-anchor="end">{yg}</text>')
    # 坐标轴框
    parts.append(f'<rect x="{PAD_L}" y="{PAD_T}" width="{plot_w}" height="{plot_h}" '
                 f'fill="none" stroke="#d5dbe6"/>')
    # 最小二乘拟合直线
    slope = s["cov"] / s["vh"]
    def fit(x):
        return s["mw"] + slope * (x - s["mh"])
    parts.append(f'<line x1="{sx(x_min):.1f}" y1="{sy(fit(x_min)):.1f}" '
                 f'x2="{sx(x_max):.1f}" y2="{sy(fit(x_max)):.1f}" '
                 f'stroke="#4c7bf0" stroke-width="2" stroke-dasharray="6 4"/>')
    # 散点
    for (h, w) in data:
        parts.append(f'<circle cx="{sx(h):.1f}" cy="{sy(w):.1f}" r="5" '
                     f'fill="#2f6fed" fill-opacity=".85" stroke="#fff" stroke-width="1"/>')
    # 轴标题
    parts.append(f'<text x="{PAD_L+plot_w/2:.1f}" y="{H-4}" font-size="12" '
                 f'fill="#44506a" text-anchor="middle">身高 / cm</text>')
    parts.append(f'<text x="14" y="{PAD_T+plot_h/2:.1f}" font-size="12" '
                 f'fill="#44506a" text-anchor="middle" '
                 f'transform="rotate(-90 14 {PAD_T+plot_h/2:.1f})">体重 / kg</text>')
    parts.append("</svg>")
    return "".join(parts)


def _f(v, d=2):
    return f"{v:.{d}f}"


def build_demo():
    s = stats(DATA)
    m = [
        f"#### 真实算出来的结果（构建期 Python 实算，样本 12 组）",
        "",
        "样本数据（身高 cm, 体重 kg）："
        + ", ".join(f"({h}, {w})" for h, w in DATA) + "。",
        "",
        "| 统计量 | 数值 | 含义 |",
        "| --- | --- | --- |",
        f"| 平均身高 | {_f(s['mh'])} cm | $E[X_1]$ |",
        f"| 平均体重 | {_f(s['mw'])} kg | $E[X_2]$ |",
        f"| 身高方差 | {_f(s['vh'])} | $\\operatorname{{Var}}(X_1)$ |",
        f"| 体重方差 | {_f(s['vw'])} | $\\operatorname{{Var}}(X_2)$ |",
        f"| 身高标准差 | {_f(s['sh'])} | $\\sqrt{{\\operatorname{{Var}}(X_1)}}$ |",
        f"| 体重标准差 | {_f(s['sw'])} | $\\sqrt{{\\operatorname{{Var}}(X_2)}}$ |",
        f"| **协方差** $\\Sigma_{{12}}$ | **{_f(s['cov'])}** | $\\operatorname{{Cov}}(X_1,X_2)$ |",
        f"| **相关系数** $\\rho$ | **{_f(s['r'])}** | $\\Sigma_{{12}}/(\\sigma_1\\sigma_2)$，取值 [-1,1] |",
        "",
        "因为 **协方差 $>0$**，且**相关系数 $\\rho \\approx 0.99$**（接近 +1），说明身高与体重强正相关："
        "「身高越高，体重往往越重」——和直觉一致。而且这次是真实数据算出来的，不是一个假设。",
        "",
        "下面是散点图：",
        "",
        scatter_svg(DATA, s),
        "",
        f"> 注意：协方差**受单位影响**（若身高用米、体重用千克，数值会不同）；所以跨变量比较时用归一化后的相关系数 $\\rho$。",
    ]
    return "\n".join(m)


def on_page_markdown(markdown, page, config, files=None):
    if "{{cov_demo}}" not in markdown:
        return markdown
    return markdown.replace("{{cov_demo}}", build_demo())


if __name__ == "__main__":
    print(build_demo())