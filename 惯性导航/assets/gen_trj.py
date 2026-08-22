#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
拆解 PSINS ①：test_SINS_trj 的 wat 表展开 + 关键航段解析值（纯 numpy，与 gen_trj.m 双轨）
=====================================================================================
test_SINS_trj.m 用 trjsegment 拼了 14 个航段（含复合段展开），最终喂给 trjsimu。
本脚本：
  1) 按 trjsegment 的规则把 14 段展开成完整 wat 表（每行 = [时长, 初速, w(3), a(3)]）
  2) 解析验证关键物理量：总时长、加速段末速、协调转弯半径、爬升段高度增量
     （纯解析，两轨逐数字一致；"真值"由 trjsimu 数值积分给出，P2 会验证闭环）
"""
import numpy as np

DPS = np.pi / 180.0   # deg/s -> rad/s
g = 9.8                # PSINS trjsegment 里的向心加速度参考（cf/9.8）

print("=" * 70)
print("拆解 PSINS ①：test_SINS_trj wat 表展开 + 解析值（纯 numpy / 纯 MATLAB 双轨）")
print("=" * 70)

# ---------- 复刻 trjsegment 的 wat 生成逻辑 ----------
seg = {'vel': 0.0, 'wat': []}          # init 段：初始速度 0

def push(row):
    seg['wat'].append(row)

def uniform(lasting):
    push([lasting, seg['vel'], 0, 0, 0, 0, 0, 0])

def accelerate(lasting, a):
    push([lasting, seg['vel'], 0, 0, 0, 0, a, 0])
    seg['vel'] += lasting * a

def deaccelerate(lasting, a):          # NOTE: a>0，减速用 -a
    push([lasting, seg['vel'], 0, 0, 0, 0, -a, 0])
    seg['vel'] -= lasting * a

def rollleft(lasting, w):
    push([lasting, seg['vel'], 0, -w * DPS, 0, 0, 0, 0])

def rollright(lasting, w):
    push([lasting, seg['vel'], 0, w * DPS, 0, 0, 0, 0])

def turnleft(lasting, w):
    cf = (w * DPS) * seg['vel']
    push([lasting, seg['vel'], 0, 0, w * DPS, -cf, 0, 0])

def turnright(lasting, w):
    cf = (w * DPS) * seg['vel']
    push([lasting, seg['vel'], 0, 0, -w * DPS, cf, 0, 0])

def headup(lasting, w):
    cf = (w * DPS) * seg['vel']
    push([lasting, seg['vel'], w * DPS, 0, 0, 0, 0, cf])

def headdown(lasting, w):
    cf = (w * DPS) * seg['vel']
    push([lasting, seg['vel'], -w * DPS, 0, 0, 0, 0, -cf])

def coturnleft(lasting, w, rolllasting):   # 协调左转：滚→转→滚回
    cf = (w * DPS) * seg['vel']
    rollw = np.arctan(cf / g) / DPS / rolllasting
    rollleft(rolllasting, rollw)
    turnleft(lasting, w)
    rollright(rolllasting, rollw)

def coturnright(lasting, w, rolllasting):
    cf = (w * DPS) * seg['vel']
    rollw = np.arctan(cf / g) / DPS / rolllasting
    rollright(rolllasting, rollw)
    turnright(lasting, w)
    rollleft(rolllasting, rollw)

def climb(lasting, w, uniformlasting):     # 抬头→匀速→低头
    headup(lasting, w)
    uniform(uniformlasting)
    headdown(lasting, w)

def descent(lasting, w, uniformlasting):
    headdown(lasting, w)
    uniform(uniformlasting)
    headup(lasting, w)

# ---------- test_SINS_trj.m 的 14 个航段 ----------
uniform(100)
accelerate(10, 1)          # 加速 10s, 1 m/s² -> 末速 10 m/s
uniform(100)
coturnleft(45, 2, 4)       # 协调左转 45s @ 2°/s（=90°），滚转 4s
uniform(100)
coturnright(50, 9, 4)      # 协调右转 50s @ 9°/s（=450°=1.25 圈），滚转 4s
uniform(100)
climb(10, 2, 50)           # 爬升：抬头 10s @2°/s + 平飞 50s + 低头 10s
uniform(100)
descent(10, 2, 50)         # 下降：对称
uniform(100)
deaccelerate(5, 2)         # 减速 5s, 2 m/s² -> 末速 0
uniform(100)

wat = np.array(seg['wat'])
total = wat[:, 0].sum()

# ---------- 1) wat 表（按航段展开后的行） ----------
print("\n[1] 完整 wat 表（每行 = [时长s, 初速m/s, w(°/s), a(m/s²)]，w/a 已转弧度）")
print(f"{'#':>3}{'时长s':>7}{'初速m/s':>8}{'w1°':>7}{'w2°':>7}{'w3°':>7}{'a1':>7}{'a2':>7}{'a3':>7}")
for i, r in enumerate(wat):
    print(f"{i+1:>3}{r[0]:>8.0f}{r[1]:>9.1f}{r[2]/DPS:>7.2f}{r[3]/DPS:>7.2f}{r[4]/DPS:>7.2f}"
          f"{r[5]:>7.3f}{r[6]:>7.3f}{r[7]:>7.3f}")

# ---------- 2) 解析验证 ----------
print("\n[2] 解析验证（纯公式，无仿真）")
print(f"   总时长 Σlasting = {total:.0f} s,  步数 @ts=0.01 = {int(total/0.01)}")
print(f"   加速段(10s@1m/s²): 末速 = 0 + 10×1 = {10*1:.0f} m/s")
print(f"   减速段(5s@2m/s²):  末速 = 10 - 5×2 = {10-5*2:.0f} m/s")
# 协调左转：45s @ 2°/s
wL, vL = 2 * DPS, 10.0
print(f"   coturnleft 45s @2°/s: 转角 = 45×2 = {45*2:.0f}°, 转弯半径 r = v/ω = {vL/wL:.1f} m")
print(f"     （协调转弯向心加速度 cf = ω·v = {wL*vL:.2f} m/s² = {wL*vL/g*100:.1f}%g，滚转角 = atan(cf/g) = {np.degrees(np.arctan(wL*vL/g)):.1f}°）")
# 协调右转：50s @ 9°/s
wR, vR = 9 * DPS, 10.0
print(f"   coturnright 50s @9°/s: 转角 = 50×9 = {50*9:.0f}° = {50*9/360:.2f} 圈, 半径 r = {vR/wR:.1f} m")
print(f"     （cf = {wR*vR:.2f} m/s² = {wR*vR/g*100:.1f}%g，滚转角 ≈ {np.degrees(np.arctan(wR*vR/g)):.1f}°）")
# 爬升段高度增量：抬头 10s @2°/s（θ 0→20°），高度 Δh = (v/ω)(1−cosωT)
wC, vC, TC = 2 * DPS, 10.0, 10.0
dh_up = (vC / wC) * (1 - np.cos(wC * TC))
dh_level = 50 * vC * np.sin(wC * TC)
print(f"   climb 段高度增量（解析）:")
print(f"     抬头 10s (θ 0→{np.degrees(wC*TC):.0f}°): Δh = (v/ω)(1−cosωT) = {dh_up:.1f} m")
print(f"     平飞 50s @{np.degrees(wC*TC):.0f}° 仰角:   Δh = t·v·sinθ = {dh_level:.1f} m")
print(f"     低头 10s (对称):               Δh = {dh_up:.1f} m")
print(f"     净爬升 ≈ {dh_up+dh_level+dh_up:.1f} m（descent 段对称，最终回到原高度）")

print("\n[小结]")
print("   轨迹 = 航段语言的'程序'：匀速/加减速改速度大小，转弯/滚转/俯仰改方向，")
print("   协调转弯用 cf=ω·v 保持向心加速度 → 所有段无缝衔接成一条平滑轨迹。")
print("   trjsimu 再按 wat 表数值积分出真值 + IMU 读数（P2 的 test_SINS 将验证闭环）。")
