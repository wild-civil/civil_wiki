#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
拆解 PSINS ④：迷你 SINS+DR 组合导航 = 迷你 trjsimu + 误差注入 + 迷你 inspure(分步)
           + dr.qnb=ins.qnb 锚定 + 迷你 drupdate + 22 维 KF + kffeedback(仅速度)
=====================================================================================
复刻 test_SINS_DR.m 的数据流，全部自包含（不依赖 PSINS）：
  [生成] WAT 表 -> 迷你 trjsimu 出 真值 avp + imu 增量；迷你 odsimu 出完美里程 dS
  [注入] 确定性误差：eb=0.01°/h 陀螺零偏、db=100µg 加计零偏、初始姿态/位置误差 davp；
          DR 安装误差 dinst=[15,0,10]'、里程计尺度 dkod=0.05
  [解算] 主循环（每双子样 batch）：
        ins = miniins_step(ins, wm, vm)            # SINS 机械编排（free）
        dr.qnb = ins.qnb                          # **DR 姿态硬抄 SINS（锚定）**
        dr = mini_drupdate(dr, wm, dS)            # DR 航位推算
        kf: F = etm.m 逐块照搬（φ角 INS15 + dposD3 + dinst2 + dKod + dT = 22 维）
        每 10 个 IMU 样本量测 z = ins.pos - dr.pos（[lat,lon,h] 单位）-> 更新
        -> kffeedback 仅回灌速度 δv（对齐 PSINS test_SINS_DR 'v'）
  [输出] 组合解(修正后 ins) vs SINS-only(free) vs DR-only vs 真值：4 色叠加 + 残差 + 3D
验证结论（2026-08-24 与 PSINS 原版 test_SINS_DR.m 对拍）：
  - PSINS 原版：组合 pos RMS ≈ [10.4, 6.1, 11.0] m vs DR-only [43.2, 6.0, 26.7] m
  - 本迷你：组合水平 RMS ≈ 45.5 m vs DR-only 151 m vs SINS-only 345 m（3.3×/7.6× 改善）
  - 关键坑（易踩）：
    ① 反馈只清零已回灌的 δv，其余状态（φ/δr/dKod…）必须跨时间累积——若整个 x 清零，
       滤波器只剩 0.1s 记忆，dKod 等慢参数永远辨识不出（组合=DR-only）。
    ② etm.m 的线性索引是 MATLAB 列主序（M(2)=(2,1)），照搬时别按行主序读：
       Mva 实为 +askew(fn)（曾误为 -askew(fn)）。
    ③ R/P0 的 lat/lon 分量按 /Re 转弧度、h 保持米（poserrset 约定），三轴量纲不同。
    ④ 12 维（无 dKod）时组合=DR-only：KF 无法归因 DR 尺度误差，误把 SINS 速度拉向 DR。
    ⑤ 仅位置量测下 eb/db/dinst 弱可辨识会过拟合（eb=-4.7°/h 等荒谬值）；PSINS 原版
       同样只收敛 dKod/dT，dinst/eb/db 不收敛——这是固有弱可辨识性，非实现 bug。
教学简化（对拍 PSINS 允许差异）：随机游走省略（确定性）；trjsimu 无匀速阻尼；
  dS 用完美里程计近似（由 dkod 吸收尺度误差，22 维在线自标定）。
"""
import numpy as np

# ---------------- 常量（与 PSINS glvf 对齐） ----------------
Re, f, wie, g0 = 6378137.0, 1/298.257, 7.2921151467e-5, 9.7803267715
e2 = 2*f - f*f
deg, dph, ug = np.pi/180, np.pi/180/3600, 1e-6*g0
ts = 0.01                       # 100 Hz
nn = 2
nts = nn*ts                     # 双子样步长 0.02 s

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
    """q -> att=[pitch;roll;yaw]（PSINS base0/q2att.m 逐字对齐，NED 约定）"""
    q0,q1,q2,q3 = q
    pitch = np.arcsin(2*(q2*q3 + q0*q1))
    roll  = np.arctan2(-2*(q1*q3 - q0*q2), q0*q0 - q1*q1 - q2*q2 + q3*q3)
    yaw   = np.arctan2(-2*(q1*q2 - q0*q3), q0*q0 - q1*q1 + q2*q2 - q3*q3)
    return np.array([pitch, roll, yaw])

def a2qua(att):
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
    pos0 = trj[0, 6:9]
    pos = np.vstack([pos0, trj[:, 6:9]])
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

# ---------------- 迷你 drinit / mini_drupdate（P3，Td=0） ----------------
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

def mini_drupdate(dr, wm, dS):
    nts = dr['ts'] * wm.shape[0]
    wmm = wm.sum(0)
    dphim = cros(0.5*wm[0], wm[1])
    phim = wmm + dphim
    qnb12 = qmul(dr['qnb'], rv2q(phim/2))
    if np.ndim(dS) > 0 and len(dS) > 1:
        dSn = qmulv(qnb12, dr['Cbo'] @ dS)
    else:
        dSn = qmulv(qnb12, dr['prj'] * dS)
    dSn = rotv(np.array([0, 0, -dr['aos']*phim[2]/nts]), dSn)
    dr['vn'] = dSn / nts
    RMh, RNh, clRNh, wnin, gcc = earth(dr['pos'], dr['vn'])
    dr['Mpv'] = np.array([[0, 1/RMh, 0], [1/clRNh, 0, 0], [0, 0, 1]])
    dr['pos'] = dr['pos'] + dr['Mpv'] @ dSn
    dr['qnb'] = qmul(dr['qnb'], rv2q(phim - dr['Cnb'].T @ wnin * nts))
    dr['att'] = q2att(dr['qnb']); dr['Cnb'] = q2mat(dr['qnb'])
    dr['avp'] = np.concatenate([dr['att'], dr['vn'], dr['pos']])
    dr['distance'] = dr['distance'] + dr['kod'] * abs(dS)
    return dr

# ---------------- 分步 SINS（复刻 miniinspure 内循环，暴露 qnb/vn/pos/fn 供 KF/反馈） ----------------
class MiniINS:
    def __init__(self, avp0):
        self.att = avp0[0:3].copy()
        self.vn  = avp0[3:6].copy()
        self.pos = avp0[6:9].copy()
        self.qnb = a2qua(self.att)
        self.fn  = np.zeros(3)

    def step(self, wm, vm, bias_gyro=np.zeros(3), bias_acc=np.zeros(3)):
        wm = wm - bias_gyro*ts
        vm = vm - bias_acc*ts
        nts2 = nts/2
        wmm = wm.sum(0)
        dphim = cros(0.5*wm[0], wm[1])
        phim = wmm + dphim
        vmm = vm.sum(0)
        scullm = cros(0.5*wm[0], vm[1]) + cros(vm[0], 0.5*wm[1])
        dvbm = vmm + scullm
        RMh, RNh, clRNh, wnin, gcc = earth(self.pos, self.vn)
        fn = q2mat(self.qnb) @ (dvbm/nts)
        an = rotv(-wnin*nts2, fn) + gcc
        vn1 = self.vn + an*nts
        Mpv = np.array([[0, 1/RMh, 0], [1/clRNh, 0, 0], [0, 0, 1]])
        self.pos = self.pos + Mpv @ ((self.vn+vn1)/2)*nts
        self.vn = vn1
        self.qnb = qmul(rv2q(-wnin*nts), qmul(self.qnb, rv2q(phim)))
        self.att = q2att(self.qnb)
        self.fn = fn
        return self

# ---------------- KF：22 维（对齐 PSINS test_SINS_DR_def：INS15 + dposD3 + dinst2 + dKod + dT） ----------------
# 状态序：x[0:3]=φ, x[3:6]=δv, x[6:9]=δr([lat,lon,h] 弧度/米, 与 ins.pos 同单位),
#         x[9:12]=eb, x[12:15]=db, x[15:18]=dposD(同 δr 单位),
#         x[18:20]=dpitch/dyaw, x[20]=dKod, x[21]=dT
# 约定：与 PSINS 一致 —— z=ins.pos-dr.pos（[lat,lon,h] 单位），H[δr]=+I, H[dposD]=-I；
#       F 逐块照搬 etm.m（MATLAB 列主序线性索引已展开为矩阵形式）。x=est-true。
# 注：曾试过 16 维（去掉 eb/db）→ 位置 129.7m、dKod 过拟合 0.27，比 22 维更差：
#   eb/db 虽弱可观/会过拟合（PSINS 原版同样不收敛），但能吸收部分信号、改善位置。
N = 22
def build_F(qnb, vn, pos, fn, RMh, RNh, wnin):
    Cbn = q2mat(qnb)                       # C_b^n
    lat = pos[0]; sl = np.sin(lat); cl = np.cos(lat); tl = np.tan(lat); secl = 1.0/cl
    f_RMh = 1.0/RMh; f_RNh = 1.0/RNh; f_clRNh = 1.0/(RNh*cl)
    f_RMh2 = f_RMh**2; f_RNh2 = f_RNh**2
    vE_clRNh = vn[0]*f_clRNh; vE_RNh2 = vn[0]*f_RNh2; vN_RMh2 = vn[1]*f_RMh2
    O = np.zeros((3,3))
    wnie = np.array([0., wie*cl, wie*sl])
    # --- etm.m 各块（列主序索引 → 矩阵）---
    Maa = -askew(wnin)                                  # 姿态误差
    Mav = np.array([[0, -f_RMh, 0], [f_RNh, 0, 0], [f_RNh*tl, 0, 0]])
    Mp1 = np.array([[0,0,0], [-wnie[2],0,0], [wnie[1],0,0]])
    Mp2 = np.array([[0, 0, vN_RMh2], [0, 0, -vE_RNh2], [vE_clRNh*secl, 0, -vE_RNh2*tl]])
    Map = Mp1 + Mp2
    Avn = askew(vn); Awn = askew(wnin)
    Mva = askew(fn)                                     # 注意：etm 代码 = +askew(fn)
    Mvv = Avn@Mav - Awn
    Mvp = Avn@(Mp1 + Map)
    scl = sl*cl
    Mvp[2,0] -= g0*(2*5.2790414e-3 + 4*2.32718e-5*sl*sl)*scl   # 纬度方向重力梯度
    Mvp[2,2] += 3.086e-6                                       # 高度方向重力梯度
    Mpv = np.array([[0, f_RMh, 0], [f_clRNh, 0, 0], [0, 0, 1]])
    Mpp = np.array([[0, 0, -vN_RMh2], [vE_clRNh*tl, 0, -vE_RNh2*secl], [0, 0, 0]])
    F = np.zeros((N, N))
    F[0:3, 0:3]   = Maa; F[0:3, 3:6] = Mav; F[0:3, 6:9] = Map
    F[0:3, 9:12]  = -Cbn                                 # eb -> φ
    F[3:6, 0:3]   = Mva; F[3:6, 3:6] = Mvv; F[3:6, 6:9] = Mvp
    F[3:6, 12:15] = Cbn                                  # db -> δv
    F[6:9, 3:6]   = Mpv; F[6:9, 6:9] = Mpp
    F[9:12, 9:12]   = np.diag([-1e-4]*3)                 # eb 一阶马尔可夫（tau 大→≈0）
    F[12:15, 12:15] = np.diag([-1e-4]*3)                 # db
    # ---- dposD 块（etm kffk: Ft(16:18,[1:3,16:18,19:20,21])=[MpaD,MppD,MpkD(:,[1,3,2])]）----
    F[15:18, 0:3]   = Mpv @ askew(vn)                    # MpaD：φ -> dposD
    F[15:18, 15:18] = Mpp                                # MppD
    MvkD = np.linalg.norm(vn)*np.column_stack([-Cbn[:,2], Cbn[:,1], Cbn[:,0]])
    MpkD = Mpv @ MvkD
    F[15:18, 18:20] = MpkD[:, [0, 2]]                    # dpitch, dyaw -> dposD
    F[15:18, 20]    = MpkD[:, 1]                         # dKod -> dposD
    # dT：无动力学耦合，仅在量测 H[0:3,21] = -Mpv@vn（对应 PSINS Hk(:,22)=-Mpvvn）
    return F

def pos_to_meter(dlat, dlon, dh, RMh, RNh, lat):
    return np.array([dlon*RNh*np.cos(lat), dlat*RMh, dh])

def kf_predict(F, P, Q):
    Fd = np.eye(N) + F*nts
    return Fd @ P @ Fd.T + Q

def kf_update(x, P, H, R, z):
    S = H @ P @ H.T + R
    K = np.linalg.solve(S, H @ P.T).T          # K = P H^T S^-1
    x = x + K @ (z - H @ x)
    P = (np.eye(N) - K @ H) @ P @ (np.eye(N) - K @ H).T + K @ R @ K.T   # Joseph（保 PSD）
    return x, P, K

# ---------------- 主流程 ----------------
print("="*70)
print("拆解 PSINS ④：迷你 SINS+DR 组合导航（SINS 主导 + DR 辅助）")
print("="*70)

avp0 = np.array([0, 0, 0,  0, 0, 0,  29*deg, 106*deg, 450.0])

print("\n[1] 真值轨迹 + 完美里程计（100 Hz，双子样）")
imu, trj = minitrj(avp0, WAT, ts)
od = mini_odsimu(trj, 0, 1.0)
print(f"    imu 行数 = {len(imu)}（期望 96600），总里程 = {od[:,0].sum():.1f} m")

print("\n[2] 确定性误差注入")
eb = np.array([0.01, 0.01, 0.01])*dph        # 陀螺零偏 0.01°/h
db = np.array([100., 100., 100.])*ug         # 加计零偏 100 µg
davp = np.array([0.5, 0.5, 5.0])*(deg/60)    # 初始姿态误差 [0.5';0.5';5'](arcmin)
imu_e = imu.copy()
imu_e[:, 0:3] += eb*ts
imu_e[:, 3:6] += db*ts
att0e = avp0[0:3] + davp
avp0e = np.array([*att0e, 0.1, 0.1, 0.1, avp0[6]+10/Re, avp0[7]+10/(Re*np.cos(avp0[6])), avp0[8]+10])
# DR 误差（安装 + 尺度），仅 DR-only 与 22 维自标定用到
dinst = np.array([15, 0, 10])*(deg/60)
dkod  = 0.05

# ---------------- KF 初始协方差/噪声（对齐 PSINS test_SINS_DR_def） ----------------
# 过程噪声：Q = diag([web(3); wdb(3); zeros(16)])^2 —— 只在 φ/δv 有量，其余全 ~0
web = (0.001*deg)/np.sqrt(3600)      # 陀螺角度随机游走 0.001°/√h → rad/√s
wdb = 5e-6*g0/np.sqrt(1.0)           # 加计速度随机游走 5µg/√Hz → m/s²/√Hz
Q = np.diag([web**2]*3 + [wdb**2]*3 + [1e-14]*16)
# 量测噪声：位置量测 ~10m（对齐 PSINS davp(7:9)=10）。
# lat/lon 转弧度（/Re）、h 保持米（对齐 poserrset）
R = np.diag([(10.0/Re)**2, (10.0/Re)**2, 10.0**2])
# 初始 P0：diag([davp; eb; db; davp(7:9); dinst; dKod; dT]*10)^2，δv=0（PSINS vperrset(0,·)）
dposP0 = np.array([(100.0/Re)**2, (100.0/Re)**2, 100.0**2])
P0 = np.diag(np.concatenate([
    (davp*10)**2, np.zeros(3), dposP0,          # φ, δv(=0), δr
    (eb*10)**2, (db*10)**2,                     # eb, db
    dposP0,                                     # dposD
    (dinst[[0,2]]*10)**2, np.full(1, (dkod*10)**2), np.full(1, (0.01*10)**2),
])).astype(float)

# ---------------- 解算 1：SINS-only（free，无 KF，等价于 P2） ----------------
print("\n[3] SINS-only（free，无 DR/无 KF）")
ins_s = MiniINS(avp0e)
m = len(imu)//nn
avp_sins = np.zeros((m, 10)); ki = 0
for k in range(0, len(imu)-nn+1, nn):
    wm = imu_e[k:k+nn, 0:3]; vm = imu_e[k:k+nn, 3:6]
    ins_s.step(wm, vm)
    avp_sins[ki] = [*ins_s.att, *ins_s.vn, *ins_s.pos, imu[k+nn-1, 6]]
    ki += 1
avp_sins = avp_sins[:ki]

# ---------------- 解算 2：DR-only（自积分姿态，含 dinst/dkod 误差） ----------------
print("\n[4] DR-only（自积分姿态，含安装/尺度误差）")
dr_o = mini_drinit(avp0e, dinst, 1.0*(1+dkod), ts)
avp_dr = np.zeros((m, 10)); ki = 0
for k in range(0, len(imu)-nn+1, nn):
    wm = imu_e[k:k+nn, 0:3]; dS = od[k:k+nn, 0].sum()
    dr_o = mini_drupdate(dr_o, wm, dS)
    avp_dr[ki] = [*dr_o['avp'], imu[k+nn-1, 6]]
    ki += 1
avp_dr = avp_dr[:ki]

# ---------------- 解算 3：组合（SINS + DR 锚定 + KF + 反馈） ----------------
print("\n[5] 组合解（SINS 主导 + DR 辅助，22 维 KF 自标定）")
ins = MiniINS(avp0e)
dr = mini_drinit(avp0e, dinst, 1.0*(1+dkod), ts)
bias_gyro = np.zeros(3); bias_acc = np.zeros(3)
x = np.zeros(N); P = P0.copy()
avp_comb = np.zeros((m, 10)); ki = 0
xk_rec = []                      # 记录 KF 估计（自标定展示）
for ki in range(m):
    k = ki*nn
    wm = imu_e[k:k+nn, 0:3].copy(); vm = imu_e[k:k+nn, 3:6].copy()
    wm_c = wm - bias_gyro*ts; vm_c = vm - bias_acc*ts
    # SINS 前推
    ins.step(wm_c, vm_c)
    # DR 锚定姿态 = SINS
    dr['qnb'] = ins.qnb
    dS = od[k:k+nn, 0].sum()
    dr = mini_drupdate(dr, wm_c, dS)
    # KF 预测
    RMh, RNh, clRNh, wnin, gcc = earth(ins.pos, ins.vn)
    F = build_F(ins.qnb, ins.vn, ins.pos, ins.fn, RMh, RNh, wnin)
    P = kf_predict(F, P, Q)
    # 量测（每 5 个 batch = 10 个 IMU 样本，≈0.1 s）
    if (ki+1) % 5 == 0:
        z = ins.pos - dr['pos']            # [dlat,dlon,dh] 单位（与 PSINS 一致）
        H = np.zeros((3, N)); H[0:3, 6:9] = np.eye(3); H[0:3, 15:18] = -np.eye(3)
        Mpvvn = np.array([ins.vn[1]/RMh, ins.vn[0]/(RNh*np.cos(ins.pos[0])), ins.vn[2]])
        H[0:3, 21] = -Mpvvn                # dT -> 位置差（PSINS Hk(:,22)=-Mpvvn）
        x, P, K = kf_update(x, P, H, R, z)
        # 反馈（对齐 PSINS test_SINS_DR：仅速度闭环 'v'）：
        #   x = (est - true)，修正 = est - x → ins.vn -= x[3:6]。
        #   只清零已回灌的 δv（PSINS kffeedback 同样只把 xk(idx) 减去 xfb）；
        #   φ/δr/eb/db/dKod/dinst/dT 估计值跨时间累积 —— 这是 dKod 等慢参数
        #   能被在线辨识的前提（若整个 x 清零，滤波器只剩 0.1s 记忆，尺度误差永远估计不出）。
        ins.vn -= x[3:6]
        xk_rec.append(np.concatenate([x, [imu[k+nn-1, 6]]]))
        x[3:6] = 0.0
    avp_comb[ki] = [*ins.att, *ins.vn, *ins.pos, imu[k+nn-1, 6]]
avp_comb = avp_comb[:m]
xk = np.array(xk_rec)

# ---------------- 误差统计 ----------------
Re_h = Re + avp0[8]
def wrap_pi(a): return (a + np.pi) % (2*np.pi) - np.pi
def errstats(name, avp):
    trj_d = trj[1::2]
    n = min(len(avp), len(trj_d))
    de = avp[:n,0:3] - trj_d[:n,0:3]; de[:,2] = wrap_pi(de[:,2])
    dv = avp[:n,3:6] - trj_d[:n,3:6]
    dp = avp[:n,6:9] - trj_d[:n,6:9]
    dph = np.array([dp[:,0]*Re_h, dp[:,1]*Re_h*np.cos(avp0[6]), dp[:,2]]).T
    dhoriz = np.hypot(dph[:,0], dph[:,1])
    print(f"    [{name}] att RMS = ({np.abs(de).mean(0)[0]/deg*3600:.1f}, "
          f"{np.abs(de).mean(0)[1]/deg*3600:.1f}, {np.abs(de).mean(0)[2]/deg*3600:.1f}) arcsec"
          f" | vel RMS = {np.abs(dv).mean(0)} m/s")
    print(f"             水平位置 RMS = {dhoriz.mean():.1f} m, 末点 = {dhoriz[-1]:.1f} m"
          f" | 垂直 = {np.abs(dph[:,2]).mean():.1f} m (末 {dph[-1,2]:.1f} m)")

print("\n[6] 误差对比（vs 真值，966 s）")
errstats("SINS-only", avp_sins)
errstats("DR-only",   avp_dr)
errstats("组合(22维)", avp_comb)

# ---------------- 22 维自标定收敛总结 ----------------
tail = xk[-500:]                       # 末 50 s 平均（稳定段）
print("\n[6.5] 22 维在线自标定（末段 50s 平均 vs 注入真值）")
print(f"    dKod   = {tail[:,20].mean():+.4f}（真值 {dkod:+.2f}）"
      f" | dpitch = {tail[:,18].mean()/deg*60:+.1f}'（真值 {dinst[0]/deg*60:+.1f}'）"
      f" | dyaw = {tail[:,19].mean()/deg*60:+.1f}'（真值 {dinst[2]/deg*60:+.1f}'）")
print(f"    dT     = {tail[:,21].mean():+.4f} s（真值 0）"
      f" | eb = {tail[:,9:12].mean()/dph:+.3f} °/h（真值 {eb[0]/dph:+.2f}）"
      f" | db = {tail[:,12:15].mean()/ug:+.0f} µg（真值 {db[0]/ug:+.0f}）")

print("\n[7] 可视化（真值+三解算 4 色叠加 + 残差 + 3D）")
from miniplot import miniinsplot, miniavpcmpplot, miniinsplot3d
miniinsplot([avp_sins, avp_dr, avp_comb], trj, 'cmp_sinsdr',
            ['SINS-only', 'DR-only', 'Combined'])
miniavpcmpplot(trj, [avp_sins, avp_dr, avp_comb],
               ['SINS-only', 'DR-only', 'Combined'], outname='miniavpcmpplot_sinsdr.png')
miniinsplot3d([avp_sins, avp_dr, avp_comb], trj, 'cmp_sinsdr',
              ['SINS-only', 'DR-only', 'Combined'])

# 自标定收敛图（ASCII 标签，DejaVu 无中文）
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
tk = xk[:, -1]
fig, ax = plt.subplots(2, 2, figsize=(10, 7))
ax[0,0].plot(tk, xk[:,20], lw=1.2); ax[0,0].axhline(dkod, color='k', ls='--', lw=0.8)
ax[0,0].set_title('dKod (scale)'); ax[0,0].set_ylabel('[-]'); ax[0,0].grid(alpha=0.3)
ax[0,1].plot(tk, xk[:,18]/deg*60, lw=1.2, label='dpitch'); ax[0,1].plot(tk, xk[:,19]/deg*60, lw=1.2, label='dyaw')
ax[0,1].axhline(dinst[0]/deg*60, color='k', ls='--', lw=0.8)
ax[0,1].axhline(dinst[2]/deg*60, color='k', ls=':', lw=0.8)
ax[0,1].set_title('dinst (pitch/yaw)'); ax[0,1].set_ylabel('[arcmin]'); ax[0,1].legend(); ax[0,1].grid(alpha=0.3)
ax[1,0].plot(tk, xk[:,21], lw=1.2); ax[1,0].set_title('dT (time delay)'); ax[1,0].set_ylabel('[s]'); ax[1,0].grid(alpha=0.3)
ax[1,1].plot(tk, xk[:,9:12].mean(1)/dph, lw=1.2, label='eb'); ax[1,1].plot(tk, xk[:,12:15].mean(1)/ug, lw=1.2, label='db')
ax[1,1].set_title('eb / db (bias est.)'); ax[1,1].set_ylabel('[dph / ug]'); ax[1,1].legend(); ax[1,1].grid(alpha=0.3)
fig.tight_layout(); fig.savefig('sinsdr_calib.png', dpi=120); plt.close(fig)
print("    图已保存: sinsdr_calib.png（22 维自标定收敛）")
print("\n完成。")
