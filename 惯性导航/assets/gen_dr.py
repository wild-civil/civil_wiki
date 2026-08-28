#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
拆解 PSINS ③：迷你航位推算 = 真值轨迹生成 + 迷你 odsimu + 误差注入 + 迷你 drinit/drupdate
=====================================================================================
复刻 test_DR.m 的数据流，但全部自包含（不依赖 PSINS）：
  [生成] WAT 表（P1 产物）-> 迷你 trjsimu 数值积分出 真值 avp + 陀螺增量 imu
  [里程] 迷你 odsimu：真值位置差分 -> 地球半径投影 -> 每步里程增量 dS（完美里程计）
  [注入] 确定性误差：初始航向误差 davp(yaw)、里程计安装误差 dinst、尺度因子 dkod、陀螺零偏 eb
  [解算] 迷你 drupdate 主循环：陀螺 wm 更新航向、里程 dS 投影递推位置（Td=0 无 leveling）
  [分析] 解算 vs 真值：位置误差（航向误差×路程 -> 线性发散；尺度误差 -> 比例发散）
教学简化（route B 零依赖）：odsimu 不做 inst 旋转真值（inst 误差只在 drinit 注入）；
  Td leveling 关掉；随机游走省略（确定性）。与 PSINS 对拍数字见 P3 正文。
"""
import numpy as np

# ---------------- 常量（与 PSINS glvf 对齐） ----------------
Re, f, wie, g0 = 6378137.0, 1/298.257, 7.2921151467e-5, 9.7803267715
e2 = 2*f - f*f
deg, dph, ug = np.pi/180, np.pi/180/3600, 1e-6*g0
ts = 0.01                       # 100 Hz

# ---------------- 四元数/旋转工具 ----------------
def rv2q(phi):
    n = np.linalg.norm(phi)
    if n < 1e-12: return np.array([1.,0,0,0])
    s = np.sin(n/2)/n
    return np.array([np.cos(n/2), s*phi[0], s*phi[1], s*phi[2]])

def qmul(q1, q2):
    return np.array([q1[0]*q2[0]-q1[1]*q2[1]-q1[2]*q2[2]-q1[3]*q2[3],
                     q1[0]*q2[1]+q1[1]*q2[0]+q1[2]*q2[3]-q1[3]*q2[2],
                     q1[0]*q2[2]-q1[1]*q2[3]+q1[2]*q2[0]+q1[3]*q2[1],
                     q1[0]*q2[3]+q1[1]*q2[2]-q1[2]*q2[1]+q1[3]*q2[0]])

def q2mat(q):
    q0,q1,q2,q3 = q
    return np.array([[q0*q0+q1*q1-q2*q2-q3*q3, 2*(q1*q2-q0*q3),       2*(q1*q3+q0*q2)],
                     [2*(q1*q2+q0*q3),         q0*q0-q1*q1+q2*q2-q3*q3, 2*(q2*q3-q0*q1)],
                     [2*(q1*q3-q0*q2),         2*(q2*q3+q0*q1),       q0*q0-q1*q1-q2*q2+q3*q3]])

def q2att(q):
    """q -> att=[pitch;roll;yaw]（PSINS base0/q2att.m 逐字对齐，NED）"""
    q0,q1,q2,q3 = q
    pitch = np.arcsin(2*(q2*q3 + q0*q1))
    roll  = np.arctan2(-2*(q1*q3 - q0*q2), q0*q0 - q1*q1 - q2*q2 + q3*q3)
    yaw   = np.arctan2(-2*(q1*q2 - q0*q3), q0*q0 - q1*q1 + q2*q2 - q3*q3)
    return np.array([pitch, roll, yaw])

def a2qua(att):
    """att=[pitch;roll;yaw] -> q（标量在首；PSINS base0/a2qua.m 逐字对齐）"""
    s = np.sin(att/2); c = np.cos(att/2)
    return np.array([c[0]*c[1]*c[2] + s[0]*s[1]*s[2],
                     s[0]*c[1]*c[2] - c[0]*s[1]*s[2],
                     c[0]*s[1]*c[2] + s[0]*c[1]*s[2],
                     c[0]*c[1]*s[2] + s[0]*s[1]*c[2]])

def a2mat(att): return q2mat(a2qua(att))
def qmulv(q, v): return q2mat(q) @ v
def rotv(phi, v): return qmulv(rv2q(phi), v)
def qconj(q): return np.array([q[0], -q[1], -q[2], -q[3]])
def cros(a, b): return np.cross(a, b)
def askew(v):
    return np.array([[0, -v[2], v[1]], [v[2], 0, -v[0]], [-v[1], v[0], 0]])

# ---------------- earth（PSINS base1/earth.m 核心） ----------------
def earth(pos, vn):
    sl, cl = np.sin(pos[0]), np.cos(pos[0])
    sl2 = sl*sl
    sq = 1 - e2*sl2;  sq2 = np.sqrt(sq)
    RMh = Re*(1-e2)/sq/sq2 + pos[2]
    RNh = Re/sq2 + pos[2]
    clRNh = cl*RNh
    vE_RNh = vn[0]/RNh
    wnen = np.array([-vn[1]/RMh, vE_RNh, vE_RNh*sl/cl])
    wnie = np.array([0., wie*cl, wie*sl])
    wnin = wnie + wnen
    gn = np.array([0., 0., -g0])
    gcc = gn - cros(wnie+wnen, vn)
    return RMh, RNh, clRNh, wnin, gcc

# ---------------- wat 表（P1 产物：test_SINS_trj 展开 21 行） ----------------
WAT = np.array([
 [100,  0,  0,      0,     0,      0,      0,     0],
 [ 10,  0,  0,      0,     0,      0,      1,     0],
 [100, 10,  0,      0,     0,      0,      0,     0],
 [  4, 10,  0, -0.51*deg, 0,      0,      0,     0],
 [ 45, 10,  0,      0, 2.00*deg, -0.349,  0,     0],
 [  4, 10,  0,  0.51*deg, 0,      0,      0,     0],
 [100, 10,  0,      0,     0,      0,      0,     0],
 [  4, 10,  0,  2.28*deg, 0,      0,      0,     0],
 [ 50, 10,  0,      0,-9.00*deg,  1.571,  0,     0],
 [  4, 10,  0, -2.28*deg, 0,      0,      0,     0],
 [100, 10,  0,      0,     0,      0,      0,     0],
 [ 10, 10, 2.00*deg, 0, 0,        0,      0, 0.349],
 [ 50, 10,  0,      0,     0,      0,      0,     0],
 [ 10, 10,-2.00*deg, 0, 0,        0,      0,-0.349],
 [100, 10,  0,      0,     0,      0,      0,     0],
 [ 10, 10,-2.00*deg, 0, 0,        0,      0,-0.349],
 [ 50, 10,  0,      0,     0,      0,      0,     0],
 [ 10, 10, 2.00*deg, 0, 0,        0,      0, 0.349],
 [100, 10,  0,      0,     0,      0,      0,     0],
 [  5, 10,  0,      0,     0,      0,     -2,     0],
 [100,  0,  0,      0,     0,      0,      0,     0],
])
# wat 列：[时长s, 初速m/s, w1, w2, w3(rad/s), a1, a2, a3(m/s²)]（w/a 已转 rad）

# ---------------- 迷你 trjsimu（P1 公式代码化，含 wnin/gcc 补偿） ----------------
def minitrj(avp0, wat, ts):
    att, vn, pos = avp0[0:3].copy(), avp0[3:6].copy(), avp0[6:9].copy()
    total = int(round(wat[:,0].sum()/ts))
    imu = np.zeros((total, 7)); avp = np.zeros((total, 10))
    ts2 = ts/2
    ki = 0
    qnb = a2qua(att); Cbn_1 = q2mat(qnb).T
    wm_1 = np.zeros(3)
    for r in wat:
        lenk = int(round(r[0]/ts)); wt, at = r[2:5], r[5:8]
        for _ in range(lenk):
            si, ci = np.sin(att[0]), np.cos(att[0])
            sk, ck = np.sin(att[2]), np.cos(att[2])
            Cnt = np.array([[ck, -ci*sk, si*sk],
                            [sk,  ci*ck, -si*ck],
                            [0,    si,    ci]])
            att = att + wt*ts
            Cnb = q2mat(a2qua(att))
            an = Cnt @ at
            vn1 = vn + an*ts; vn01 = (vn+vn1)/2
            RMh, RNh, clRNh, wnin, gcc = earth(pos, vn01)
            dpos01 = np.array([vn01[1]/RMh, vn01[0]/clRNh, vn01[2]])*ts2
            pos = pos + 2*dpos01
            dq = qmul(qconj(a2qua(att - wt*ts)), a2qua(att))
            phim = 2*np.array([np.arctan2(dq[1], dq[0]), np.arctan2(dq[2], dq[0]), np.arctan2(dq[3], dq[0])])
            phim = phim + (Cbn_1 + Cnb.T) @ (wnin*ts2)
            wm = np.linalg.inv(np.eye(3) + 1/12*askew(wm_1)) @ phim
            dvbm = Cbn_1 @ (an - gcc)*ts
            vm = np.linalg.inv(np.eye(3) + 0.5*askew(wm)) @ dvbm
            avp[ki] = [*att, *vn1, *pos, ki*ts]
            imu[ki] = [*wm, *vm, ki*ts]
            wm_1 = wm; Cbn_1 = Cnb.T; vn = vn1
            ki += 1
    return imu[:ki], avp[:ki]

# ---------------- 迷你 odsimu（里程增量仿真，Td=0 确定性） ----------------
def mini_odsimu(trj, inst, kod):
    """trj: 真值 avp (N×10)；inst: 安装误差(略, 教学版=0)；kod: 完美里程计=1
       输出 od: N×2 = [每步里程增量 dS, 时刻 t]，与 trj 行一一对应"""
    pos0 = trj[0, 6:9]
    pos = np.vstack([pos0, trj[:, 6:9]])     # N+1 个位置点
    n = pos.shape[0]
    RMh = np.zeros(n-1); clRNh = np.zeros(n-1)
    for k in range(n-1):
        RMh[k], _, clRNh[k], _, _ = earth(pos[k], np.zeros(3))
    dpos = np.diff(pos, axis=0)
    dxyz = np.column_stack([RMh*dpos[:,0], clRNh*dpos[:,1], dpos[:,2]])
    dS = np.sqrt(np.sum(dxyz**2, axis=1))
    dSc = np.concatenate([[0], np.cumsum(dS)])
    od = np.column_stack([np.diff(dSc/kod), trj[:, 9]])
    return od

# ---------------- 迷你 drinit（DR 结构初始化，Td=0） ----------------
def mini_drinit(avp0e, inst, kod, ts):
    dr = {}
    avp0e = avp0e.copy()
    if len(avp0e) < 9:
        avp0e = np.concatenate([avp0e[0:3], np.zeros(3), avp0e[3:]])
    qnb = a2qua(avp0e[0:3])
    att = q2att(qnb); Cnb = q2mat(qnb)
    vn = np.zeros(3); pos = avp0e[6:9]
    dr['qnb'] = qnb; dr['att'] = att; dr['Cnb'] = Cnb
    dr['vn'] = vn; dr['pos'] = pos; dr['avp'] = np.concatenate([att, vn, pos])
    dr['kod'] = kod
    dr['aos'] = inst[1]; inst = inst.copy(); inst[1] = 0
    Cbo = a2mat(-inst) * kod
    dr['Cbo'] = Cbo
    dr['prj'] = Cbo @ np.array([0., 1., 0.])
    dr['ts'] = ts
    dr['distance'] = 0.0
    RMh, _, clRNh, _, _ = earth(pos, np.zeros(3))
    dr['Mpv'] = np.array([[0, 1/RMh, 0], [1/clRNh, 0, 0], [0, 0, 1]])
    dr['Td'] = 0
    return dr

# ---------------- 迷你 drupdate（DR 主更新，Td=0 无 leveling） ----------------
def mini_drupdate(dr, wm, dS):
    nts = dr['ts'] * wm.shape[0]
    # cnscl 双子样：陀螺圆锥补偿（DR 只用陀螺更新航向）
    wmm = wm.sum(0)
    dphim = cros(0.5*wm[0], wm[1])
    phim = wmm + dphim
    qnb12 = qmul(dr['qnb'], rv2q(phim/2))     # qupdt(dr.qnb, phim/2)
    # 里程增量投影到导航系
    if np.ndim(dS) > 0 and len(dS) > 1:
        dSn = qmulv(qnb12, dr['Cbo'] @ dS)
    else:
        dSn = qmulv(qnb12, dr['prj'] * dS)
    dSn = rotv(np.array([0, 0, -dr['aos']*phim[2]/nts]), dSn)   # aos=0 -> 恒等
    dr['vn'] = dSn / nts
    RMh, RNh, clRNh, wnin, gcc = earth(dr['pos'], dr['vn'])
    dr['Mpv'] = np.array([[0, 1/RMh, 0], [1/clRNh, 0, 0], [0, 0, 1]])
    dr['pos'] = dr['pos'] + dr['Mpv'] @ dSn    # 位置递推（严龚敏博士论文 Eq.4.1.1）
    dr['qnb'] = qmul(dr['qnb'], rv2q(phim - dr['Cnb'].T @ wnin * nts))  # 姿态更新
    dr['att'] = q2att(dr['qnb']); dr['Cnb'] = q2mat(dr['qnb'])
    dr['avp'] = np.concatenate([dr['att'], dr['vn'], dr['pos']])
    dr['distance'] = dr['distance'] + dr['kod'] * abs(dS)
    return dr

# ---------------- 主流程 ----------------
print("="*70)
print("拆解 PSINS ③：迷你航位推算 = 真值 + odsimu + 误差注入 + drinit/drupdate")
print("="*70)

avp0 = np.array([0, 0, 0,  0, 0, 0,  29*deg, 106*deg, 450.0])

print("\n[1] 真值轨迹生成（100 Hz，双子样增量）")
imu, trj = minitrj(avp0, WAT, ts)
print(f"    行数 = {len(imu)}（期望 96600），末位置 = ({trj[-1,6]/deg:.4f}°, {trj[-1,7]/deg:.4f}°, {trj[-1,8]:.1f} m)")

print("\n[2] 迷你 odsimu：真值位置差分出完美里程增量 dS")
od = mini_odsimu(trj, 0, 1.0)
print(f"    里程增量行数 = {len(od)}，总里程 = {od[:,0].sum():.1f} m")

print("\n[3] 确定性误差注入（航向 1°、里程计安装 10'、尺度 5%、陀螺零偏 0.01°/h）")
davp  = np.array([60, 0, 60])*(deg/60)     # 姿态误差 arcmin -> pitch 1°, roll 0, yaw 1°
dinst = np.array([15, 0, 10])*(deg/60)     # 安装误差 arcmin -> dyaw = 10''
dkod  = 0.05                               # 尺度因子误差 5%
eb    = np.array([0, 0, 0.01])*dph         # 陀螺零偏（z 轴 -> 航向缓慢漂移）
avp0e = avp0.copy(); avp0e[0:3] += davp
imu_e = imu.copy(); imu_e[:, 0:3] += eb*ts
print(f"    初始 yaw 误差 = {davp[2]/deg:.3f}° (=60')，安装 dyaw = {dinst[2]/deg:.3f}° (=10')，尺度误差 = {dkod*100:.0f}%")

print("\n[4] 迷你 drinit + drupdate 主循环（Td=0）")
dr = mini_drinit(avp0e, dinst, 1.0*(1+dkod), ts)
len_ = len(imu_e); nn = 2
avp = np.zeros((len_//nn, 10)); ki = 0
for k in range(0, len_-nn+1, nn):
    k1 = k + nn - 1
    wm = imu_e[k:k+nn, 0:3]
    dS = od[k:k+nn, 0].sum()
    dr = mini_drupdate(dr, wm, dS)
    avp[ki] = [*dr['avp'], imu_e[k1, 6]]
    ki += 1
avp = avp[:ki]
print(f"    总里程 dr.distance = {dr['distance']:.1f} m（= 真值里程 ×(1+dkod)）")

print("\n[5] 误差传播分析（DR vs 真值，966 s）")
Re_h = Re + avp0[8]

def wrap_pi(a):
    return (a + np.pi) % (2*np.pi) - np.pi

def errstats(name, avp):
    trj_d = trj[1::2]
    n = min(len(avp), len(trj_d))
    de = avp[:n, 0:3] - trj_d[:n, 0:3]; de[:, 2] = wrap_pi(de[:, 2])
    dv = avp[:n, 3:6] - trj_d[:n, 3:6]
    dp = avp[:n, 6:9] - trj_d[:n, 6:9]
    dph = np.array([dp[:,0]*Re_h, dp[:,1]*Re_h*np.cos(avp0[6]), dp[:,2]]).T
    dp_horiz = np.hypot(dph[:,0], dph[:,1])
    print(f"    [{name}] att RMS = ({np.abs(de).mean(0)[0]/deg*3600:.1f}, {np.abs(de).mean(0)[1]/deg*3600:.1f}, {np.abs(de).mean(0)[2]/deg*3600:.1f}) arcsec"
          f" | vel RMS = {np.abs(dv).mean(0)} m/s")
    print(f"             水平位置误差 RMS = {dp_horiz.mean():.1f} m, 末点 = {dp_horiz[-1]:.1f} m"
          f" | 垂直 = {np.abs(dph[:,2]).mean():.1f} m (末 {dph[-1,2]:.1f} m)")

errstats("航位推算", avp)

print("\n[6] 教学要点")
print("    航向误差 δψ -> 位置误差 ≈ tan(δψ)·S（S=已走路程） -> 随路程线性发散")
print("    尺度因子误差 dkod -> 位置误差 ∝ dkod·S -> 同样线性（比例型）")
print("    与 P2 纯惯导对照：P2 误差来自重力杠杆(Schuler 振荡,随时间) ；DR 误差随路程单调增长")

print("\n[7] 可视化（迷你 insplot / avpcmpplot / 3D，零依赖自写，参考 PSINS 布局）")
from miniplot import miniinsplot, miniavpcmpplot, miniinsplot3d
miniinsplot(trj, 'truth')
miniinsplot(avp, 'dr')
miniinsplot(avp, trj, 'cmp')
miniavpcmpplot(trj, [avp], ['dr'], outname='miniavpcmpplot_dr.png')
# 3D 轨迹对比（DR vs 真值；Z=高度误差×8，与 P2 的 miniinsplot3d 约定一致）
miniinsplot3d([avp], trj, 'cmp_dr')
