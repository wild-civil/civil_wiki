#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
迷你 insplot / avpcmpplot（自写零依赖，matplotlib 实现，与 MATLAB 版 miniinsplot.m / miniavpcmpplot.m 双轨一致）
借鉴 PSINS insplot(avp,'avp') / avpcmpplot 的布局意图，不调用 PSINS 任何函数。
"""
import numpy as np
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt


def miniinsplot(*args):
    """6 子图状态图（对应 insplot(avp,'avp')）。
    单轨迹模式:  miniinsplot(avp, ttl)                  -> 生成 miniinsplot_<ttl>.png
    对比(单解算): miniinsplot(dr, truth, ttl)           -> 轨迹子图叠 红(估计)+黑(真值)+红星(起点)
    对比(多解算): miniinsplot([s1,s2,...], truth, ttl)  -> 轨迹子图叠 黑(真值)+彩色(各解算)
    约定（统一）：真值永远画黑线（参考基准）；解算按配色循环（free=红、fix=蓝、…）。
    avp: (N,10) [att3,vn3,pos3,t]
    """
    deg = np.pi / 180
    Re = 6378137.0
    # ---------------- 参数解析 ----------------
    if len(args) == 2 and isinstance(args[1], str):
        avp = args[0]; truth = None; ttl = args[1]; iscmp = False; sols = []; labels = []
    elif len(args) >= 3 and isinstance(args[2], str):
        truth = args[1]; ttl = args[2]; iscmp = True
        if isinstance(args[0], (list, tuple)):
            sols = list(args[0])                 # 多解算：第一参为 list
        else:
            sols = [args[0]]                     # 单解算：第一参为矩阵
        avp = sols[0]                            # 其它 5 个子图以第一解算为准
        labels = args[3] if len(args) >= 4 else None
    else:
        raise ValueError('miniinsplot: 参数错误（应为 miniinsplot(avp,ttl) 或 miniinsplot([sols],truth,ttl)）')

    t = avp[:, 9]
    lat0, lon0, h0 = avp[0, 6], avp[0, 7], avp[0, 8]
    # 局部坐标 East-right / North-up（与 MATLAB 版一致）
    x = (avp[:, 7] - lon0) * Re * np.cos(lat0)   # East（右 / x）
    y = (avp[:, 6] - lat0) * Re                  # North（上 / y）
    z = avp[:, 8] - h0
    dxyz = np.column_stack([x, y, z])            # [East, North, Up]

    # 解算配色与标签（第一解算=红；free/fix 顺序调用即红/蓝）
    sol_cols = ['r-', 'b-', 'g-', 'm-', 'c-']
    if labels is None:
        if len(sols) == 1:
            labels = ['DR (est)']
        elif len(sols) == 2:
            labels = ['free', 'fix']
        else:
            labels = [f'sol{k+1}' for k in range(len(sols))]
    sol_lbl = labels

    plt.figure(figsize=(9, 7))
    plt.subplot(3, 2, 1)
    plt.plot(t, avp[:, 0] / deg, label='Pitch')
    plt.plot(t, avp[:, 1] / deg, label='Roll')
    plt.grid(); plt.xlabel('t / s'); plt.ylabel('(deg)'); plt.title('Pitch / Roll')
    plt.legend(loc='best')
    plt.subplot(3, 2, 2)
    plt.plot(t, avp[:, 2] / deg); plt.grid()
    plt.xlabel('t / s'); plt.ylabel('(deg)'); plt.title('Yaw')
    plt.subplot(3, 2, 3)
    plt.plot(t, avp[:, 3:6]); plt.grid()
    plt.xlabel('t / s'); plt.ylabel('(m/s)'); plt.title('Velocity (VE / VN / VU)')
    plt.legend(['VE', 'VN', 'VU'], loc='best')
    plt.subplot(3, 2, (4, 6))
    plt.plot(0, 0, 'rp')                          # 起点红星，不进入 legend
    if iscmp:
        handles, labels = [], []
        xt = (truth[:, 7] - lon0) * Re * np.cos(lat0)
        yt = (truth[:, 6] - lat0) * Re
        ht, = plt.plot(xt, yt, 'k-', lw=1.8)       # 真值（黑，参考基准）
        handles.append(ht); labels.append('Truth')
        allx = np.concatenate([xt]); ally = np.concatenate([yt])
        for k, s in enumerate(sols):
            xs = (s[:, 7] - lon0) * Re * np.cos(lat0)
            ys = (s[:, 6] - lat0) * Re
            h, = plt.plot(xs, ys, sol_cols[min(k, len(sol_cols) - 1)])
            handles.append(h); labels.append(sol_lbl[k])
            allx = np.concatenate([allx, xs]); ally = np.concatenate([ally, ys])
        mx, my = 0.02 * np.ptp(allx), 0.02 * np.ptp(ally)
        plt.xlim(allx.min() - mx, allx.max() + mx)
        plt.ylim(ally.min() - my, ally.max() + my)
        plt.title('Trajectory (Truth vs solutions)')
        plt.legend(handles, labels, loc='best')
    else:
        plt.plot(x, y)
        mx, my = 0.02 * np.ptp(x), 0.02 * np.ptp(y)
        plt.xlim(x.min() - mx, x.max() + mx)
        plt.ylim(y.min() - my, y.max() + my)
        plt.title('Trajectory (local ENU)')
    plt.grid(); plt.xlabel('East / m'); plt.ylabel('North / m')
    plt.subplot(3, 2, 5)
    plt.plot(t, dxyz[:, [1, 0, 2]]); plt.grid()   # 对齐 MATLAB dxyz(:,[2,1,3])=[North,East,Up]
    plt.xlabel('t / s'); plt.ylabel('(m)'); plt.title('Position offset from start')
    plt.legend([r'$\Delta N$', r'$\Delta E$', r'$\Delta H$'], loc='best')
    plt.tight_layout()
    plt.savefig(f'miniinsplot_{ttl}.png', dpi=100)
    plt.close()
    print(f'    图已保存: miniinsplot_{ttl}.png')


def miniavpcmpplot(trj, avps, names, outname='miniavpcmpplot.png'):
    """真值 vs 多条解算的残差对比图（对应 avpcmpplot）。trj: (N,10) 100Hz；avps: list of (M,10) 双子样"""
    deg = np.pi / 180
    Re = 6378137.0
    dph = deg / 3600
    lat0 = trj[0, 6]
    trj_d = trj[1::2]                          # 双子样对齐（时刻 1,3,5,...*ts）
    n = len(avps)
    cmap = plt.get_cmap('tab10')
    cols = [cmap(i) for i in range(n)]

    plt.figure(figsize=(9, 7))
    # (311) attitude error (arcsec)
    plt.subplot(3, 1, 1); plt.grid()
    att_rms = []
    for k, avp in enumerate(avps):
        m = min(avp.shape[0], trj_d.shape[0])
        de = avp[:m, 0:3] - trj_d[:m, 0:3]
        de[:, 2] = (de[:, 2] + np.pi) % (2 * np.pi) - np.pi
        plt.plot(trj_d[:m, 9], de / dph, color=cols[k])
        att_rms.append(np.sqrt(np.mean(de ** 2)) / dph)
    plt.xlabel('t / s'); plt.ylabel('(arcsec)')
    plt.title(f'Attitude error   RMS = {np.mean(att_rms):.0f} arcsec')
    plt.legend(names, loc='best')
    # (312) velocity error (m/s)
    plt.subplot(3, 1, 2); plt.grid()
    vel_rms = []
    for k, avp in enumerate(avps):
        m = min(avp.shape[0], trj_d.shape[0])
        dv = avp[:m, 3:6] - trj_d[:m, 3:6]
        plt.plot(trj_d[:m, 9], dv, color=cols[k])
        vel_rms.append(np.sqrt(np.mean(dv ** 2)))
    plt.xlabel('t / s'); plt.ylabel('(m/s)')
    plt.title(f'Velocity error   RMS = {np.mean(vel_rms):.4f} m/s')
    # (313) position error (m)
    plt.subplot(3, 1, 3); plt.grid()
    pos_rms = []
    for k, avp in enumerate(avps):
        m = min(avp.shape[0], trj_d.shape[0])
        dp = avp[:m, 6:9] - trj_d[:m, 6:9]
        dph_ = np.column_stack([dp[:, 0] * Re, dp[:, 1] * Re * np.cos(lat0), dp[:, 2]])
        plt.plot(trj_d[:m, 9], dph_, color=cols[k])
        pos_rms.append(np.sqrt(np.mean(dph_ ** 2)))
    plt.xlabel('t / s'); plt.ylabel('(m)')
    plt.title(f'Position error   RMS = {np.mean(pos_rms):.1f} m')
    plt.legend(names, loc='best')
    plt.tight_layout()
    plt.savefig(outname, dpi=100)
    plt.close()
    print(f'    图已保存: {outname}')
