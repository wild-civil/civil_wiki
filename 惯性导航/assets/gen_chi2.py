#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
一致性检验 NEES/NIS：χ² 门限与错配诊断（纯 numpy，与 gen_chi2.m 双轨）
=====================================================================
核心事实：
   若滤波器声称的协方差 P（及 R）与真实误差统计一致，则
     NEES = dx' P^{-1} dx  ~  chi2(n_x)     （dx = x_true - x_hat，需真值）
     NIS  = r'  S^{-1} r   ~  chi2(m)       （r = z - h(x_hat)，S = H P H' + R，在线可算）
   因此 E[NEES]=n_x、E[NIS]=m：长时间平均偏离 m 就说明 P/R 与真实不符。

本脚本做三件事：
  1) χ² 分布性质蒙特卡洛：标准正态平方和 → 样本均值≈m、95% 分位≈理论值
  2) NIS 均值 = 一致性闸门：R/P 声称值对/错配 三场景（解析期望 + MC 确认）
  3) NEES 批检验（有真值场景）：N 时刻 ΣNEES ~ chi2(N*n_x) 的 95% 区间判定
不依赖 scipy，结果可直接复现。
"""
import numpy as np

rng = np.random.default_rng(42)

# ---------- 理论 χ² 分位数（对照用） ----------
# m=1,2,3 的 95% / 99% 上侧分位数
CHI2_THEO = {1: (3.841, 6.635),
             2: (5.991, 9.210),
             3: (7.815, 11.345)}

print("=" * 70)
print("一致性检验 NEES/NIS：χ² 门限与错配诊断（纯 numpy / 纯 MATLAB 双轨）")
print("=" * 70)

# ---------- 1) χ² 分布性质（MC） ----------
print("\n[1] χ² 分布性质（MC: N=200000，标准正态平方和 → 自由度 m）")
N_MC = 200_000
for m in (1, 2, 3):
    samples = np.sum(rng.standard_normal((N_MC, m)) ** 2, axis=1)
    mean_mc = samples.mean()
    q95_mc = np.quantile(samples, 0.95)
    q95_th = CHI2_THEO[m][0]
    print(f"   m={m}: 样本均值={mean_mc:.3f} (理论 {m}),  "
          f"95% 分位={q95_mc:.2f} (理论 {q95_th:.3f})")
print("   -> 均值=m：若 P 真是误差协方差，NEES/NIS 就服从 χ²(m) —— 这是检验的根基")

# ---------- 2) NIS 均值 = 一致性闸门 ----------
print("\n[2] NIS 均值 = 一致性闸门（m=2 位置量测；真实新息协方差 Σ_true = P+R = 41·I₂）")
P_true, R_true = 16.0, 25.0          # 真实预测误差 4 m、量测噪声 5 m
Sigma_true = (P_true + R_true) * np.eye(2)
print(f"   真实: P_true={P_true:.0f} (4m), R_true={R_true:.0f} (5m), Σ_true=({P_true+R_true:.0f})·I₂")
scenarios = [
    ("一致    (S=41·I₂)", 16.0, 25.0, "✓ 通过 (≈m)"),
    ("过自信  (S=8·I₂)",   4.0,  4.0, "✗ 偏高 → P/R 被低估"),
    ("过保守  (S=200·I₂)", 100.0, 100.0, "✗ 偏低 → P/R 被高估"),
]
print(f"   {'场景':<16}{'E[NIS] 解析':>12}{'MC 均值':>10}   判定")
for name, P_c, R_c, verdict in scenarios:
    S_claim = (P_c + R_c) * np.eye(2)
    # 解析：E[r' S^-1 r] = tr(S^-1 Σ_true)，r ~ N(0, Σ_true)
    E_nis = np.trace(np.linalg.inv(S_claim) @ Sigma_true)
    # MC 确认：r = chol(Σ_true) @ 标准正态
    r = np.sqrt(P_true + R_true) * rng.standard_normal((2, N_MC))
    nis = np.sum(r * (np.linalg.inv(S_claim) @ r), axis=0)
    print(f"   {name:<16}{E_nis:>10.2f}{nis.mean():>10.2f}   {verdict}")

# ---------- 3) NEES 批检验（有真值场景） ----------
print("\n[3] NEES 批检验（有真值才可算：N=50 时刻, 状态维 d=2）")
N = 50
d = 2
lo, hi = 74.22, 129.56   # chi2(100) 的 2.5%/97.5% 分位（理论，批检验 95% 区间）
print(f"   ΣNEES ~ χ²(N·d) = χ²(100)，95% 区间 [{lo}, {hi}]")
print(f"   一致滤波器:  E[ΣNEES] = N·d = {N*d:.0f} ∈ [{lo}, {hi}] → ✓ 通过")
ratio = 4.0  # 过自信：声称 P = P_true/4
E_over = N * d * ratio
print(f"   过自信(P/4): E[ΣNEES] = {E_over:.0f} >> {hi} → ✗ 拒绝（声称 P 太小，误差被高估 4 倍）")
print("   -> 实机没有真值用 NIS；仿真/SIL 有真值才用 NEES（本项目 matlab_sim 即此场景）")

print("\n[小结]")
print("   一致性 = 声称的 P/R 与真实误差统计相符；NIS 均值 ≈ m 即通过。")
print("   NIS 偏高 → 过自信（P/R 被低估）；NIS 偏低 → 过保守（P/R 被高估）。")
print("   单次 NIS 波动大，须时间平均 / 批检验 / χ² 门限（gating 即单次门限的工程化）。")
