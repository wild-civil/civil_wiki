# gen_ekf_vs_eskf_py.py — 直接法 EKF vs ESKF Python 对照（读 MATLAB CSV 同一份量测）
import numpy as np
import csv, os

csv_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'ekf_vs_eskf_res.csv')
if not os.path.exists(csv_path):
    print('(ekf_vs_eskf_res.csv 不存在，先跑 MATLAB)'); raise SystemExit
rows = list(csv.reader(open(csv_path)))
m = np.array([[float(v) for v in r] for r in rows])
t = m[:,0]; xt = m[:,1]; yt = m[:,2]; zx = m[:,3]; zy = m[:,4]
xEh_mat = m[:,5:9]; xNh_mat = m[:,9:13]

dt, T = 1.0, 100.0
Rc, w = 100.0, 0.05
v_true = Rc*w
N = int(T/dt)

def wrap(ang):
    return (ang + np.pi) % (2*np.pi) - np.pi

# —— 直接法 EKF ——
xE = np.array([xt[0], yt[0], w*0 + np.pi/2 + 30*np.pi/180, v_true])
PE = np.diag([25, 25, (30*np.pi/180)**2, 1])
QE = np.diag([1e-3, 1e-3, 1e-6, 1e-3])
Hz = np.array([[1,0,0,0],[0,1,0,0]]); Rz = 25*np.eye(2)
xEh = np.zeros((N+1,4)); 
def meas_update(x, P, z):
    S = Hz@P@Hz.T + Rz
    K = P@Hz.T @ np.linalg.inv(S)
    r = z - Hz@x
    x = x + K@r
    P = (np.eye(4) - K@Hz)@P
    return x, P
xE, PE = meas_update(xE, PE, np.array([zx[0], zy[0]]))   # k=0 量测更新（对齐 MATLAB）
xEh[0] = xE
for k in range(1, N+1):
    xE[0] += xE[3]*np.cos(xE[2])*dt
    xE[1] += xE[3]*np.sin(xE[2])*dt
    xE[2] += w*dt
    F = np.array([[1,0,-xE[3]*np.sin(xE[2])*dt, np.cos(xE[2])*dt],
                  [0,1, xE[3]*np.cos(xE[2])*dt, np.sin(xE[2])*dt],
                  [0,0,1,0],[0,0,0,1]])
    PE = F@PE@F.T + QE
    xE, PE = meas_update(xE, PE, np.array([zx[k], zy[k]]))
    xEh[k] = xE

# —— ESKF ——
xN = np.array([xt[0], yt[0], np.pi/2 + 30*np.pi/180, v_true])
dx = np.zeros(4); Pd = np.diag([25, 25, (30*np.pi/180)**2, 1]); Qd = QE.copy()
Hd = Hz.copy()
xNh = np.zeros((N+1,4))
def meas_update_d(xN, dx, Pd, z):
    S = Hd@Pd@Hd.T + Rz
    K = Pd@Hd.T @ np.linalg.inv(S)
    r = z - np.array([xN[0], xN[1]])
    dx = dx + K@r
    Pd = (np.eye(4) - K@Hd)@Pd
    xN = xN + dx
    dx = np.zeros(4)
    return xN, dx, Pd
xN, dx, Pd = meas_update_d(xN, dx, Pd, np.array([zx[0], zy[0]]))   # k=0（对齐 MATLAB）
xNh[0] = xN
for k in range(1, N+1):
    xN[0] += xN[3]*np.cos(xN[2])*dt
    xN[1] += xN[3]*np.sin(xN[2])*dt
    xN[2] += w*dt
    Fd = np.array([[1,0,-xN[3]*np.sin(xN[2])*dt, np.cos(xN[2])*dt],
                   [0,1, xN[3]*np.cos(xN[2])*dt, np.sin(xN[2])*dt],
                   [0,0,1,0],[0,0,0,1]])
    dx = Fd@dx
    Pd = Fd@Pd@Fd.T + Qd
    xN, dx, Pd = meas_update_d(xN, dx, Pd, np.array([zx[k], zy[k]]))
    xNh[k] = xN

errE = np.sqrt((xEh[:,0]-xt)**2 + (xEh[:,1]-yt)**2)
errN = np.sqrt((xNh[:,0]-xt)**2 + (xNh[:,1]-yt)**2)
psiE = wrap(xEh[:,2] - (w*t + np.pi/2))
psiN = wrap(xNh[:,2] - (w*t + np.pi/2))

print('=== Python 复现 ===')
print(f'位置 RMSE 全程 : EKF {np.sqrt(np.mean(errE**2)):.2f} | ESKF {np.sqrt(np.mean(errN**2)):.2f} m')
print(f'直接法 vs ESKF 估计差: max={np.max(np.abs(xEh-xNh)):.3e} m（等价性实证）')
dE = np.max(np.abs(xEh - xEh_mat)); dN = np.max(np.abs(xNh - xNh_mat))
print(f'MATLAB vs Python: 直接法最大差={dE:.3e} | ESKF最大差={dN:.3e}')
print('（字节级一致 = 双轨验证通过）' if max(dE,dN) < 1e-9 else '（差异！）')
