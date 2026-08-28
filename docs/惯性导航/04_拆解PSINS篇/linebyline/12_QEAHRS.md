# 12. QEKF 四元数扩展卡尔曼滤波 AHRS 逐行注释

> 🧩 **一句话**：用 7 维状态向量（四元数 4 + 陀螺零偏 3），通过 EKF 预测+量测更新，最优融合陀螺+加计+磁力计——比 Mahony 精度更高，因为有权重最优（协方差）融合。

> 💡 **学习心态**：如果你已经看了 09_kfupdate.md（卡尔曼滤波五公式），QEKF 就是它的一个**具体应用**——状态只有 7 维，量测只有 3 维，比 15 状态 SINS/GPS 组合简单得多。如果你还没看 09，也别怕，这里的 EKF 公式会从头推导。

---

## 📐 数学原理

### 1. 状态向量——为什么是 7 维？

$$\mathbf{x} = \begin{bmatrix} q_0 \\ q_1 \\ q_2 \\ q_3 \\ \varepsilon_{bx} \\ \varepsilon_{by} \\ \varepsilon_{bz} \end{bmatrix} = \begin{bmatrix} \mathbf{q} \\ \boldsymbol{\varepsilon}_b \end{bmatrix}_{7 \times 1}$$

| 状态 | 含义 | 单位 | 维度 |
|---|---|---|---|
| $\mathbf{q}=[q_0,q_1,q_2,q_3]^T$ | 姿态四元数 | 归一化（$\Vert\mathbf{q}\Vert=1$） | 4 |
| $\boldsymbol{\varepsilon}_b=[\varepsilon_{bx},\varepsilon_{by},\varepsilon_{bz}]^T$ | 陀螺三轴零偏 | rad/s | 3 |

**为什么四元数是 4 维而不是 3 维？** 四元数有 4 个元素但只有 3 个自由度（因为 $\|\mathbf{q}\|=1$ 约束）。用 4 维是因为四元数乘法没有奇异性（不像欧拉角有万向锁）。代价是 EKF 需要处理 4 维状态的冗余，归一化约束通过 L55 `qnormlz` 保证。

**为什么陀螺零偏是 3 维？** 陀螺三轴各自有恒定零偏（假设短时间内不变），作为状态可以**在线估计**。这是 QEKF 相比 Mahony 的核心优势——Mahony 只能通过积分项**隐含**估计零偏，QEKF 直接把零偏作为状态**显式**估计。

### 2. 状态方程——四元数微分方程

四元数微分方程：

$$\dot{\mathbf{q}} = \frac{1}{2}\mathbf{q} \otimes \bar{\boldsymbol{\omega}}$$

其中 $\bar{\boldsymbol{\omega}} = [0, \boldsymbol{\omega}^T]^T$ 是角速度的纯四元数形式，$\boldsymbol{\omega} = \tilde{\boldsymbol{\omega}} - \boldsymbol{\varepsilon}_b$（测量值减零偏）。

展开成矩阵形式：

$$\begin{bmatrix} \dot{q}_0 \\ \dot{q}_1 \\ \dot{q}_2 \\ \dot{q}_3 \end{bmatrix} = \frac{1}{2} \begin{bmatrix} -q_1 \omega_x - q_2 \omega_y - q_3 \omega_z \\ q_0 \omega_x + q_3 \omega_y - q_2 \omega_z \\ -q_3 \omega_x + q_0 \omega_y + q_1 \omega_z \\ q_2 \omega_x - q_1 \omega_y + q_0 \omega_z \end{bmatrix}$$

零偏状态方程：

$$\dot{\boldsymbol{\varepsilon}}_b = \mathbf{0}$$

（假设零偏在短时间内恒定不变）

### 3. 状态转移矩阵 $\Phi$ 的推导

EKF 需要状态转移矩阵 $\Phi = I + F \cdot T_s$（一阶离散化），其中 $F = \frac{\partial \dot{\mathbf{x}}}{\partial \mathbf{x}}$ 是雅可比矩阵。

对 $\mathbf{q}$ 部分：

$$\frac{\partial \dot{\mathbf{q}}}{\partial \mathbf{q}} = \frac{1}{2} \begin{bmatrix} 0 & -\omega_x & -\omega_y & -\omega_z \\ \omega_x & 0 & \omega_z & -\omega_y \\ \omega_y & -\omega_z & 0 & \omega_x \\ \omega_z & \omega_y & -\omega_x & 0 \end{bmatrix}$$

对 $\boldsymbol{\varepsilon}_b$ 部分：

$$\frac{\partial \dot{\mathbf{q}}}{\partial \boldsymbol{\varepsilon}_b} = \frac{1}{2} \begin{bmatrix} q_1 & q_2 & q_3 \\ -q_0 & q_3 & -q_2 \\ -q_3 & -q_0 & q_1 \\ q_2 & -q_1 & -q_0 \end{bmatrix}$$

（因为 $\boldsymbol{\omega} = \tilde{\boldsymbol{\omega}} - \boldsymbol{\varepsilon}_b$，所以 $\frac{\partial \boldsymbol{\omega}}{\partial \boldsymbol{\varepsilon}_b} = -\mathbf{I}$）

零偏对自身：

$$\frac{\partial \dot{\boldsymbol{\varepsilon}}_b}{\partial \boldsymbol{\varepsilon}_b} = \mathbf{0}_{3\times3}$$

零偏对四元数：

$$\frac{\partial \dot{\boldsymbol{\varepsilon}}_b}{\partial \mathbf{q}} = \mathbf{0}_{3\times4}$$

**完整雅可比矩阵** $F$（$7 \times 7$）：

$$F = \frac{1}{2} \begin{bmatrix} 0 & -\omega_x & -\omega_y & -\omega_z & q_1 & q_2 & q_3 \\ \omega_x & 0 & \omega_z & -\omega_y & -q_0 & q_3 & -q_2 \\ \omega_y & -\omega_z & 0 & \omega_x & -q_3 & -q_0 & q_1 \\ \omega_z & \omega_y & -\omega_x & 0 & q_2 & -q_1 & -q_0 \\ 0 & 0 & 0 & 0 & 0 & 0 & 0 \\ 0 & 0 & 0 & 0 & 0 & 0 & 0 \\ 0 & 0 & 0 & 0 & 0 & 0 & 0 \end{bmatrix}$$

**离散化**（一阶）：

$$\Phi = I + F \cdot T_s$$

> **对应代码**：QEAHRSUpdate L23-28 的 `eye(7) + [...] *nts/2`，其中矩阵就是 $F$（含 $\frac{1}{2}$ 系数），乘 $T_s$ 得 $\Phi$。

### 4. 量测模型——加计部分

加计测到的是重力在 b 系的投影。理论上，如果姿态完美：

$$\mathbf{f}^b_{\text{理论}} = (C_b^n)^T \begin{bmatrix} 0 \\ 0 \\ -g \end{bmatrix} = \text{第三行转置} \times (-g)$$

即 $f_x^b = -2(q_1 q_3 - q_0 q_2) \cdot g$，$f_y^b = -2(q_2 q_3 + q_0 q_1) \cdot g$，$f_z^b = -(q_0^2 - q_1^2 - q_2^2 + q_3^2) \cdot g$

量测用水平分量 $[f_x^b, f_y^b]$（对应 pitch 和 roll），去掉 $f_z$（因为 $f_z$ 含 $g$ 大小，提供不了额外信息）。

**量测雅可比 $H_{\text{acc}}$**（对四元数求偏导）：

$$H_{\text{acc}} = \frac{\partial [f_x^b, f_y^b]}{\partial [q_0, q_1, q_2, q_3]}$$

展开后：

$$h_{11} = f_x q_0 - f_y q_3 + f_z q_2$$
$$h_{12} = f_x q_1 + f_y q_2 + f_z q_3$$
$$h_{21} = f_x q_3 + f_y q_0 - f_z q_1$$
$$h_{22} = f_x q_2 - f_y q_1 - f_z q_0$$

$$H_{\text{acc}} = \begin{bmatrix} h_{11} & h_{12} & -h_{22} & -h_{21} & 0 & 0 & 0 \\ h_{21} & h_{22} & h_{12} & h_{11} & 0 & 0 & 0 \end{bmatrix} \times 2$$

> **对应代码**：QEAHRSUpdate L33-36。

### 5. 量测模型——磁力计部分

磁力计测到地磁场在 b 系的投影 $\mathbf{m}^b$。转到 n 系 $\mathbf{m}^n = C_b^n \mathbf{m}^b$，取水平分量算航向：

$$\psi = \arctan2(m_E^n, m_N^n) = \arctan2(m_x^n, m_y^n)$$

其中 $C_b^n$ 的前两行前两列元素：

$$m_E^n = C_{11} m_x^b + C_{12} m_y^b + C_{13} m_z^b$$
$$m_N^n = C_{21} m_x^b + C_{22} m_y^b + C_{23} m_z^b$$

航向对四元数的偏导（链式法则）：

$$H_{\text{mag}} = \frac{\partial \psi}{\partial [q_0, q_1, q_2, q_3]} = \frac{1}{C_{22}^2 + C_{12}^2} \begin{bmatrix} 2q_3 C_{22} + 2q_0 C_{12} \\ -2q_2 C_{22} - 2q_1 C_{12} \\ -2q_1 C_{22} + 2q_2 C_{12} \\ 2q_0 C_{22} - 2q_3 C_{12} \end{bmatrix}^T$$

> **对应代码**：QEAHRSUpdate L37-42。

### 6. 完整 EKF 流程

| 步骤 | 公式 | 代码位置 |
|---|---|---|
| **预测** $\mathbf{x}_{k|k-1} = \Phi \mathbf{x}_{k-1|k-1}$ | $\mathbf{q}_{k|k-1} = \mathbf{q}_{k-1} \otimes \text{rv2q}(\boldsymbol{\omega} \cdot T_s)$（隐含在 kfupdate 里） | kfupdate 预测步 |
| **协方差预测** $\mathbf{P}_{k|k-1} = \Phi \mathbf{P}_{k-1|k-1} \Phi^T + Q$ | 同标准 KF | kfupdate 预测步 |
| **量测** $\mathbf{z}_k = [f_x^b, f_y^b, \psi]^T$ | 加计水平 + 磁航向 | L47-54 |
| **增益** $\mathbf{K} = \mathbf{P}\mathbf{H}^T(\mathbf{H}\mathbf{P}\mathbf{H}^T+\mathbf{R})^{-1}$ | 同标准 KF | kfupdate 量测步 |
| **更新** $\mathbf{x}_{k|k} = \mathbf{x}_{k|k-1} + \mathbf{K}(\mathbf{z} - \mathbf{H}\mathbf{x}_{k|k-1})$ | 同标准 KF | kfupdate 量测步 |
| **归一化** $\mathbf{q} \leftarrow \mathbf{q}/\Vert\mathbf{q}\Vert$ | 四元数约束 | L55 |

> **关键**：QEKF 直接调用 PSINS 的通用 `kfupdate.m` 做预测+量测更新，自己只负责构建 $\Phi$、$H$、$R$ 三个矩阵。**这就是为什么先学 09_kfupdate.md 再看这里会非常轻松。**

### 7. 自适应 R 矩阵

QEAHRSUpdate L48-53 根据**水平加速度大小**动态调整 $R$：

$$\text{if } \|\mathbf{f}^n_{\text{水平}}\| > R_{0}: \quad R_{\text{acc}} = \frac{\|\mathbf{f}^n_{\text{水平}}\|}{R_0} \cdot \frac{R_{\text{acc},0}}{T_s}$$

$$\text{else}: \quad R_{\text{acc}} = \frac{R_{\text{acc},0}}{T_s}$$

**物理意义**：水平加速度大 = 有运动 = 加计测的不只是重力 = 不信任加计 → 增大 $R$ → KF 自动降低加计权重。

---

## 📝 逐行注释

### QEAHRSInit.m 逐行注释

> 🧩 **函数作用**：初始化 7 状态 QEKF AHRS。
>
> 源码：[QEAHRSInit.m](file:///workspace/psins/base/AHRS/QEAHRSInit.m)

| 行号 | 原代码 | 中文注释 | 公式/备注 |
|---|---|---|---|
| 1 | `function ahrs = QEAHRSInit(ts, att0, t0)` | QEKF AHRS 初始化 | 输入：采样间隔、初始姿态、初始时间 |
| 3 | `% X=[q0,q1,q2,q3,ebx,eby,ebz]'` | ★ 状态向量：四元数 4 + 陀螺零偏 3 = 7 维 | $\mathbf{x} = [q_0, q_1, q_2, q_3, \varepsilon_{bx}, \varepsilon_{by}, \varepsilon_{bz}]^T$ |
| 5 | `% Prototype: ahrs = QEAHRSInit(ts)` | ★ **函数原型**：调用方式 `ahrs = QEAHRSInit(ts)` | — |
| 6 | `% Inputs: ts - AHRS update interval` | **输入** ts = AHRS 更新间隔（s） | $T_s$ |
| 7 | `% Output: ahrs - output AHRS structure array` | ★ **输出** ahrs = AHRS 结构体（含 `kf` 子结构） | $\mathbf{x}_0, P_0, Q, R$ 等存在 `ahrs.kf` 里 |
| 14 | `global glv` | 全局变量 | — |
| 15-22 | `if ~exist('att0'...` | 初始姿态处理（同 MahonyInit） | 4 元素→四元数，3 元素→欧拉角转四元数 |
| 23 | `kf.Qt = diag([[10;10;10;10]*glv.dpsh; [10;10;10]*glv.dphpsh])^2;` | ★ 过程噪声 $Q$：四元数 $10°/\sqrt{h}$，零偏 $10°/h/\sqrt{h}$ | $Q = \text{diag}(Q_q, Q_{eb})$，表征系统不确定性 |
| 24 | `kf.Pxk = diag([[1;1;1;1]; [1000;1000;1000]*glv.dph])^2;` | ★ 初始协方差 $P_0$：四元数不确定度 1，零偏不确定度 $1000°/h$ | $P_0 = \text{diag}(P_q, P_{eb})$，零偏不确定度大 = 一开始不知道零偏多少 |
| 25 | `kf.Pmax = [[1;1;1;1]; [1000;1000;1000]*glv.dph].^2;` | 协方差上限（防止发散） | $P \leq P_{\max}$ |
| 26 | `kf.Pmin = [[1;1;1;1]*0.001; [1;1;1]*glv.dph].^2;` | 协方差下限（防止过度自信） | $P \geq P_{\min}$ |
| 27 | `kf.pconstrain = 1;` | 开启 P 约束 | 限制 $P \in [P_{\min}, P_{\max}]$ |
| 28 | `kf.Rk = diag([[10;10]*glv.mg; 10*glv.deg])^2;  kf.Rk0 = kf.Rk;` | ★ 量测噪声 $R$：加计 $10$mg（pitch/roll），磁力计 $10°$（yaw）；`Rk0` 存初始 $R$（自适应用） | $R = \text{diag}(R_{acc}, R_{mag})$，$R_0$ 是基准值 |
| 29 | `kf.Phikk_1 = eye(7);` | 初始状态转移矩阵 $= I$（每步重算） | $\Phi$ 在 QEAHRSUpdate 里每步更新 |
| 30 | `kf.Hk = zeros(3,7);` | 初始量测矩阵 $= 0$（每步重算） | $H$ 在 QEAHRSUpdate 里每步更新 |
| 31 | `kf.xk = [q; 0;0;0];` | ★ 初始状态：四元数 + 零偏 = 0 | $\mathbf{x}_0 = [q_0, q_1, q_2, q_3, 0, 0, 0]^T$ |
| 32 | `kf = kfinit0(kf, ts);` | KF 通用初始化（设置 ts 等） | — |
| 33 | `ahrs.kf = kf;` | 存回 ahrs 结构体 | — |
| 34 | `ahrs.Cnb = q2mat(kf.xk(1:4));` | 算初始方向余弦阵 | $C_b^n = \text{q2mat}(\mathbf{q})$ |
| 35 | `if ~exist('t0', 'var'), t0 = 0; end` | 默认初始时间 = 0 | — |
| 36 | `ahrs.tk = t0;` | 时间初始化 | — |

> 💡 **P0/Q/R 的量级直觉**：
> - $P_0$ 大 = "我不确定" → KF 初始会快速修正
> - $Q$ 大 = "系统噪声大" → KF 持续保持修正能力
> - $R$ 大 = "量测噪声大" → KF 少信任量测
> - 零偏 $P_0 = 1000°/h$：一开始完全不知道零偏多大 → 大初始不确定度
> - 加计 $R = 10$mg：MEMS 加计噪声约几 mg → 10mg 是合理保守值

### QEAHRSUpdate.m 逐行注释

> 🧩 **函数作用**：一步 QEKF AHRS 更新——构建 $\Phi$/$H$/$R$ → 调 kfupdate → 归一化。
>
> 源码：[QEAHRSUpdate.m](file:///workspace/psins/base/AHRS/QEAHRSUpdate.m)

| 行号 | 原代码 | 中文注释 | 公式/备注 |
|---|---|---|---|
| 1 | `function ahrs = QEAHRSUpdate(ahrs, imu, mag, ts)` | QEKF AHRS 一步更新 | — |
| 6 | `% Prototype: ahrs = QEAHRSUpdate(ahrs, gyro, acc, mag, ts)` | ★ **函数原型**（⚠️ 源码注释里写的是 `gyro, acc` 分开，但 L1 实际签名是 `imu` 合并传入，注释滞后于代码） | — |
| 7 | `% Inputs: ahrs - AHRS structure array` | **输入** ahrs = AHRS 结构体（由 QEAHRSInit 创建） | — |
| 8 | `%         imu - [wm, vm] gyro & acc increment samples` | **输入** imu = [角增量 $\boldsymbol{\phi}_m$, 速度增量 $\Delta\mathbf{v}_m$] 子样 | 多子样时 imu 是 $N \times 6$ 矩阵 |
| 9 | `%         mag  - magetic output in mGauss` | **输入** mag = 磁力计输出（mGauss） | $\mathbf{m}^b$ |
| 10 | `%         ts   - sample interval` | **输入** ts = 采样间隔（s） | $T_s$ |
| 11 | `% Output: ahrs - output AHRS structure array` | ★ **输出** ahrs = 更新后的 AHRS 结构体 | 含 $\hat{\mathbf{q}}, \hat{\boldsymbol{\varepsilon}}_b, C_b^n$ 等 |
| 18 | `[gyro, acc] = cnscl(imu);  nts = size(imu,1)*ts;` | 圆锥/划桨补偿（同 Mahony） | $\boldsymbol{\phi}_m, \Delta\mathbf{v}_m, T_s$ |
| 19 | `gyro = gyro/nts;  acc = acc/nts;` | ★ 角增量→角速度，速度增量→比力 | $\boldsymbol{\omega} = \boldsymbol{\phi}_m/T_s$，$\mathbf{f}^b = \Delta\mathbf{v}_m/T_s$ |
| 20 | `q0 = ahrs.kf.xk(1); q1 = ...; q3 = ...;` | 取出当前四元数 | — |
| 21 | `wx = gyro(1); wy = gyro(2); wz = gyro(3);` | 取出陀螺角速度 | $\boldsymbol{\omega} = [\omega_x, \omega_y, \omega_z]^T$ |
| 22 | `fx = acc(1);  fy = acc(2);  fz = acc(3);` | 取出加计比力 | $\mathbf{f}^b = [f_x, f_y, f_z]^T$ |
| 23-28 | `ahrs.kf.Phikk_1 = eye(7) + [...] *nts/2;` | ★★★ **状态转移矩阵 $\Phi$** | $\Phi = I + F \cdot T_s$，$F$ 是雅可比矩阵（见 §3 推导） |
| 24-27 | `0 -wx -wy -wz ...` | ★ $F$ 的四元数部分：$\frac{\partial \dot{\mathbf{q}}}{\partial \mathbf{q}}$ + $\frac{\partial \dot{\mathbf{q}}}{\partial \boldsymbol{\varepsilon}_b}$ | 见 §3 的 $F$ 矩阵 |
| 28 | `zeros(3,7)` | $F$ 的零偏行：$\frac{\partial \dot{\boldsymbol{\varepsilon}}_b}{\partial \mathbf{x}} = \mathbf{0}$ | 零偏恒定 → 导数 = 0 |
| 33 | `h11 = fx*q0-fy*q3+fz*q2;  h12 = fx*q1+fy*q2+fz*q3;` | ★ 加计量测雅可比元素 | $h_{11} = f_x q_0 - f_y q_3 + f_z q_2$，$h_{12} = f_x q_1 + f_y q_2 + f_z q_3$ |
| 34 | `h21 = fx*q3+fy*q0-fz*q1;  h22 = fx*q2-fy*q1-fz*q0;` | 加计量测雅可比元素（续） | $h_{21} = f_x q_3 + f_y q_0 - f_z q_1$，$h_{22} = f_x q_2 - f_y q_1 - f_z q_0$ |
| 35-36 | `ahrs.kf.Hk(1:2,:) = [h11 h12 -h22 -h21 0 0 0; h21 h22 h12 h11 0 0 0]*2;` | ★★ **加计量测矩阵 $H_{\text{acc}}$**（2 行：pitch+roll） | 见 §4 推导，$\times 2$ 来自四元数→DCM 的 2 倍系数 |
| 37 | `magH = ahrs.Cnb*mag;` | 磁力计转到 n 系 | $\mathbf{m}^n = C_b^n \mathbf{m}^b$ |
| 38 | `nm = norm(magH(1:2));` | 磁力计水平分量模值 | $\vert\mathbf{m}^n_{\text{水平}}\vert$ |
| 39 | `if nm>0` | 有水平磁场才算航向 | — |
| 40 | `yaw = atan2(magH(1), magH(2));` | ★ 磁力计算航向 | $\psi = \arctan2(m_E^n, m_N^n)$ |
| 41 | `C22 = ahrs.Cnb(2,2); C12 = ahrs.Cnb(1,2);` | 取 $C_b^n$ 的元素（航向偏导需要） | — |
| 42 | `ahrs.kf.Hk(3,:) = [2*q3*C22+2*q0*C12, ...] / (C22^2+C12^2);` | ★★ **航向量测矩阵 $H_{\text{mag}}$**（第 3 行） | $H_{\text{mag}} = \frac{\partial \psi}{\partial \mathbf{q}}$，见 §5 推导 |
| 43-45 | `else yaw=0; Hk(3,:)=zeros;` | 磁力计水平为 0 时不更新航向 | — |
| 47 | `fn = ahrs.Cnb*acc;` | 比力转到 n 系 | $\mathbf{f}^n = C_b^n \mathbf{f}^b$ |
| 48 | `nm = norm(fn(1:2));` | 水平加速度模值 | $\vert\mathbf{f}^n_{\text{水平}}\vert$ |
| 49 | `if nm>ahrs.kf.Rk0(1,1)` | 水平加速度 > 基准值 → 动态 | — |
| 50 | `ahrs.kf.Rk(1:2,1:2) = nm/Rk0(1,1)*Rk0(1:2,1:2)/nts;` | ★ 自适应 R：动态时加大 $R_{\text{acc}}$ | $R_{\text{acc}} = \frac{\vert f^n_{\text{水平}}\vert}{R_0} \cdot \frac{R_{\text{acc},0}}{T_s}$ |
| 51-52 | `else, ahrs.kf.Rk(1:2,1:2) = Rk0(1:2,1:2)/nts;` | 静态时用基准 $R$ | $R_{\text{acc}} = R_{\text{acc},0}/T_s$ |
| 54 | `ahrs.kf = kfupdate(ahrs.kf, [0;0; yaw]);` | ★★★ **调 PSINS 通用 KF 做预测+量测更新** | 量测 $\mathbf{z} = [0, 0, \psi]^T$，前 2 维是加计水平偏差（隐含在 Hk 里） |
| 55 | `ahrs.kf.xk(1:4) = qnormlz(ahrs.kf.xk(1:4));` | ★ 四元数归一化（KF 更新后 $\Vert\mathbf{q}\Vert \neq 1$） | $\mathbf{q} \leftarrow \mathbf{q}/\Vert\mathbf{q}\Vert$ |
| 56 | `ahrs.Cnb = q2mat(ahrs.kf.xk(1:4));` | 更新方向余弦阵 | $C_b^n = \text{q2mat}(\mathbf{q})$ |
| 57 | `ahrs.tk = ahrs.tk + nts;` | 时间推进 | $t \mathrel{+}= T_s$ |

> **L54 是整个 QEKF 的灵魂**：`kfupdate(ahrs.kf, [0;0; yaw])` 做了两件事：
> 1. **预测步**：用 L23-28 构建的 $\Phi$ 推演状态和协方差
> 2. **量测步**：用 L35-42 构建的 $H$ 和 L50-52 构建的 $R$ 做量测更新
>
> QEKF 自己**不做任何 KF 数学运算**，只负责构建 $\Phi$/$H$/$R$ 三个矩阵，然后交给通用 kfupdate。

> **L54 的量测 [0;0; yaw] 怎么理解？** 量测向量 $\mathbf{z} = [z_1, z_2, z_3]^T$：
> - $z_1, z_2$：加计水平分量的"测量值减预测值"的残差，这里写 0 是因为 $H$ 矩阵已经把预测值编进去了（$H \cdot \mathbf{x}$ 就是预测的加计值，量测值隐含在 acc 里）
> - $z_3$：磁航向角 yaw
>
> 严格来说 PSINS 的 kfupdate 内部会算 $\mathbf{z} - H\mathbf{x}$，所以这里传 `[0;0;yaw]` 实际上是 $H\mathbf{x}$ 和 $\mathbf{z}$ 的组合形式。如果看不懂没关系，记住"调 kfupdate 就完了"。

### test_AHRS_QEKF.m 逐行注释

> 源码：[test_AHRS_QEKF.m](file:///workspace/psins/demos/test_AHRS_QEKF.m)

| 行号 | 原代码 | 中文注释 | 公式/备注 |
|---|---|---|---|
| 1 | `glvs` | 初始化全局变量 | — |
| 2 | `ts = 0.1;` | 采样间隔 0.1s | $T_s = 0.1$s |
| 3 | `ahrs = QEAHRSInit(ts);` | 初始化 QEKF | 7 状态 EKF |
| 4 | `len = 100/ts; avp = zeros(len, 14);` | 跑 100 秒，1000 步 | — |
| 5 | `for k=1:len` | 主循环 | — |
| 6 | `ahrs = QEAHRSUpdate(ahrs, [[1,0,0]*0, [1,0,1/glv.deg]], [0;0;0], ts);` | 输入同 Mahony test，但磁力计=[0;0;0]（不用磁力计） | $\boldsymbol{\phi}_m=\mathbf{0}$, $\Delta\mathbf{v}_m=[1,0,1/glv.deg]^T$（z 分量=$1/glv.deg$，与 x 分量 1 之比 = $glv.deg=\tan 1°$，模拟 1° pitch） |
| 7 | `avp(k,:) = [m2att(ahrs.Cnb); ahrs.kf.xk(5:7); diag(ahrs.kf.Pxk); ahrs.tk];` | 存：欧拉角 + 零偏估计 + 协方差对角线 + 时间 | $\text{att}, \hat{\boldsymbol{\varepsilon}}_b, \text{diag}(P), t$ |
| 8 | `end` | — | — |
| 9-14 | `figure, subplot(...)` | 画 5 张图 | pitch/roll、yaw、零偏、四元数方差、零偏方差 |

> **和 test_AHRS_Mahony 的区别**：QEKF 跑 100s（Mahony 跑 50s），因为 EKF 收敛需要更长的时间来估计零偏。磁力计=[0;0;0] 表示这个 test 不用磁力计，只靠加计做 pitch/roll。

---

## 📊 Mahony vs QEKF 对比

| | Mahony | QEKF |
|---|---|---|
| **状态量** | 四元数 4 维（隐含） | 四元数 4 + 陀螺零偏 3 = 7 维 |
| **融合方法** | PI 互补滤波 | 扩展卡尔曼滤波 |
| **估计陀螺零偏** | ✅ 通过积分项隐含估计 | ✅ 显式作为状态估计 |
| **量测** | 加计+磁力计的叉积误差 | 加计水平分量+磁航向角 |
| **协方差** | 无（固定/自适应 PI 参数） | 有（$P$ 矩阵传播，自适应 $R$） |
| **最优性** | 频域互补（非最优） | 最小方差最优估计 |
| **计算量** | 小（无矩阵求逆） | 中（$3 \times 7$ 的 $H$ 矩阵，$7 \times 7$ 的 $P$ 矩阵） |
| **精度** | 中等 | 略高（有协方差最优融合） |
| **嵌入式友好** | ⭐⭐⭐（STM32 轻松跑 1kHz） | ⭐⭐（$7 \times 7$ 矩阵运算，但 H743 双精度 FPU 可应对） |
| **适合场景** | 飞控、简单 AHRS | 高精度 AHRS、需要零偏估计 |

> **做航姿板建议**：先上 Mahony 验证硬件 → 调好 PI 参数 → 再升级 QEKF 提升精度。Mahony 在 STM32H743 上跑 1kHz 毫无压力；QEKF $7 \times 7$ 矩阵跑 1kHz 也没问题（H743 有双精度 FPU，$7 \times 7$ 矩阵乘法约 343 次乘加，1kHz 下占 CPU <0.1%）。

---

## 🔍 断点调试建议

### 调试1：$\Phi$ 矩阵验证

在 QEAHRSUpdate L23 设断点：

```matlab
% 构建前
q0, q1, q2, q3  % 当前四元数
wx, wy, wz      % 当前角速度

% 手算 Φ 的 (1,2) 元素
phi12_man = -wx * nts / 2;
abs(ahrs.kf.Phikk_1(1,2) - (1 + 0) - phi12_man)  % =0 说明理解对了
% 注意：eye(7) 的 (1,2) = 0，加上 [...] * nts/2 的 (1,2) = -wx*nts/2
```

### 调试2：$H$ 矩阵验证

在 QEAHRSUpdate L36 之后设断点：

```matlab
% 加计部分 H (前2行)
ahrs.kf.Hk(1:2,:)

% 手算 h11, h12
h11_man = fx*q0 - fy*q3 + fz*q2;
h12_man = fx*q1 + fy*q2 + fz*q3;
% Hk(1,1) 应该 = h11*2, Hk(1,2) 应该 = h12*2
abs(ahrs.kf.Hk(1,1) - h11_man*2)  % <1e-15
```

### 调试3：协方差收敛验证

在 QEAHRSUpdate L54 设断点：

```matlab
% KF 更新前
ahrs.kf.Pxk  % 先验协方差
ahrs.kf.Hk   % 量测矩阵
ahrs.kf.Rk   % 量测噪声（注意自适应 R）

% KF 更新后（dbstep 过 L54）
ahrs.kf.Kk   % 卡尔曼增益（应该随 P 减小而减小）
ahrs.kf.Pxk  % 后验协方差（应该比更新前小）

% 四元数归一化前后
norm(ahrs.kf.xk(1:4))  % 归一化前，应该接近 1 但不等于 1
```

### 调试4：Mahony vs QEKF 对比

用同一组 IMU 数据跑两个算法：

```matlab
% 同一组数据，两个算法各跑一遍
ahrs1 = MahonyInit(4);
ahrs2 = QEAHRSInit(0.1);
% ... 循环更新 ...
att_mahony = m2att(ahrs1.Cnb);
att_qekf = m2att(ahrs2.Cnb);
norm(att_mahony - att_qekf)  % 稳态应该 <0.1°
```

---

## ❌ 初学者最容易踩的坑

1. **四元数没归一化**：L55 `qnormlz` 是**必须**的！KF 更新后 $\|\mathbf{q}\| \neq 1$，不归一化 → DCB 误差 → 姿态发散
2. **$\Phi$ 矩阵的 $\frac{1}{2}$ 系数忘了**：L28 的 `*nts/2` 包含 $\frac{1}{2}$，因为 $\dot{\mathbf{q}} = \frac{1}{2}\mathbf{q}\otimes\boldsymbol{\omega}$。移植时容易写成 `*nts` 忘了除 2
3. **$H$ 矩阵的 $\times 2$ 系数忘了**：L36 的 `*2` 来自四元数→DCM 的 $2$ 倍系数。DCM 元素含 $q_i q_j \times 2$ 项，所以偏导也有 2
4. **自适应 R 方向搞反**：L50 是动态时**增大** $R$（不信任加计），不是减小。写反了会导致动态时加计噪声被放大
5. **磁力计补偿忘了去东向**：Mahony 在 L39 做了 `bxyz(1:2)=[0;norm(...)]`，QEKF 在 L40 用 `atan2(magH(1), magH(2))` 只取航向。不做这步 → 磁倾角会污染 roll/pitch
6. **$P_0$ 设太小**：零偏初始 $P_0 = 1000°/h$ 看着大，但如果你设成 $1°/h$（以为零偏很小），KF 会认为"零偏很确定"→ 不去估计零偏 → 零偏实际存在但没被估出来 → 姿态持续漂移

---

## 🎯 配套练习

### 练习1：$\Phi$ 矩阵手算

在 QEAHRSUpdate L23 断点处，手算 $\Phi$ 的第 1 行：
```matlab
% 给定 q0=1, q1=0, q2=0, q3=0, wx=0.01, wy=0, wz=0
% Φ(1,:) = [1, -wx*Ts/2, -wy*Ts/2, -wz*Ts/2, q1*Ts/2, q2*Ts/2, q3*Ts/2]
phi1_man = [1, -wx*nts/2, 0, 0, 0, 0, 0];
norm(ahrs.kf.Phikk_1(1,:) - phi1_man)  % <1e-15
```

### 练习2：协方差收敛观察

跑 test_AHRS_QEKF.m，回答：
- `ahrs.kf.Pxk` 对角线随时间怎么变？应该单调递减然后收敛
- 四元数的方差（`Pxk(1:4)`）和零偏方差（`Pxk(5:7)`）哪个收敛更快？为什么？
- `ahrs.kf.Kk` 随时间怎么变？应该随 $P$ 减小而减小

### 练习3：自适应 R 观察

修改 test_AHRS_QEKF.m，在加计里加一个水平加速度（模拟动态）：
```matlab
ahrs = QEAHRSUpdate(ahrs, [[0,0,0], [0.5,0,1/glv.deg]], [0;0;0], ts);
%                                                     ^^^ 改成 0.5 = 有水平加速度
```
- $R$ 怎么变？应该比静态大
- 姿态收敛速度怎么变？应该变慢（因为 $R$ 大 = 少信任加计）

### 练习4：Mahony vs QEKF 对比

用同一组数据（比如 test 里的静态 pitch=1° 场景）跑两个算法，对比：
- 收敛时间：Mahony $\approx \tau$=4s，QEKF 收敛时间由 $P_0/Q/R$ 决定
- 稳态精度：QEKF 应该略好（最优融合）
- 零偏估计：QEKF 的 `kf.xk(5:7)` 是否收敛到 0？（因为模拟的陀螺没零偏）

### 练习5：嵌入式移植热身

把 QEAHRSUpdate.m 翻译成 C 伪代码，重点关注：
- L23-28 的 $\Phi$ 矩阵：$7 \times 7$ 矩阵赋值，C 里怎么写？（提示：可以用 `float Phi[7][7]` 数组）
- L54 的 `kfupdate`：需要哪些子函数？（提示：矩阵乘法、矩阵求逆、看 09_kfupdate.md 的 C 翻译）
- $7 \times 7$ 矩阵求逆：嵌入式上可以用简化方法吗？（提示：$\Phi$ 大部分是 0，$H$ 只有 3 行，可以分块运算）
