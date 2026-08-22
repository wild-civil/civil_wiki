# gen_sins_error_py.py — 纯惯导误差传播 Python 对照（读 MATLAB CSV 重画 + 独立复现）
# 输出: sins_error_compare_py.png（对照图）
import numpy as np
import csv
import os

g = 9.8; R = 6371e3
ws = np.sqrt(g/R); Ts = 2*np.pi/ws
print(f'舒勒周期 Ts = {Ts/60:.1f} min')

# 独立复现（与 MATLAB 脚本同参数）
dr0 = 0.0; dv0 = 0.1
phi0 = 5/60*np.pi/180
dfN = 10e-5
dwE = 0.01*np.pi/180/3600

t = np.arange(0, 3601, 1.0)
sint = np.sin(ws*t); cost = np.cos(ws*t)
r_dr0 = np.full_like(t, dr0)
r_dv0 = dv0*sint/ws
r_phi0 = (g*phi0/ws**2)*(1-cost)
r_dfN = (dfN/ws**2)*(1-cost)
r_dwE = R*dwE*(sint/ws - t)
r_total = r_dr0 + r_dv0 + r_phi0 + r_dfN + r_dwE

# 数值积分（验证解析解）
dt = 1.0; N = len(t)
x = np.array([dr0, dv0, phi0]); xnum = np.zeros((3, N)); xnum[:,0] = x
for i in range(1, N):
    dx = np.array([x[1], g*x[2]+dfN, -x[1]/R-dwE])
    x = x + dx*dt
    xnum[:,i] = x

# 读 MATLAB CSV 对照
csv_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'sins_error_res.csv')
if os.path.exists(csv_path):
    with open(csv_path) as f:
        rows = list(csv.reader(f))
    m = np.array([[float(v) for v in r] for r in rows])
    t_m = m[:,0]; r_m = m[:,1]*1000   # km -> m
    diff = np.max(np.abs(r_m - r_total))
    print(f'MATLAB vs Python 位置差 (m): {diff:.3e}')
else:
    print('(sins_error_res.csv 不存在，跳过对照)')

print(f'60min 总位置误差: {np.max(np.abs(r_total)):.1f} m')
print(f'陀螺零偏项 60min: {np.max(np.abs(r_dwE)):.1f} m = {np.max(np.abs(r_dwE))/1852:.3f} 海里')
print(f'数值vs解析 位置差: {np.max(np.abs(xnum[0,:]-r_total)):.2e} m')

# 不同陀螺零偏
dws = np.array([0.001, 0.01, 0.1])*np.pi/180/3600
print('\n不同陀螺零偏 60min 发散 (海里):')
for dw in dws:
    rk = R*dw*(sint/ws - t)
    print(f'  {dw*180/np.pi*3600:.3f} deg/h -> {np.max(np.abs(rk))/1852:.3f} 海里')

# 输出关键结论
print('\n结论:')
print(f'  初始失准角 5\' -> 舒勒振荡幅度 {np.max(np.abs(r_phi0))/1000:.2f} km (有界, 84.4min 周期)')
print(f'  加计零偏 10 mGal -> 振荡幅度 {np.max(np.abs(r_dfN)):.1f} m (有界)')
print(f'  陀螺零偏 0.01 deg/h -> 60min 线性发散 {np.max(np.abs(r_dwE))/1852:.3f} 海里 (线性无界)')
