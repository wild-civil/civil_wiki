#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
gen_att_update_py.py — Python 轨：姿态更新方法误差对比（与 MATLAB 轨对照）
用法: python gen_att_update_py.py   （需先跑 gen_att_update.m 生成 att_update_res.csv）
输出: att_update_compare_py.png（同一数据重新绘制 + 数值摘要）
对应 wiki: 惯性导航/02_解算篇/07_姿态更新算法.md
"""
import numpy as np
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt

plt.rcParams['font.sans-serif'] = ['Microsoft YaHei', 'SimHei']
plt.rcParams['axes.unicode_minus'] = False

d = np.loadtxt('att_update_res.csv', delimiter=',')
t = d[:, 0]
res = d[:, 1:]                     # 18 列: 6 方法 x 3 轴, 单位 arcsec
methods = ['1 最优coning', '2 未补偿', '3 四元数RK4', '4 BortzRK4', '5 BortzPicard', '6 DCMTaylor']
clrs = ['b', 'r', 'g', 'm', 'c', 'k']

# 数值摘要: 每方法 x 轴误差的 max|.|（arcsec）
print('# 姿态更新方法对比数值摘要 (x 轴误差 max, arcsec):')
for j in range(6):
    mx = np.max(np.abs(res[:, 3*j]))
    print(f'#   {methods[j]:<14s}: {mx:.4f}')

fig, axes = plt.subplots(1, 3, figsize=(12, 4), dpi=130)
titles = ['x 轴误差 (圆锥运动)', 'y 轴误差', 'z 轴误差']
for ax, ti, axis in zip(axes, titles, range(3)):
    for j in range(6):
        ax.plot(t, res[:, 3*j+axis], clrs[j], lw=1.5)
    ax.grid(True, ls=':', alpha=0.5)
    ax.set_xlabel('t / s'); ax.set_ylabel('误差 / arcsec'); ax.set_title(ti)
axes[0].legend(methods, fontsize=8, loc='best')
fig.tight_layout()
fig.savefig('att_update_compare_py.png')
print('# saved att_update_compare_py.png')
