# gen_kf1d_py.py — 一维 KF Python 对照（读 MATLAB CSV 验证 + 独立复现）
import numpy as np
import csv, os

dt, N, v0, p0 = 1.0, 50, 5.0, 0.0
R = 25.0
Q = np.diag([1e-3, 1e-3])
Phi = np.array([[1, dt],[0, 1]])
Gamma = np.array([[dt**2/2, 0],[0, dt]])
H = np.array([[1.0, 0.0]])

# 优先读 MATLAB 的 CSV（含真值 p 和量测 z），用同一份数据跑 KF —— 严格对照
csv_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'kf1d_res.csv')
if os.path.exists(csv_path):
    rows = list(csv.reader(open(csv_path)))
    m = np.array([[float(v) for v in r] for r in rows])
    t = m[:,0]; p = m[:,1]; z = m[:,2]          # 与 MATLAB 完全相同的量测
    print('(使用 MATLAB 生成的同一份量测数据)')
else:
    rng = np.random.default_rng(42)
    t = np.arange(N+1, dtype=float)
    p = p0 + v0*t
    z = p + np.sqrt(R)*rng.standard_normal(N+1)

x = np.array([0.0, 0.0]); P = np.diag([100.0, 100.0])
xH = np.zeros((N+1, 2)); pH = np.zeros((N+1, 2)); xH[0] = x
for k in range(N+1):
    if k > 0:
        x = Phi @ x
        P = Phi @ P @ Phi.T + Gamma @ Q @ Gamma.T
    S = H @ P @ H.T + R
    K = (P @ H.T) / S
    r = z[k] - H @ x
    x = x + K.flatten()*r
    P = (np.eye(2) - K @ H) @ P
    xH[k] = x; pH[k] = [P[0,0], P[1,1]]

err = xH[:,0] - p
print('=== 一维 KF Python 复现 ===')
print(f'量测噪声 σ={np.sqrt(R):.0f} m; KF 稳态 σ_p={np.sqrt(pH[-1,0]):.3f} m ({np.sqrt(pH[-1,0])/np.sqrt(R)*100:.1f}% 于量测)')
print(f'速度估计 50s={xH[-1,1]:.3f} m/s (真值 5.00)')
print(f'位置最终误差={abs(err[-1]):.3f} m')

# 读 MATLAB CSV 对照（同数据 → 估计应逐位一致）
if os.path.exists(csv_path):
    diff_x = np.max(np.abs(m[:,3] - xH[:,0]))
    diff_v = np.max(np.abs(m[:,4] - xH[:,1]))
    print(f'MATLAB vs Python: 位置最大差={diff_x:.3e} m, 速度最大差={diff_v:.3e} m/s')
    print('（字节级一致 = 双轨验证通过）' if diff_x < 1e-9 else '（差异！）')
