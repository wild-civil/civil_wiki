#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
观测模型 H 矩阵构造 + 验证（本项目固件 ins_eskf_15d.c 锚定）
==============================================================
误差状态序（固件权威）：
    [ p(0:2), v(3:5), phi(6:8), ba(9:11), bg(12:14) ]   共 15 维
    p = NED 位置, v = NED 速度, phi = 3 维旋转矢量(姿态误差),
    ba = 加计零偏, bg = 陀螺零偏

本脚本做三件事：
  1) 按固件公式构造 5 种量测的 H 矩阵（GNSS 位置/速度、气压高度、加计、磁强计）
  2) 有限差分验证 H 的正确性（解析 H 对 数值雅可比）
  3) 演示可观测性解耦：加计只观 roll/pitch（重力方向），磁强计只观 yaw（航向）

不依赖 matplotlib，纯 numpy，结果可直接复现。
"""
import numpy as np

G = 9.81
EPS = 1e-5

# ---------- 基础工具 ----------
def skew(v):
    x, y, z = v
    return np.array([[0, -z, y],
                     [z, 0, -x],
                     [-y, x, 0]], float)

def axis_angle_to_R(axis, ang):
    """罗德里格斯公式：绕 axis(单位向量) 旋转 ang(rad) 的旋转矩阵。"""
    axis = np.asarray(axis, float); axis /= np.linalg.norm(axis)
    K = skew(axis)
    return np.eye(3) + np.sin(ang)*K + (1-np.cos(ang))*K@K

# ---------- 量测预测函数 h(x_nom) ----------
def h_gnss_pos(p):       return p[0:3]
def h_gnss_vel(v):       return v[3:6]
def h_baro(p):           return -p[2]            # NED 下 z 向下为正，高度 = -p_z
def h_accel(R):          return R.T @ np.array([0, 0, -G])   # 比力：R^T[0,0,-g]
def h_mag(R, mref):      return R.T @ mref

# ---------- 构造 H 矩阵（15 列，误差状态序）----------
def build_H(kind, R, mref=None):
    # 位置/速度在固件里也走 3x15 的 eus3 联合更新；baro 才是 1x15 标量
    H = np.zeros((1, 15)) if kind == 'baro' else np.zeros((3, 15))
    if kind == 'gnss_pos':
        H[0, 0] = H[1, 1] = H[2, 2] = 1.0
    elif kind == 'gnss_vel':
        H[0, 3] = H[1, 4] = H[2, 5] = 1.0
    elif kind == 'baro':
        H[0, 2] = -1.0
    elif kind in ('accel', 'mag'):
        h = h_accel(R) if kind == 'accel' else h_mag(R, mref)
        Hm = skew(h)                      # 右误差雅可比 +skew(h)（固件 ins_eskf_15d.c:462/493）
        for i in range(3):
            H[i, 6:9] = Hm[i]
    return H

# ---------- 有限差分验证 ----------
def predict_h(kind, p_pert, R_pert, mref):
    """按量测类型，用(扰动后的)名义态算预测值。"""
    if kind == 'gnss_pos': return h_gnss_pos(p_pert)
    if kind == 'gnss_vel': return h_gnss_vel(p_pert)
    if kind == 'baro':     return np.array([h_baro(p_pert)])
    if kind == 'accel':    return h_accel(R_pert)
    if kind == 'mag':      return h_mag(R_pert, mref)
    raise ValueError(kind)

def fd_check(kind, R, mref):
    """对每一种量测，比较解析 H 与数值雅可比。"""
    p0 = np.zeros(15)
    R0 = R
    H = build_H(kind, R0, mref)
    h0 = predict_h(kind, p0, R0, mref)
    nrows = H.shape[0]
    max_err = 0.0
    for j in range(15):
        p_pert = p0.copy()
        R_pert = R0
        if j <= 5:                 # 位置/速度块：直接平移名义态
            p_pert[j] += EPS
        elif 6 <= j <= 8:          # 姿态块：右乘小旋转
            axis = np.zeros(3); axis[j - 6] = 1.0
            R_pert = R0 @ axis_angle_to_R(axis, EPS)
        # ba/bg(9:14) 量测不依赖，名义态不变
        hp = predict_h(kind, p_pert, R_pert, mref)
        dh = (hp - h0) / EPS
        for a in range(nrows):
            max_err = max(max_err, abs(dh[a] - H[a, j]))
    return max_err

# ---------- 可观测性解耦演示 ----------
def observ_demo():
    R0 = np.eye(3)                              # 名义：水平、朝北
    mref = np.array([1.0, 0.0, 0.4])           # 导航系参考磁场：北向 + 向下(倾角)
    print("\n[可观测性] 名义 R=I, mref=[1,0,0.4]; 注入 10° 单轴姿态误差, 看各量测残差")
    print(f"{'误差轴':<10}{'加计残差|r|':>14}{'磁强计残差|r|':>16}")
    for name, axis, ang in [('roll(x)',  [1,0,0], 10*np.pi/180),
                            ('pitch(y)', [0,1,0], 10*np.pi/180),
                            ('yaw(z)',   [0,0,1], 10*np.pi/180)]:
        Rerr = axis_angle_to_R(axis, ang)
        Rtrue = R0 @ Rerr                      # 右误差：R_true = R_nom * R(dθ)
        ra = h_accel(Rtrue) - h_accel(R0)      # 真值减名义 -> 残差方向
        rm = h_mag(Rtrue, mref) - h_mag(R0, mref)
        print(f"{name:<10}{np.linalg.norm(ra):>14.4f}{np.linalg.norm(rm):>16.4f}")
    print("  -> 加计残差对 yaw≈0 (重力方向不含航向); 磁强计残差对 yaw 最大 (航向=罗盘)")

# ---------- 主程序 ----------
if __name__ == '__main__':
    R0 = np.eye(3)
    mref = np.array([1.0, 0.0, 0.4])
    print("="*70)
    print("观测模型 H 矩阵（固件误差状态序 [p,v,phi,ba,bg]）")
    print("="*70)
    for kind in ['gnss_pos', 'gnss_vel', 'baro', 'accel', 'mag']:
        H = build_H(kind, R0, mref)
        err = fd_check(kind, R0, mref)
        print(f"\n[{kind}]  H 形状 {H.shape[0]}x15,  解析H vs 数值雅可比最大差 = {err:.3e}")
        # 非零列（block）概览
        nz = np.where(np.any(np.abs(H) > 1e-12, axis=0))[0]
        print("  非零误差态列索引:", nz.tolist())
        print("  H =\n", np.array2string(H, precision=3, suppress_small=True))

    observ_demo()

    print("\n[小结] 每种传感器点亮误差态的不同块：")
    print("  GNSS 位置 -> 位置块(0:2)        直接观测位置")
    print("  GNSS 速度 -> 速度块(3:5)        直接观测速度")
    print("  气压高度  -> 位置块 z(索引2)     仅观测高度(= -p_z)")
    print("  加计      -> 姿态块(6:8)        观测 roll/pitch(重力方向)")
    print("  磁强计    -> 姿态块(6:8)        观测 yaw(航向)")
