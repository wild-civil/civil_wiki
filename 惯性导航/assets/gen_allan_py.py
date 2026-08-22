#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
gen_allan_py.py — Python 轨：Allan 方差演示（与 MATLAB 轨对照，双实现一致性验证）
用法: python gen_allan_py.py   （需先跑过 gen_allan_matlab.m 生成 allan_matlab.csv）
输出: allan_curve_python.png（对照图，两条曲线 + 数值差异打印）
对应 wiki: 惯性导航/05_Allan方差.md
本脚本是 index.md「PSINS 演示约定」中"Python/NumPy 兜底"的落地：
同一份数据，两套独立实现（PSINS avar vs 本项目 allan.py 同款算法），
曲线重合 + 数值差异极小 => 工具正确性的交叉验证。
"""
import numpy as np
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt

# 中文字体（避免标题变方块）
plt.rcParams['font.sans-serif'] = ['Microsoft YaHei', 'SimHei']
plt.rcParams['axes.unicode_minus'] = False

def allan_dev(omega, dt, taus):
    """本项目 verification/metrics/allan.py 同款算法（log 网格 + 固定簇长）"""
    N = omega.shape[0]
    sig = np.empty(len(taus))
    for ti, tau in enumerate(taus):
        m = max(1, int(round(tau / dt)))
        if m >= N - 1:
            sig[ti] = np.nan; continue
        nclusters = N // m
        if nclusters < 2:
            sig[ti] = np.nan; continue
        c = omega[:nclusters*m].reshape(nclusters, m).mean(axis=1)
        diff = c[1:] - c[:-1]
        sig[ti] = np.sqrt(diff.var() / 2.0)
    return sig

def main():
    # 读 MATLAB 轨生成的同一份数据（原始合成数据 deg/h + PSINS 的 Allan 结果）
    y = np.loadtxt('allan_y.csv')                      # (N,) deg/h —— 同一份数据
    d = np.loadtxt('allan_matlab.csv', delimiter=',')  # (tau, sigma_PSINS)
    tau_psins, sig_psins = d[:,0], d[:,1]
    dt = 0.01

    # 用本项目 allan.py 同款算法重算（输入需 deg/s；此处 y 是 deg/h，先换算）
    sig_py = allan_dev(y / 3600.0, dt, tau_psins)      # 返回 deg/s → 转 deg/h
    sig_py = sig_py * 3600.0

    # 数值对比（公共有限区间）
    mask = np.isfinite(sig_py) & (sig_psins > 0) & (sig_py > 0)
    rel = np.abs(sig_py[mask] - sig_psins[mask]) / sig_psins[mask]
    print(f"# Allan 双实现对照 (N={len(y)}, dt={dt}s, 同一份数据)")
    print(f"# PSINS avar vs 本项目 allan_dev: 公共点数={mask.sum()}")
    print(f"# 相对误差: max={rel.max()*100:.3f}%  mean={rel.mean()*100:.3f}%")

    # 出图
    fig, ax = plt.subplots(figsize=(8.6, 5.2), dpi=130)
    ax.loglog(tau_psins, sig_psins, 'b-',  lw=2, label='PSINS avar (MATLAB)')
    ax.loglog(tau_psins, sig_py,    'r--', lw=1.6, label='allan_dev (Python, 本项目)')
    ax.grid(True, which='both', ls=':', alpha=0.5)
    ax.set_xlabel('$\\tau$ / s'); ax.set_ylabel('$\\sigma_A(\\tau)$ / (deg/h)')
    ax.set_title('Allan 双实现对照：PSINS avar vs 本项目 allan_dev')
    ax.legend(loc='lower right')
    fig.tight_layout()
    fig.savefig('allan_curve_python.png')
    print("# saved allan_curve_python.png")

if __name__ == '__main__':
    main()
