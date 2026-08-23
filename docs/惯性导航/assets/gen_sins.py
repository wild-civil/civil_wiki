#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
拆解 PSINS ②：迷你链路 = 迷你 trjsimu + 误差注入 + 迷你 inspure（纯 numpy，与 gen_sins.m 双轨）
=====================================================================================
复刻 test_SINS.m 的数据流，但全部自包含（不依赖 PSINS）：
  [生成] wat 表（P1 产物，21 行硬编码）-> 迷你 trjsimu 数值积分出 真值 avp + imu 增量
  [注入] 确定性误差：eb=0.01°/h 陀螺零偏、db=100µg 加计零偏、初始姿态误差 [0.5;0.5;5]'
  [解算] 迷你 inspure（nn=2 双子样机械编排：cnscl 圆锥/划桨 + earth + 速度/位置/姿态更新）
  [分析] 解算 vs 真值：姿态/速度/位置误差（Schuler 振荡、水平漂移、高度通道）
高度阻尼选项：free（自由）/ fix（固定真值高度，= test_SINS 的 trj.bh 作用）
教学简化（对拍 PSINS 时允许的差异）：随机游走省略（确定性）、trjsimu 无匀速阻尼。
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
    q = np.array([q1[0]*q2[0]-q1[1]*q2[1]-q1[2]*q2[2]-q1[3]*q2[3],
                  q1[0]*q2[1]+q1[1]*q2[0]+q1[2]*q2[3]-q1[3]*q2[2],
                  q1[0]*q2[2]-q1[1]*q2[3]+q1[2]*q2[0]+q1[3]*q2[1],
                  q1[0]*q2[3]+q1[1]*q2[2]-q1[2]*q2[1]+q1[3]*q2[0]])
    return q

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

def qmulv(q, v): return q2mat(q) @ v
def rotv(phi, v): return qmulv(rv2q(phi), v)
def cros(a, b):  return np.cross(a, b)
def qconj(q):    return np.array([q[0], -q[1], -q[2], -q[3]])   # 四元数共轭（np.conj 对实数数组无效！）

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
    wnien = wnie + wnen
    gcc = gn - cros(wnien, vn)
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
    qnb = a2qua(att); Cbn_1 = q2mat(qnb).T     # C_b^n（导航->体 的转置 = 体->导航）
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
            # 姿态增量（旋转矢量，dq 法 ≈ PSINS m2rv(Cbn_1*Cnb)）
            dq = qmul(qconj(a2qua(att - wt*ts)), a2qua(att))
            phim = 2*np.array([np.arctan2(dq[1], dq[0]), np.arctan2(dq[2], dq[0]), np.arctan2(dq[3], dq[0])])
            phim = phim + (Cbn_1 + Cnb.T) @ (wnin*ts2)     # wnin 补偿（同 PSINS）
            wm = np.linalg.inv(np.eye(3) + 1/12*askew(wm_1)) @ phim
            dvbm = Cbn_1 @ (an - gcc)*ts
            vm = np.linalg.inv(np.eye(3) + 0.5*askew(wm)) @ dvbm
            avp[ki] = [*att, *vn1, *pos, ki*ts]
            imu[ki] = [*wm, *vm, ki*ts]
            wm_1 = wm; Cbn_1 = Cnb.T; vn = vn1
            ki += 1
    return imu[:ki], avp[:ki]

def askew(v):
    return np.array([[0, -v[2], v[1]], [v[2], 0, -v[0]], [-v[1], v[0], 0]])

# ---------------- 迷你 inspure（nn=2 双子样机械编排） ----------------
def miniinspure(imu, avp0, fix_h=False):
    nn = 2
    att, vn, pos = avp0[0:3].copy(), avp0[3:6].copy(), avp0[6:9].copy()
    qnb = a2qua(att)
    len_ = len(imu); m = len_//nn
    avp = np.zeros((m, 10)); ki = 0
    pos0 = pos.copy()
    for k in range(0, len_-nn+1, nn):
        wm = imu[k:k+nn, 0:3]; vm = imu[k:k+nn, 3:6]
        nts = nn*ts; nts2 = nts/2
        # cnscl 双子样圆锥/划桨补偿
        wmm = wm.sum(0)
        dphim = cros(0.5*wm[0], wm[1])
        phim = wmm + dphim
        vmm = vm.sum(0)
        scullm = cros(0.5*wm[0], vm[1]) + cros(vm[0], 0.5*wm[1])
        dvbm = vmm + scullm
        # 标定（迷你版：无刻度误差，零偏已注入数据）
        phim = phim; dvbm = dvbm
        # earth
        RMh, RNh, clRNh, wnin, gcc = earth(pos, vn)
        # 速度更新
        fn = q2mat(qnb) @ (dvbm/nts)
        an = rotv(-wnin*nts2, fn) + gcc
        vn1 = vn + an*nts
        # 位置更新
        Mpv = np.array([[0, 1/RMh, 0], [1/clRNh, 0, 0], [0, 0, 1]])
        pos = pos + Mpv @ ((vn+vn1)/2)*nts
        vn = vn1
        # 姿态更新（qupdt2 等效）
        qnb = qmul(rv2q(-wnin*nts), qmul(qnb, rv2q(phim)))
        if fix_h:
            pos[2] = pos0[2]          # 高度固定（= test_SINS 的 trj.bh 作用）
        att = q2att(qnb)
        avp[ki] = [*att, *vn, *pos, imu[k+1, 6]]
        ki += 1
    return avp[:ki]

# ---------------- 主流程 ----------------
print("="*70)
print("拆解 PSINS ②：迷你链路 = 迷你 trjsimu + 误差注入 + 迷你 inspure")
print("="*70)

avp0 = np.array([0, 0, 0,  0, 0, 0,  29*deg, 106*deg, 450.0])

print("\n[1] 迷你 trjsimu：966 s 轨迹生成（100 Hz，双子样增量）")
imu, trj = minitrj(avp0, WAT, ts)
print(f"    行数 = {len(imu)}（期望 96600），末位置 = ({trj[-1,6]/deg:.4f}°, {trj[-1,7]/deg:.4f}°, {trj[-1,8]:.1f} m)")

print("\n[2] 确定性误差注入（eb=0.01°/h, db=100µg, att err [0.5;0.5;5]', vn 0.1, pos 10m）")
eb = np.array([0.01, 0.01, 0.01])*dph
db = np.array([100., 100., 100.])*ug
imu_e = imu.copy()
imu_e[:, 0:3] += eb*ts
imu_e[:, 3:6] += db*ts
att0e = avp0[0:3] + np.array([0.5, 0.5, 5.0])*(deg/60)
avp0e = np.array([*att0e, 0.1, 0.1, 0.1, avp0[6]+10/Re, avp0[7]+10/(Re*np.cos(avp0[6])), avp0[8]+10])

print("\n[3] 迷你 inspure（nn=2 双子样机械编排）")
avp_free = miniinspure(imu_e, avp0e, fix_h=False)
avp_fix  = miniinspure(imu_e, avp0e, fix_h=True)
Re_h = Re + avp0[8]
def pos_err_m(dp):
    return np.array([dp[0]*Re_h, dp[1]*Re_h*np.cos(avp0[6]), dp[2]])
print(f"    高度自由:  末点位置误差 = ({pos_err_m(avp_free[-1,6:9]-trj[-1,6:9])[0]:.1f}, {pos_err_m(avp_free[-1,6:9]-trj[-1,6:9])[1]:.1f}, {pos_err_m(avp_free[-1,6:9]-trj[-1,6:9])[2]:.1f}) m")
print(f"    高度固定:  末点位置误差 = ({pos_err_m(avp_fix[-1,6:9]-trj[-1,6:9])[0]:.1f}, {pos_err_m(avp_fix[-1,6:9]-trj[-1,6:9])[1]:.1f}, {pos_err_m(avp_fix[-1,6:9]-trj[-1,6:9])[2]:.1f}) m")

def wrap_pi(a):
    return (a + np.pi) % (2*np.pi) - np.pi

def errstats(name, avp):
    # 与真值对齐（双子样：时刻 1,3,5,...*ts）
    trj_d = trj[1::2]
    n = min(len(avp), len(trj_d))
    de = avp[:n,0:3] - trj_d[:n,0:3]; de[:,2] = wrap_pi(de[:,2])
    dv = avp[:n,3:6] - trj_d[:n,3:6]
    dp = avp[:n,6:9] - trj_d[:n,6:9]
    dph = np.array([dp[:,0]*Re_h, dp[:,1]*Re_h*np.cos(avp0[6]), dp[:,2]]).T
    dp_horiz = np.hypot(dph[:,0], dph[:,1])
    print(f"    [{name}] att RMS = ({np.abs(de).mean(0)[0]/deg*3600:.1f}, {np.abs(de).mean(0)[1]/deg*3600:.1f}, {np.abs(de).mean(0)[2]/deg*3600:.1f}) arcsec"
          f" | vel RMS = {np.abs(dv).mean(0)} m/s")
    print(f"             水平位置误差 RMS = {dp_horiz.mean():.1f} m, 末点 = {dp_horiz[-1]:.1f} m"
          f" | 垂直 = {np.abs(dph[:,2]).mean():.1f} m (末 {dph[-1,2]:.1f} m)")

print("\n[4] 误差传播分析（vs 真值，966 s）")
errstats("高度自由", avp_free)
errstats("高度固定", avp_fix)

print("\n[5] 教学要点")
print("    陀螺零偏 eb -> 姿态误差(线性增长) -> 位置误差(Schuler 振荡 ~84min 周期) -> 水平漂移 km 级")
print("    高度通道开环不稳定(垂直 Schuler ~9min 周期发散) -> test_SINS 用 trj.bh 固定高度(高度阻尼)")
print("    mini vs PSINS：随机游走/trjsimu 阻尼差异，量级形态一致（对拍数字见 P2 正文）")

print("\n[6] 可视化（迷你 insplot / avpcmpplot，零依赖自写，参考 PSINS 布局）")
from miniplot import miniinsplot, miniavpcmpplot, miniinsplot3d
miniinsplot(avp_fix, 'fix')
miniinsplot(avp_free, 'free')
miniavpcmpplot(trj, [avp_free, avp_fix], ['free', 'fix'])
# 方案 B：真值 + free + fix 同图三色叠加（黑=Truth，红=free，蓝=fix）
miniinsplot([avp_free, avp_fix], trj, 'cmp_freefix')
# 方案 A：三维轨迹对比（独立图，Z=高度误差×8 放大，破"2D 看不出 free/fix 差别"的困惑）
miniinsplot3d([avp_free, avp_fix], trj, 'cmp_freefix')
