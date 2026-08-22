#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
多传感器冗余 + FDI 演示（纯 numpy，与 gen_fdi.m 双轨）
=====================================================
三个演示，对应 15 篇三个核心论断：
  1) 一路 IMU 故障时：单路 / 均值 / 中值 的误差对比
     -> 中值天然剔除离群（无故障时略逊均值，有故障时完胜）
  2) 2oo3 表决：三路两两残差矩阵，故障路被"少数服从多数"隔离
  3) NIS 门限捕获缓变漂移：慢漂移让 NIS 单调上升，越过 χ² 门限触发告警
     （14 篇的 NIS 从"体检"升级为"在线故障检测"）
确定性演示（无随机），两轨逐数字一致。
"""
import numpy as np

print("=" * 70)
print("多传感器冗余 + FDI：中值表决 / 2oo3 / NIS 漂移检测（纯 numpy / 纯 MATLAB 双轨）")
print("=" * 70)

# ---------- 1) 单路 / 均值 / 中值 对比 ----------
print("\n[1] 一路故障时怎么融合？（真实角速度 w_true = 100.0 °/s，无噪声确定性）")
w_true = 100.0
w = np.array([100.0, 120.0, 100.1])   # 路 2 = 故障（+20% 刻度误差）
err_single = abs(w[1] - w_true)                # 单路：拿故障路
err_mean   = abs(w.mean() - w_true)            # 均值：被故障路拉偏
err_med    = abs(np.median(w) - w_true)        # 中值：取排序中间值 100.1
print(f"   三路读数: {w}  (路2 故障: +20%)")
print(f"   单路(选路2): 误差 {err_single:5.1f} °/s  ->  ✗ 最差")
print(f"   均值:        {w.mean():6.2f} °/s, 误差 {err_mean:5.1f} °/s  ->  ✗ 被污染 (6.7%)")
print(f"   中值:        {np.median(w):6.2f} °/s, 误差 {err_med:5.1f} °/s  ->  ✓ 最稳 (0.1%)")
print("   -> 一路故障下：中值 ≈ 正常值，均值被拉偏，单路可能全错。")

# ---------- 2) 2oo3 表决（残差矩阵） ----------
print("\n[2] 2oo3 表决：三路两两残差，多数票隔离故障路")
eps = 0.5   # 残差门限：|wi - wj| > eps 记为不一致
d = np.abs(w[:, None] - w[None, :])          # 3x3 两两差矩阵
vote = d > eps
print(f"   两两残差矩阵 (°/s):\n{d}")
print(f"   不一致矩阵 (> {eps} °/s):\n{vote.astype(int)}")
for i in range(3):
    bad = vote[i].sum()                       # 路 i 与其他几路不一致的票数
    tag = "故障 ✗ 隔离" if bad >= 2 else ("正常 ✓" if bad == 0 else "可疑 ?")
    print(f"   路{i+1}: 不一致票数 = {bad}  ->  {tag}")
print("   -> 故障路与其余两路都冲突（2 票），被表决隔离；正常两路互相一致。")

# ---------- 3) NIS 门限捕获缓变漂移 ----------
print("\n[3] NIS 门限捕获缓变漂移（m=1 量测：漂移 b(t)=0.02·t °/s, σ=1 °/s）")
b_rate, sigma = 0.02, 1.0
gate = 3.841                                # χ²(1) 的 95% 分位（14 篇门限表）
k_trigger = int(np.ceil(np.sqrt(gate) / b_rate))   # NIS = (b·t)²/σ² = gate 的解（向上取整）
print(f"   NIS(t) = (0.02·t)²/1²，门限 χ²(1,95%) = {gate}")
for k in (50, k_trigger, 100):
    nis = (b_rate * k) ** 2 / sigma ** 2
    flag = "已触发" if nis > gate else "未触发"
    print(f"   t = {k:3d} 步: NIS = {nis:6.2f}  {flag}")
print(f"   -> 在第 {k_trigger} 步跨过门限（持续漂移 vs 偶发尖峰：看 NIS 是否单调上升）")
print("   （步数按整数步计算，两轨一致；实机用滑动窗口 + 健康标志，避免单步误报）")

print("\n[小结]")
print("   硬故障(卡死/断线) -> 方差≈0 / 通信错误位(SM_ERR_*) 即检。")
print("   软故障(偏差/漂移) -> 中值表决(3 路) + 2oo3 表决 + NIS 门限(在线)。")
print("   中值抗 1 路故障、均值不抗；2oo3 抗任意 1 路、怕 2 路同源共因。")
