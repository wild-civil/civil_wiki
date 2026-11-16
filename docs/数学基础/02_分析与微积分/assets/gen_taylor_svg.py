# -*- coding: utf-8 -*-
"""生成 03_泰勒展开与小角度近似.md 的三张配图。

曲线一律由数值计算生成 polyline（不手绘）。运行：
    python gen_taylor_svg.py
输出与本脚本同目录的三个 .svg。
"""
import math
import os

OUT = os.path.dirname(os.path.abspath(__file__))
FONT = "'Segoe UI','Microsoft YaHei','PingFang SC',Arial,sans-serif"

INK = "#202124"
GREY = "#5f6368"
LINE = "#9aa0a6"
GRID = "#e8eaed"
BLACK = "#202124"
RED = "#d93025"
BLUE = "#1a73e8"
GREEN = "#188038"


def head(w, h, title, desc):
    return (
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 %d %d" '
        'width="%d" height="%d" font-family="%s" role="img">\n'
        '<title>%s</title>\n<desc>%s</desc>\n'
        '<style>\n'
        '.ttl{font-size:18px;font-weight:700;fill:%s}\n'
        '.sub{font-size:12.5px;fill:%s}\n'
        '.ax{stroke:%s;stroke-width:1.2}\n'
        '.grid{stroke:%s;stroke-width:1}\n'
        '.lb{font-size:13px;fill:%s}\n'
        '.sm{font-size:12px;fill:%s}\n'
        '.num{font-size:11px;fill:#80868b}\n'
        '.box{fill:#f8f9fa;stroke:#dadce0;stroke-width:1}\n'
        '</style>\n'
        '<rect width="%d" height="%d" fill="#ffffff"/>\n'
        % (w, h, w, h, FONT, title, desc, INK, GREY, LINE, GRID, INK, GREY, w, h)
    )


def txt(x, y, s, cls="lb", anchor="start", extra=""):
    return '<text class="%s" x="%.1f" y="%.1f" text-anchor="%s" %s>%s</text>\n' % (
        cls, x, y, anchor, extra, s)


def polyline(points, color, width, dash="", clip=None):
    cp = ' clip-path="url(#%s)"' % clip if clip else ""
    da = ' stroke-dasharray="%s"' % dash if dash else ""
    return '<polyline points="%s" fill="none" stroke="%s" stroke-width="%s"%s%s/>\n' % (
        " ".join("%.1f,%.1f" % p for p in points), color, width, da, cp)


def save(name, body):
    path = os.path.join(OUT, name)
    with open(path, "w", encoding="utf-8") as f:
        f.write(body)
    print("wrote", name, os.path.getsize(path), "bytes")


# ---------------------------------------------------------------- 图 1
def fig1():
    W, H = 760, 430
    L, R, T, B = 64, 28, 68, 76
    x0, x1, y0, y1 = -3.5, 3.5, -1.6, 1.6

    def px(x):
        return L + (x - x0) / (x1 - x0) * (W - L - R)

    def py(y):
        return T + (y1 - y) / (y1 - y0) * (H - T - B)

    s = [head(W, H, "多项式逐阶逼近正弦函数",
              "sin x 真值与一阶、三阶、五阶泰勒多项式在原点附近的对比。")]
    s.append(txt(W / 2, 30, "逐阶模仿：项数越多，跟得越远", "ttl", "middle"))
    s.append(txt(W / 2, 51, "所有曲线在 x = 0 处相切，区别只在离开原点之后拐得多快", "sub", "middle"))
    s.append('<defs><clipPath id="plot"><rect x="%d" y="%d" width="%d" height="%d"/></clipPath></defs>\n'
             % (L, T, W - L - R, H - T - B))

    for xv in (-3, -2, -1, 1, 2, 3):
        s.append('<line class="grid" x1="%.1f" y1="%d" x2="%.1f" y2="%d"/>\n'
                 % (px(xv), T, px(xv), H - B))
        s.append(txt(px(xv), H - B + 18, str(xv), "num", "middle"))
    for yv in (-1, -0.5, 0.5, 1):
        s.append('<line class="grid" x1="%d" y1="%.1f" x2="%d" y2="%.1f"/>\n'
                 % (L, py(yv), W - R, py(yv)))
        s.append(txt(L - 10, py(yv) + 4, str(yv), "num", "end"))

    s.append('<line class="ax" x1="%d" y1="%.1f" x2="%d" y2="%.1f"/>\n'
             % (L, py(0), W - R, py(0)))
    s.append('<line class="ax" x1="%.1f" y1="%d" x2="%.1f" y2="%d"/>\n'
             % (px(0), T, px(0), H - B))
    s.append(txt(W - R - 4, py(0) - 8, "x", "sm", "end"))
    s.append(txt(px(0) + 8, T + 14, "y", "sm"))

    def series(fn):
        pts = []
        for i in range(561):
            x = x0 + (x1 - x0) * i / 560
            y = fn(x)
            if -4.0 < y < 4.0:
                pts.append((px(x), py(y)))
            else:
                pts.append(None)
        # 把超出画面太多的点断开，避免 polyline 拉出长斜线
        segs, cur = [], []
        for p in pts:
            if p is None:
                if len(cur) > 1:
                    segs.append(cur)
                cur = []
            else:
                cur.append(p)
        if len(cur) > 1:
            segs.append(cur)
        return segs

    specs = [
        (lambda x: x, RED, 2.0, ""),
        (lambda x: x - x ** 3 / 6 + x ** 5 / 120, GREEN, 2.0, "7 5"),
        (lambda x: x - x ** 3 / 6, BLUE, 2.4, ""),
        (math.sin, BLACK, 3.2, ""),
    ]
    for fn, col, wd, dash in specs:
        for seg in series(fn):
            s.append(polyline(seg, col, wd, dash, "plot"))

    # 原点标记 + 图例
    s.append('<circle cx="%.1f" cy="%.1f" r="3.5" fill="%s"/>\n' % (px(0), py(0), INK))
    s.append(txt(px(0) + 10, py(0) + 18, "展开点 x = 0", "sm"))

    items = [
        (BLACK, "sin x（真值）"),
        (RED, "P₁ = x"),
        (BLUE, "P₃ = x − x³/6"),
        (GREEN, "P₅ = P₃ + x⁵/120"),
    ]
    lx = L
    ly = H - 22
    for col, label in items:
        s.append('<line x1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f" stroke="%s" stroke-width="3"/>\n'
                 % (lx, ly - 4, lx + 26, ly - 4, col))
        s.append(txt(lx + 32, ly, label, "sm"))
        lx += 172
    save("泰勒展开_逐阶逼近正弦.svg", "".join(s) + "</svg>\n")


# ---------------------------------------------------------------- 图 2
def fig2():
    W, H = 760, 420
    s = [head(W, H, "小角度近似的单位圆几何",
              "单位圆中弧长 theta、sin theta 与 1-cos theta 的几何关系，以及 0.1 弧度时的数值对照。")]
    s.append(txt(W / 2, 30, "单位圆里看清楚：谁是一阶，谁是二阶", "ttl", "middle"))
    s.append(txt(W / 2, 51, "几何图把角度放大到 0.45 rad 便于观察；右侧数值按 θ = 0.1 rad 计算", "sub", "middle"))

    cx, cy, rad = 218, 330, 205
    th = 0.45
    P = (cx + rad * math.cos(th), cy - rad * math.sin(th))
    A = (cx + rad, cy)

    # 坐标轴与 1/4 圆弧
    s.append('<line class="ax" x1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f"/>\n'
             % (cx - 18, cy, A[0] + 26, cy))
    s.append('<line class="ax" x1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f"/>\n'
             % (cx, cy + 16, cx, cy - rad - 20))
    s.append('<path d="M %.1f %.1f A %d %d 0 0 0 %.1f %.1f" fill="none" stroke="%s" stroke-width="1.6"/>\n'
             % (A[0], A[1], rad, rad, cx, cy - rad, LINE))
    # 两条半径
    s.append('<line x1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f" stroke="%s" stroke-width="2"/>\n'
             % (cx, cy, A[0], A[1], GREY))
    s.append('<line x1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f" stroke="%s" stroke-width="2.2"/>\n'
             % (cx, cy, P[0], P[1], BLUE))
    # 弧长 theta 加粗
    s.append('<path d="M %.1f %.1f A %d %d 0 0 0 %.1f %.1f" fill="none" stroke="%s" stroke-width="4"/>\n'
             % (A[0], A[1], rad, rad, P[0], P[1], RED))
    # sin 竖线
    s.append('<line x1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f" stroke="%s" stroke-width="3"/>\n'
             % (P[0], P[1], P[0], cy, GREEN))
    # cos 水平段
    s.append('<line x1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f" stroke="%s" stroke-width="3"/>\n'
             % (cx, cy - 6, P[0], cy - 6, BLUE))
    # 1-cos 间隙
    s.append('<line x1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f" stroke="%s" stroke-width="4"/>\n'
             % (P[0], cy + 6, A[0], cy + 6, RED))
    s.append('<circle cx="%.1f" cy="%.1f" r="4" fill="%s"/>\n' % (P[0], P[1], INK))
    s.append('<circle cx="%.1f" cy="%.1f" r="3" fill="%s"/>\n' % (cx, cy, INK))

    # 标签
    s.append(txt(cx - 16, cy + 22, "O", "sm", "end"))
    s.append(txt(cx + 48, cy - 20, "θ", "lb", "start", 'fill="%s"' % RED))
    s.append(txt((cx + P[0]) / 2, cy - 14, "cos θ", "sm", "middle", 'fill="%s"' % BLUE))
    s.append(txt(P[0] + 10, (P[1] + cy) / 2 + 4, "sin θ", "sm", "start", 'fill="%s"' % GREEN))
    s.append(txt((P[0] + A[0]) / 2, cy + 26, "1 − cos θ", "sm", "middle", 'fill="%s"' % RED))
    s.append(txt(A[0] + 8, cy - 12, "A", "sm"))
    s.append(txt(34, 88, "P = (cos θ, sin θ)", "sm"))
    s.append(txt(34, 108, "红色粗弧 = 弧长 θ（弧度定义）", "sm"))
    s.append(txt(34, 128, "绿线 = sin θ，蓝线 = cos θ", "sm"))

    # 右侧数值卡
    bx, by, bw, bh = 468, 84, 264, 278
    s.append('<rect class="box" x="%d" y="%d" width="%d" height="%d" rx="10"/>\n' % (bx, by, bw, bh))
    s.append(txt(bx + 18, by + 30, "θ = 0.1 rad 时的三条长度", "lb", extra='font-weight="700"'))
    rows = [
        ("弧长  θ", "0.100000", RED),
        ("sin θ", "0.099833", GREEN),
        ("1 − cos θ", "0.004996", RED),
    ]
    yy = by + 68
    for name, val, col in rows:
        s.append(txt(bx + 20, yy, name, "sm"))
        s.append(txt(bx + bw - 20, yy, val, "lb", "end", 'fill="%s" font-weight="700"' % col))
        s.append('<line x1="%d" y1="%.1f" x2="%d" y2="%.1f" stroke="%s" stroke-width="1"/>\n'
                 % (bx + 18, yy + 9, bx + bw - 18, yy + 9, GRID))
        yy += 40
    s.append(txt(bx + 20, by + 200, "sin θ 与 θ 只差 0.17% → 一阶", "sm"))
    s.append(txt(bx + 20, by + 222, "1 − cos θ ≈ θ²/2 → 二阶小量", "sm"))
    s.append(txt(bx + 20, by + 250, "所以 sin θ ≈ θ，cos θ ≈ 1", "lb",
                 extra='fill="%s" font-weight="700"' % BLUE))
    s.append(txt(W / 2, H - 14, "θ 越小，弦与弧越贴合；丢掉 sin θ 的一阶项，等于把这段竖直变化抹成 0", "sub", "middle"))
    save("小角度_单位圆几何.svg", "".join(s) + "</svg>\n")


# ---------------------------------------------------------------- 图 3
def fig3():
    W, H = 760, 410
    L, R, T, B = 74, 28, 68, 72
    x0, x1, y0, y1 = 0.0, 0.5, 0.0, 0.52

    def px(x):
        return L + (x - x0) / (x1 - x0) * (W - L - R)

    def py(y):
        return T + (y1 - y) / (y1 - y0) * (H - T - B)

    s = [head(W, H, "三种小角度近似的绝对误差对比",
              "零阶近似 sin theta 约为 0 的误差是一阶，cos theta 约为 1 是二阶，sin theta 约为 theta 是三阶。")]
    s.append(txt(W / 2, 30, "一阶 vs 二阶 vs 三阶：误差塌向 0 的速度差多少", "ttl", "middle"))
    s.append(txt(W / 2, 51, "纵轴为绝对误差，横轴为 θ（弧度）；三条曲线的「阶数」决定谁先贴到 0", "sub", "middle"))

    for xv in (0.1, 0.2, 0.3, 0.4, 0.5):
        s.append('<line class="grid" x1="%.1f" y1="%d" x2="%.1f" y2="%d"/>\n'
                 % (px(xv), T, px(xv), H - B))
        s.append(txt(px(xv), H - B + 18, "%.1f" % xv, "num", "middle"))
    for yv in (0.1, 0.2, 0.3, 0.4, 0.5):
        s.append('<line class="grid" x1="%d" y1="%.1f" x2="%d" y2="%.1f"/>\n'
                 % (L, py(yv), W - R, py(yv)))
        s.append(txt(L - 10, py(yv) + 4, "%.1f" % yv, "num", "end"))
    s.append('<line class="ax" x1="%d" y1="%.1f" x2="%d" y2="%.1f"/>\n'
             % (L, py(0), W - R, py(0)))
    s.append('<line class="ax" x1="%d" y1="%d" x2="%d" y2="%d"/>\n'
             % (L, T, L, H - B))
    s.append(txt(L + 40, H - B + 36, "θ / rad", "sm"))
    s.append(txt(L - 56, T - 10, "绝对误差", "sm"))

    def curve(fn, col, wd):
        pts = [(px(x0 + (x1 - x0) * i / 400), py(fn(x0 + (x1 - x0) * i / 400)))
               for i in range(401)]
        s.append(polyline(pts, col, wd))

    curve(lambda x: math.sin(x), RED, 2.8)
    curve(lambda x: 1 - math.cos(x), GREEN, 2.8)
    curve(lambda x: x - math.sin(x), BLUE, 2.8)

    # θ = 0.1 参考竖线 + 三个标记点
    s.append('<line x1="%.1f" y1="%d" x2="%.1f" y2="%d" stroke="%s" stroke-width="1.2" stroke-dasharray="4 4"/>\n'
             % (px(0.1), T, px(0.1), H - B, LINE))
    s.append(txt(px(0.1) + 6, T + 16, "θ = 0.1", "sm"))
    for val, col in ((math.sin(0.1), RED), (1 - math.cos(0.1), GREEN), (0.1 - math.sin(0.1), BLUE)):
        s.append('<circle cx="%.1f" cy="%.1f" r="4" fill="%s"/>\n' % (px(0.1), py(val), col))

    # 左上图例卡（该区域三条曲线都很低，不会遮挡）
    bx, by, bw, bh = 96, 92, 372, 118
    s.append('<rect class="box" x="%d" y="%d" width="%d" height="%d" rx="10"/>\n' % (bx, by, bw, bh))
    legend = [
        (RED, "sin θ ≈ 0", "误差 ~ θ（一阶）· 0.1 时 9.98e−2"),
        (GREEN, "cos θ ≈ 1", "误差 ~ θ²/2（二阶）· 0.1 时 5.00e−3"),
        (BLUE, "sin θ ≈ θ", "误差 ~ θ³/6（三阶）· 0.1 时 1.67e−4"),
    ]
    yy = by + 28
    for col, name, note in legend:
        s.append('<line x1="%d" y1="%.1f" x2="%d" y2="%.1f" stroke="%s" stroke-width="3"/>\n'
                 % (bx + 16, yy - 4, bx + 40, yy - 4, col))
        s.append(txt(bx + 48, yy, name, "sm", extra='font-weight="700" fill="%s"' % col))
        s.append(txt(bx + 148, yy, note, "sm"))
        yy += 32

    s.append(txt(W / 2, H - 16, "θ 缩小 10 倍：一阶误差缩小 10 倍，二阶 100 倍，三阶 1000 倍", "sub", "middle"))
    save("小角度_误差量级对比.svg", "".join(s) + "</svg>\n")


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    fig1()
    fig2()
    fig3()
