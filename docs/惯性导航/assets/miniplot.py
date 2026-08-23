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


def miniinsplot(avp, ttl):
    """单条 avp 的 6 子图状态图（对应 insplot(avp,'avp')）。avp: (N,10) [att3,vn3,pos3,t]"""
    deg = np.pi / 180
    Re = 6378137.0
    t = avp[:, 9]
    lat0, lon0, h0 = avp[0, 6], avp[0, 7], avp[0, 8]
    x = (avp[:, 6] - lat0) * Re                 # 北
    y = (avp[:, 7] - lon0) * Re * np.cos(lat0)  # 东
    z = avp[:, 8] - h0
    dxyz = np.column_stack([x, y, z])

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
    plt.plot(x, y); plt.grid(); plt.axis('equal')
    plt.xlabel('North / m'); plt.ylabel('East / m'); plt.title('Trajectory (local ENU)')
    plt.subplot(3, 2, 5)
    plt.plot(t, dxyz); plt.grid()
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
