# 13 篇验证脚本：松组合(LC) vs 紧组合(TC) 的 H 矩阵与星数鲁棒性
# 纯 numpy，双轨自检（解析 H vs 有限差分雅可比）。
# 锚定 PSINS：test_SINS_GPS_153.m（LC，H=位置块单位阵）、
#             gnss/test/test_SINS_GPS_tightly_coupled.m + base/kf/kfhk.m + gnss/gps/rhoSatRec.m（TC，H=+LOS）

import numpy as np

np.set_printoptions(precision=4, suppress=True)

D = 20.0e6  # 卫星距接收机约 20000 km（几何演示用）

def dirvec(az_deg, el_deg):
    """局部 ENU(x东/y北/z天) 下，由方位/仰角得卫星方向单位矢量。"""
    az = np.deg2rad(az_deg); el = np.deg2rad(el_deg)
    return np.array([np.cos(el) * np.sin(az),
                     np.cos(el) * np.cos(az),
                     np.sin(el)])

# 6 颗卫星方向：覆盖多个仰角/方位，模拟良好几何
sats_dir = np.array([
    dirvec(0,   45),
    dirvec(120, 30),
    dirvec(240, 25),
    dirvec(60,  60),
    dirvec(300, 50),
    dirvec(180, 15),
])
n_sv = sats_dir.shape[0]

p_true = np.zeros(3)                         # 接收机真位置（局部系原点）
delta_p = np.array([50.0, -30.0, 10.0])     # INS 位置误差 (m)
p_ins = p_true + delta_p                     # INS 估计位置
sat_pos = p_true[None, :] + sats_dir * D     # 卫星位置 = 真位置 + 方向*D

def pred_rho(p):
    """INS 预测伪距：||sat - p||（每条卫星一行）。"""
    d = sat_pos - p[None, :]
    return np.sqrt(np.sum(d * d, axis=1))

def true_rho():
    return pred_rho(p_true)

rho_pred = pred_rho(p_ins)
rho_true = true_rho()
delta_rho = rho_true - rho_pred             # 新息 r = z - h(x)

# ---------- TC 伪距 H：每行 = +LOS（接收机->卫星单位矢量，落在位置块）----------
LOS = sat_pos - p_ins[None, :]
LOS = LOS / np.linalg.norm(LOS, axis=1, keepdims=True)
H_analytic = LOS

# ---------- 有限差分校验 ----------
EPS = 1e-3
H_fd = np.zeros((n_sv, 3))
for i in range(n_sv):
    for j in range(3):
        dp = np.zeros(3); dp[j] = EPS
        r_p = rho_true[i] - pred_rho(p_ins + dp)[i]
        r_m = rho_true[i] - pred_rho(p_ins - dp)[i]
        H_fd[i, j] = (r_p - r_m) / (2 * EPS)

max_err = np.max(np.abs(H_analytic - H_fd))
print("=== TC 伪距 H = +LOS（解析 vs 有限差分）===")
print("LOS 单位矢量（每行一颗卫星）:\n", LOS)
print("max|H_analytic - H_fd| =", max_err, " (≈ 差分截断误差，非建模误差)")

# ---------- LC 对照：GNSS-PVT 作量测，H = 位置块单位阵 ----------
H_LC = np.eye(3)
print("\n=== LC 对照：把 GNSS-PVT 当量测，H = I_3（位置块）===")
print("LC 新息 r = p_ins - p_gps；若 GNSS 位置无偏则 r = delta_p，H=I")

# ---------- 2 星部分可观性演示（LC 此时无 PVT、TC 仍可部分修正）----------
idx2 = [0, 1]
H2 = LOS[idx2]                              # 2x3
R2 = (5.0 ** 2) * np.eye(2)                # 伪距噪声 5 m
P = np.diag([100.0 ** 2, 100.0 ** 2, 100.0 ** 2])  # 位置误差协方差 (100 m std)
r2 = delta_rho[idx2]
S = H2 @ P @ H2.T + R2
K2 = P @ H2.T @ np.linalg.inv(S)
dx = K2 @ r2
P2 = (np.eye(3) - K2 @ H2) @ P
print("\n=== 仅 2 颗卫星：LC 无 PVT(需≥4) → 无更新；TC 仍可部分修正 ===")
print("更新前位置误差 |delta_p| =", round(np.linalg.norm(delta_p), 2), "m")
print("TC KF 修正量 dx =", np.round(dx, 2))
print("更新后位置误差 |delta_p - dx| =", round(np.linalg.norm(delta_p - dx), 2), "m")
print("更新后协方差 sqrt(diag) =", np.round(np.sqrt(np.diag(P2)), 2), "m")
# 垂直于 2 条 LOS 张成子空间的分量仍不可观（协方差不降）
observable = np.linalg.matrix_rank(H2)
print("H2 秩 =", observable, "（2 星只可观 2 维位置子空间，垂直方向仍漂）")
