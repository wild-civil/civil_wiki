# 11. Mahony 互补滤波 AHRS 逐行注释

> 🧩 **一句话**：用陀螺做高频预测，用加计+磁力计做低频校正，PI 控制器把两者"互补"融合——只解姿态，不解位置。

> 💡 **学习心态**：这一章比 insupdate 简单——没有速度/位置更新，没有科里奥利/地球曲率，**只关心姿态一个量**。如果你看完了 03\_insupdate，这里会觉得很轻松；如果你还没看 insupdate，从这里入门反而更容易。

***

## 📐 数学原理

### 1. 核心矛盾：陀螺 vs 加计+磁力计

| 传感器     | 优点          | 缺点             | 频率特性    |
| ------- | ----------- | -------------- | ------- |
| **陀螺**  | 高频响应快，动态准   | 有零偏，长时间漂移      | 高通（短期好） |
| **加计**  | 静态测重力方向准，不漂 | 动态时分不清重力+运动加速度 | 低通（长期好） |
| **磁力计** | 测地磁方向，提供航向  | 受铁磁干扰          | 低通（长期好） |

**互补滤波的核心思想**：用陀螺做高频预测，用加计+磁力计做低频校正，两者在频域上"互补"。

### 2. 姿态误差的物理来源

假设真实姿态为 $C_b^n$，陀螺测得的角速度 $\tilde{\boldsymbol{\omega}} = \boldsymbol{\omega} + \boldsymbol{\varepsilon}$（含零偏 $\boldsymbol{\varepsilon}$）。

如果直接用陀螺积分：$\mathbf{q}_{k+1} = \mathbf{q}_k \otimes \text{rv2q}(\tilde{\boldsymbol{\omega}} \cdot T_s)$，零偏 $\boldsymbol{\varepsilon}$ 会导致姿态误差**线性发散**。

**怎么办？** 用加计和磁力计来"纠正"陀螺。

### 3. 加计误差推导——叉积怎么来的？

加计在 b 系测到的比力 $\mathbf{f}^b$，静态时 $\mathbf{f}^b = -\mathbf{g}^b$（重力在 b 系的投影）。

当前姿态矩阵 $C_b^n$ 的**第三行** $(C_b^n)_{3,:}$ 就是当前姿态认为的"天向"在 b 系的表示。

理论上，如果姿态完美，$\mathbf{f}^b$ 应该和 $(C_b^n)_{3,:}$ 完全平行。

如果有姿态误差 $\boldsymbol{\phi}$，$\mathbf{f}^b$ 和 $(C_b^n)_{3,:}$ 不平行，有一个小夹角。

**用叉积来度量这个偏差**：

$\mathbf{e}_{\text{acc}} = (C_b^n)_{3,:}^T \times \hat{\mathbf{f}}^b$

其中 $\hat{\mathbf{f}}^b = \mathbf{f}^b / \|\mathbf{f}^b\|$ 是归一化后的加计测量。

**为什么用叉积？** 两个单位向量的叉积 = $\sin\theta$（沿旋转轴方向），正好给出"把当前姿态往哪转才能对齐重力"的方向和大小。

数学推导（小角度近似）：

$\mathbf{e}_{\text{acc}} = \begin{bmatrix} 0 \\ 0 \\ 1 \end{bmatrix} \times \begin{bmatrix} f_x \\ f_y \\ f_z \end{bmatrix}_{\text{归一化}} = \begin{bmatrix} -f_y \\ f_x \\ 0 \end{bmatrix}$

这正好对应 pitch 和 roll 的误差（不含 yaw）。

### 4. 磁力计误差推导

磁力计在 b 系测到 $\mathbf{m}^b$。理论参考磁场 $\mathbf{w}^b$（由 n 系参考磁场 $C_b^n \mathbf{m}^b$ 投影回来）：

$\mathbf{e}_{\text{mag}} = \mathbf{w}^b \times \hat{\mathbf{m}}^b$

**为什么磁力计只修正航向？** PSINS 在 [MahonyUpdate.m](file:///workspace/psins/base/AHRS/MahonyUpdate.m#L39) L39 做了关键一步——把 n 系磁场的东向分量清零：

$\mathbf{b}^n = \begin{bmatrix} 0 \\ \|\mathbf{m}^n_{\text{水平}}\| \\ m^n_z \end{bmatrix}$

这样参考磁场只包含北向和垂向，**不含东向** → 叉积误差只在航向上有分量，不会污染 pitch/roll。

### 5. PI 控制器设计

把加计误差 + 磁力计误差加起来：

$\mathbf{e} = \mathbf{e}_{\text{acc}} + \mathbf{e}_{\text{mag}}$

用 PI 控制器生成陀螺修正量：

$\boldsymbol{\varepsilon}_{\text{反馈}} = K_p \cdot \mathbf{e} + K_i \int_0^t \mathbf{e} \, d\tau$

- **P 部分** $K_p \cdot \mathbf{e}$：比例修正，快速消除当前误差
- **I 部分** $K_i \int \mathbf{e}\,dt$：积分修正，消除恒定陀螺零偏（零偏是常数 → 误差恒定 → 积分不断增长 → 抵消零偏）

### 6. 传递函数推导

MahonyInit 的注释里写了一个传递函数：

$\delta\mathbf{q}(s) = \frac{sK_p + K_i}{s^2 + K_p s + K_i} \cdot \mathbf{f}_b(s) + \frac{s}{s^2 + K_p s + K_i} \cdot \mathbf{w}_b(s)$

**怎么来的？**

系统方程（简化为一阶）：

- $\dot{\boldsymbol{\phi}} = -\boldsymbol{\varepsilon}_{\text{反馈}} + \mathbf{w}_b$（误差动力学，$\boldsymbol{\phi}$ 是姿态误差角）
- $\boldsymbol{\varepsilon}_{\text{反馈}} = K_p \mathbf{e} + K_i \int \mathbf{e}\,dt$
- $\mathbf{e} \approx \boldsymbol{\phi}$（小角度下，叉积误差 ≈ 姿态误差角）

合并得：

$\ddot{\boldsymbol{\phi}} + K_p \dot{\boldsymbol{\phi}} + K_i \boldsymbol{\phi} = \dot{\mathbf{w}}_b$

拉普拉斯变换：

$s^2 \boldsymbol{\phi}(s) + K_p s \boldsymbol{\phi}(s) + K_i \boldsymbol{\phi}(s) = s \cdot \mathbf{w}_b(s)$

$\frac{\boldsymbol{\phi}(s)}{\mathbf{w}_b(s)} = \frac{s}{s^2 + K_p s + K_i}$

这是从陀螺噪声 $\mathbf{w}_b$ 到姿态误差 $\boldsymbol{\phi}$ 的传递函数——**高通**（陀螺高频噪声通过，低频被滤掉）。

同理，从加计误差（低频参考）到姿态误差的传递函数：

$\frac{\boldsymbol{\phi}(s)}{\mathbf{f}_b(s)} = \frac{sK_p + K_i}{s^2 + K_p s + K_i}$

这是**低通**（加计低频信号通过，高频被滤掉）。

### 7. 临界阻尼设计——$K_p$ 和 $K_i$ 怎么取？

分母 $s^2 + K_p s + K_i$ 要设计成**临界阻尼**（既不过冲也不振荡）：

$s^2 + K_p s + K_i = s^2 + 2\beta s + \beta^2 = (s + \beta)^2$

所以：

- $K_p = 2\beta$
- $K_i = \beta^2$
- $\beta = 1/\tau$，$\tau$ 是时间常数

PSINS 的经验系数：$\beta = 2.146/\tau$（2.146 是严老师调的经验值，比理论 $1/\tau$ 略大）。

**$\tau$** **的物理意义**：系统从误差衰减到 63% 所需的时间。$\tau=4$s 意味着姿态误差每 4 秒衰减到原来的 37%。

### 8. 最终姿态更新公式

$\boxed{\mathbf{q}_{k+1} = \mathbf{q}_k \otimes \text{rv2q}\left(\boldsymbol{\phi}_m - \boldsymbol{\varepsilon}_{\text{反馈}} \cdot T_s\right)}$

- $\boldsymbol{\phi}_m$：陀螺角增量（经圆锥补偿）
- $\boldsymbol{\varepsilon}_{\text{反馈}} \cdot T_s$：PI 反馈的修正量
- 两者相减 = "陀螺说转了这么多，但 PI 说要修正一些" → 净转动量

**如果加计和陀螺完全一致（静态）**：误差 $\mathbf{e} \approx 0$，$\boldsymbol{\varepsilon}_{\text{反馈}} \approx 0$，退化为纯陀螺积分。

> **如果加计检测到偏差**：$\mathbf{e} \neq 0$，$\boldsymbol{\varepsilon}_{\text{反馈}} \neq 0$，把陀螺增量往加计方向"拉"。

### 9. rv2q 是什么？——旋转向量转四元数

公式里反复出现的 `rv2q` 是 **rotation vector to quaternion** 的缩写——把旋转向量转换为四元数。

**旋转向量** $\boldsymbol{\phi}$：方向 = 旋转轴，大小 = 旋转角（rad）。

**转换公式**：

$$\mathbf{q} = \text{rv2q}(\boldsymbol{\phi}) = \begin{bmatrix} \cos\left(\frac{\vert\boldsymbol{\phi}\vert}{2}\right) \\ \frac{\boldsymbol{\phi}}{\vert\boldsymbol{\phi}\vert} \sin\left(\frac{\vert\boldsymbol{\phi}\vert}{2}\right) \end{bmatrix}$$

其中 $\vert\boldsymbol{\phi}\vert$ 是旋转向量的模（即旋转角度）。

**举例**：绕 z 轴转 10° → $\boldsymbol{\phi} = [0, 0, 10° \times \frac{\pi}{180}]^T$ → $\text{rv2q}(\boldsymbol{\phi})$ 给出对应的四元数。

> **为什么用 rv2q 而不是直接四元数微分？** rv2q 是**精确的大角度转换**，没有小角度近似。在 insupdate L46 和 MahonyUpdate L49 都用它做姿态更新：先算出"这一步要转多少"（旋转向量），再转成四元数做乘法。比 $\dot{q} = \frac{1}{2}q \otimes \omega$ 的一阶欧拉法精度更高。

***

## 📝 逐行注释

### MahonyInit.m 逐行注释

> 🧩 **函数作用**：初始化 Mahony AHRS 结构体，设置 PI 控制器参数。
>
> 源码：[MahonyInit.m](file:///workspace/psins/base/AHRS/MahonyInit.m)

| 行号    | 原代码                                                                                             | 中文注释                                                                              | 公式/备注                                       |
| ----- | ----------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------- | ------------------------------------------- |
| 1     | `function ahrs = MahonyInit(tau, att0, t0)`                                                     | Mahony AHRS 初始化函数                                                                 | 输入：时间常数 $\tau$（s）、初始姿态 att0、初始时间 t0         |
| 2-6   | `% The initialization ... dq = ...`                                                             | 注释：传递函数 $\delta q = \frac{sK_p+K_i}{s^2+sK_p+K_i}f_b + \frac{s}{s^2+sK_p+K_i}w_b$ | 见 §6 推导                                     |
| 8     | `% Prototype: ahrs = MahonyInit(tau)`                                                           | ★ **函数原型**：调用方式 `ahrs = MahonyInit(tau)`                                          | —                                           |
| 9-11  | `% Inputs: tau - time constant, Delta(s) = s^2+Kp*s+Ki = s^2+2*beta*s+beta^2, where beta = 1/tau` | **输入** tau = 时间常数（s）                                                              | $\Delta(s)=s^2+2\beta s+\beta^2$，$\beta=1/\tau$，临界阻尼二阶系统 |
| 12    | `%        att0 - initial attitude`                                                              | **输入** att0 = 初始姿态（可省略）                                                           | 4 元素→四元数，3 元素→欧拉角                           |
| 13    | `%        t0   - initial time`                                                                  | **输入** t0 = 初始时间（可省略）                                                             | —                                           |
| 14    | `% Output: ahrs - output AHRS structure array`                                                  | ★ **输出** ahrs = AHRS 结构体                                                          | 含 $K_p, K_i, \mathbf{q}, C_b^n$ 等          |
| 20    | `% 07/06/2017`                                                                                  | 版权日期                                                                              | —                                           |
| 21    | `if ~exist('att0', 'var')`                                                                      | 如果没传初始姿态                                                                          | —                                           |
| 22    | `q = [1;0;0;0];`                                                                                | 默认四元数 = 单位姿态                                                                      | $\mathbf{q} = [1,0,0,0]^T$ = 无旋转            |
| 24-27 | `la = length(att0); if la==4, q = att0; elseif la==0, q = [1;0;0;0]; else q = a2qua(att0); end` | 如果传了 4 元素→四元数，3 元素→欧拉角转四元数                                                        | `a2qua(att0)` = 欧拉角→四元数                     |
| 29    | `ahrs.flt = iirflt([4,0.02]);`                                                                  | 初始化 IIR 低通滤波器（4 阶，截止 0.02 归一化频率）                                                  | 给加计数据做低通，滤掉高频噪声                             |
| 30    | `ahrs.q = q;  ahrs.Cnb = q2mat(ahrs.q);`                                                        | 存四元数，算出方向余弦阵                                                                      | $\mathbf{C}_b^n = \text{q2mat}(\mathbf{q})$ |
| 31    | `ahrs.exyzInt = [0;0;0];`                                                                       | 误差积分项清零（PI 的 I 部分）                                                                | $\int_0^0 \mathbf{e}\,dt = \mathbf{0}$      |
| 32    | `if ~exist('tau', 'var'), tau = 4; end`                                                         | 默认时间常数 $\tau=4$s                                                                  | 截止频率 $\approx 1/(2\pi\tau) \approx 0.04$ Hz |
| 33    | `if tau<=0.1`                                                                                   | 如果 $\tau \leq 0.1$ → 自适应模式                                                        | tau 很小 = 想要快速响应 → 用自适应                      |
| 34    | `ahrs.adaptive = 1;`                                                                            | 开启自适应（运行时根据加速度大小动态调 $\tau$）                                                       | 见 MahonyUpdate L20-35                       |
| 35    | `else`                                                                                          | 否则固定参数模式                                                                          | —                                           |
| 36    | `ahrs.adaptive = 0;`                                                                            | 关闭自适应                                                                             | —                                           |
| 37    | `beta = 2.146/tau;`                                                                             | ★ 算 $\beta$：$2.146$ 是严老师的经验系数                                                     | $\beta = 2.146/\tau$                        |
| 38    | `ahrs.Kp = 2*beta; ahrs.Ki = beta^2;`                                                           | ★★ PI 参数：$K_p=2\beta$，$K_i=\beta^2$                                               | 临界阻尼：$s^2+2\beta s+\beta^2=(s+\beta)^2$     |
| 40    | `if ~exist('t0', 'var'), t0 = 0; end`                                                           | 默认初始时间 = 0                                                                        | —                                           |
| 41    | `ahrs.tk = t0;`                                                                                 | 初始化时间                                                                             | —                                           |
| 42    | `ahrs.qInt = ahrs.q; ahrs.vnInt = [0;0;0]; ahrs.qIntT = 0;`                                     | 纯积分测试变量（可选，用于验证陀螺零偏估计效果）                                                          | 每 100s 重置一次，看纯积分漂多少                         |

> 💡 **关键理解**：$K_p$ 和 $K_i$ 不是随便取的。$K_p = 2\beta$，$K_i = \beta^2$ 保证系统是**临界阻尼**——既不过冲也不缓慢收敛。$\tau$ 越大 → $\beta$ 越小 → 滤波越平滑但响应越慢；$\tau$ 越小 → 响应快但噪声大。

> **数值例**：$\tau=4$s 时，$\beta = 2.146/4 = 0.5365$，$K_p = 2 \times 0.5365 = 1.073$，$K_i = 0.5365^2 = 0.2878$。姿态误差每 4 秒衰减到 37%。

### MahonyUpdate.m 逐行注释

> 🧩 **函数作用**：一步 Mahony AHRS 更新——输入 IMU+磁力计，输出更新后的姿态。
>
> 源码：[MahonyUpdate.m](file:///workspace/psins/base/AHRS/MahonyUpdate.m)

| 行号 | 原代码 | 中文注释 | 公式/备注 |
|---|---|---|---|
| 1 | `function ahrs = MahonyUpdate(ahrs, imu, mag, ts)` | Mahony AHRS 一步更新 | 输入：ahrs 结构体、IMU、磁力计、采样间隔 |
| 4 | `% Prototype: ahrs = MahonyUpdate(ahrs, imu, mag, ts)` | ★ **函数原型**：调用方式 `ahrs = MahonyUpdate(ahrs, imu, mag, ts)` | — |
| 5 | `% Inputs: ahrs - AHRS structure array` | **输入** ahrs = AHRS 结构体（由 MahonyInit 创建） | — |
| 6 | `%        imu - [wm, vm] gyro & acc increment samples` | **输入** imu = [角增量 $\boldsymbol{\phi}_m$, 速度增量 $\Delta\mathbf{v}_m$] 子样 | 多子样时 imu 是 $N \times 6$ 矩阵 |
| 7 | `%        mag - magetic output in mGauss (or any unit)` | **输入** mag = 磁力计输出（mGauss，单位不限，因为会归一化） | $\mathbf{m}^b$ |
| 8 | `%        ts - sample interval` | **输入** ts = 采样间隔（s） | $T_s$ |
| 9 | `% Output: ahrs - output AHRS structure array` | ★ **输出** ahrs = 更新后的 AHRS 结构体 | 含 $\mathbf{q}, C_b^n, \mathbf{e}_{\text{Int}}$ 等 |
| 16 | `[phim, dvbm] = cnscl(imu);  nts = size(imu,1)*ts;` | ★ 圆锥/划桨补偿（和 insupdate L19 一样！），算出总时间 | $\boldsymbol{\phi}_m$ = 补偿后角增量，$\Delta\mathbf{v}_m$ = 补偿后速度增量，$T_s = N_{\text{子样}} \times t_s$ |
| 17 | `nm = norm(dvbm);` | 加计增量模值 | $\vert\Delta\mathbf{v}_m\vert$ |
| 18 | `if nm>0, acc = dvbm/nm;  else  acc = [0;0;0]; end` | ★ 归一化为单位向量（b 系重力方向测量值） | $\hat{\mathbf{f}}^b = \Delta\mathbf{v}_m / \vert\Delta\mathbf{v}_m\vert$，注意 nm=0 时保护 |
| 19 | `ahrs.flt = iirflt(ahrs.flt, dvbm/nts); fb = ahrs.flt.y(1:3,1);` | 低通滤波加计数据，取滤波后的比力 | IIR 降噪声，$\mathbf{f}^b_{\text{滤波}} = \text{IIR}(\Delta\mathbf{v}_m/T_s)$ |
| 20-35 | `if ahrs.adaptive==1 ... end` | ★ 自适应模式：根据加速度偏离重力的程度动态调 $\tau$ | 见 §10 详解 |
| 21 | `nm1 = abs(norm(fb)-9.8);` | 加计模值偏离 9.8 的程度 | $\vert\vert\mathbf{f}^b\vert - g\vert$，静态≈0，动态>0 |
| 22-23 | `if nm1<0.03, tau = interplim([0, .03], [3, 10], nm1);` | 偏离 <30mg → 几乎静态，$\tau \in [3, 10]$s | 静态时 $\tau$ 小 = 响应快 = 多信任加计 |
| 24-25 | `elseif nm1<0.1, tau = interplim([0.03, .1], [10, 20], nm1);` | 偏离 <100mg → 轻微动态，$\tau \in [10, 20]$s | 逐步加大 $\tau$ = 减少信任加计 |
| 30-31 | `else, tau = interplim([.1, 150], [300000, 500000], nm1);` | 偏离 >100mg → 强动态，$\tau$ 极大 | $\tau \to \infty$ = $K_p,K_i \to 0$ = 纯陀螺积分 |
| 33 | `beta = 2.146/tau;` | 重新算 $\beta$ | $\beta = 2.146/\tau$ |
| 34 | `ahrs.Kp = 2*beta; ahrs.Ki = beta^2;` | 重新设 PI 参数 | 动态时 $K_p,K_i \to 0$ → 几乎不做校正 |
| 36 | `nm = norm(mag);` | 磁力计模值 | $\vert\mathbf{m}^b\vert$ |
| 37 | `if nm>0, mag = mag/nm;  else  mag = [0;0;0]; end` | 归一化磁力计 | $\hat{\mathbf{m}}^b = \mathbf{m}^b / \vert\mathbf{m}^b\vert$ |
| 38 | `bxyz = ahrs.Cnb*mag;` | ★ 磁力计从 b 系转到 n 系 | $\mathbf{m}^n = C_b^n \hat{\mathbf{m}}^b$ |
| 39 | `bxyz(1:2) = [0;norm(bxyz(1:2))];` | ★★ **磁倾角补偿**：只保留水平北向分量，清掉东向 | $\mathbf{b}^n = [0, \vert\mathbf{m}^n_{\text{水平}}\vert, m^n_z]^T$ |
| 40 | `wxyz = ahrs.Cnb'*bxyz;` | 修正后的参考磁场转回 b 系 | $\mathbf{w}^b = (C_b^n)^T \mathbf{b}^n = C_n^b \mathbf{b}^n$ |
| 41 | `exyz = cros(ahrs.Cnb(3,:)',acc) + cros(wxyz,mag);` | ★★★ **核心：误差 = 加计叉积 + 磁力计叉积** | $\mathbf{e} = \underbrace{(C_b^n)_{3,:}^T \times \hat{\mathbf{f}}^b}_{\text{pitch/roll 误差}} + \underbrace{\mathbf{w}^b \times \hat{\mathbf{m}}^b}_{\text{yaw 误差}}$ |
| 43 | `ahrs.exyzInt = ahrs.exyzInt + exyz*ahrs.Ki*nts;` | ★ 误差积分（I 部分） | $\int \mathbf{e}\,dt \mathrel{+}= K_i \cdot \mathbf{e} \cdot T_s$ |
| 45 | `eb = (ahrs.Kp*exyz+ahrs.exyzInt);` | ★★ PI 反馈 = 比例 + 积分 | $\boldsymbol{\varepsilon}_{\text{反馈}} = K_p \mathbf{e} + K_i \int \mathbf{e}\,dt$ |
| 46-48 | `if nm==0, en = ahrs.Cnb*eb; en(3)=0; eb = ahrs.Cnb'*en; end` | 无磁力计时，去掉航向误差（只保留 pitch/roll） | $e_n = C_b^n \boldsymbol{\varepsilon}$，$e_{n,z}=0$（yaw 不修正） |
| 49 | `ahrs.q = qmul(ahrs.q, rv2q(phim-eb*nts));` | ★★★ **姿态更新**：陀螺角增量 - PI反馈修正 → 四元数乘法 | $\mathbf{q}_{k+1} = \mathbf{q}_k \otimes \text{rv2q}(\boldsymbol{\phi}_m - \boldsymbol{\varepsilon}_{\text{反馈}} \cdot T_s)$ |
| 50 | `ahrs.Cnb = q2mat(ahrs.q);` | 更新方向余弦阵 | $C_b^n = \text{q2mat}(\mathbf{q})$ |
| 51 | `ahrs.tk = ahrs.tk + nts;` | 时间推进 | $t \mathrel{+}= T_s$ |
| 53-58 | `ahrs.qIntT = ahrs.qIntT + nts; ...` | 纯积分测试（可选）：每 100s 不做校正纯积分，看漂多少 | 验证 PI 校正是否有效 |

> **L49 是整个 Mahony 的灵魂**：`phim - eb*nts` = 陀螺测的角增量减去 PI 反馈的修正量。
>
> 如果加计和陀螺完全一致（静态），误差 $\mathbf{e} \approx \mathbf{0}$，$\boldsymbol{\varepsilon}_{\text{反馈}} \approx \mathbf{0}$，退化为纯陀螺积分；
>
> 如果加计检测到偏差，$\boldsymbol{\varepsilon}_{\text{反馈}} \neq \mathbf{0}$，把陀螺增量往加计方向"拉"。

### §10 自适应模式详解（L20-35）

自适应的核心思想：**加速度越偏离重力 = 越动态 = 越不信任加计 = $\tau$ 越大**

| 加速度偏差 $\vert f\vert - g$ | 判断 | $\tau$ 范围 | $K_p, K_i$ | 效果 |
|---|---|---|---|---|
| <30mg | 几乎静态 | 3-10s | 大 | 多信任加计，快速校正 |
| 30-100mg | 轻微动态 | 10-20s | 中 | 减少信任，但仍校正 |
| >100mg | 强动态 | 300000-500000s | ≈0 | 几乎不校正，纯陀螺 |

**为什么不能直接** **$K_p, K_i = 0$？** 因为需要平滑过渡。`interplim` 做线性插值，避免突变。

### test\_AHRS\_Mahony.m 逐行注释

> 源码：[test\_AHRS\_Mahony.m](file:///workspace/psins/demos/test_AHRS_Mahony.m)

| 行号    | 原代码                                                                         | 中文注释                                                                | 公式/备注                                                                                                |
| ----- | --------------------------------------------------------------------------- | ------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------- |
| 1     | `glvs`                                                                      | 初始化全局变量（地球参数等）                                                      | —                                                                                                    |
| 2     | `ts = 0.1;`                                                                 | 采样间隔 0.1s（10Hz）                                                     | $T_s = 0.1$s                                                                                         |
| 3     | `ahrs = MahonyInit(4);`                                                     | 初始化 Mahony，$\tau=4$s（固定参数模式）                                        | $\beta=0.5365$, $K_p=1.073$, $K_i=0.288$                                                             |
| 4     | `len = 50/ts; avp = zeros(len, 7);`                                         | 跑 50 秒，500 步                                                        | —                                                                                                    |
| 5     | `for k=1:len`                                                               | 主循环                                                                 | —                                                                                                    |
| 6     | `ahrs = MahonyUpdate(ahrs, [[1,0,0]*0, [1,0,1/glv.deg]], [0.2;-10;0], ts);` | ★ 输入：陀螺角增量=\[0,0,0]（静止）、加计=\[1,0,0.0175]（pitch=1°）、磁力计=\[0.2,-10,0] | $\boldsymbol{\phi}_m=\mathbf{0}$, $\Delta\mathbf{v}_m=[1,0,\sin 1°]^T$, $\mathbf{m}^b=[0.2,-10,0]^T$ |
| 7     | `avp(k,:) = [m2att(ahrs.Cnb); ahrs.exyzInt; ahrs.tk];`                      | 存：欧拉角 + 误差积分 + 时间                                                   | $\text{att} = \text{m2att}(C_b^n)$                                                                   |
| 8     | `end`                                                                       | —                                                                   | —                                                                                                    |
| 9     | `sysw=tf([1,0], [1,ahrs.Kp,ahrs.Ki]);`                                      | 构造传递函数 $\frac{s}{s^2+K_p s+K_i}$（陀螺噪声通道）                            | 高通                                                                                                   |
| 10    | `yw = step(sysw,avp(:,end));`                                               | 画阶跃响应（陀螺噪声→误差）                                                      | —                                                                                                    |
| 11    | `sysf=tf([ahrs.Kp,ahrs.Ki], [1,ahrs.Kp,ahrs.Ki]);`                          | 构造传递函数 $\frac{sK_p+K_i}{s^2+K_p s+K_i}$（加计通道）                       | 低通                                                                                                   |
| 12    | `yf = step(sysf,avp(:,end));`                                               | 画阶跃响应（加计→误差修正）                                                      | —                                                                                                    |
| 13-17 | `figure, subplot(...)`                                                      | 画 4 张图：pitch、roll、yaw、误差积分                                          | —                                                                                                    |
| 18    | `[ahrs.Kp, ahrs.Ki]`                                                        | 打印最终的 PI 参数                                                         | 应该输出 \[1.073, 0.288]                                                                                 |

> **这个 test 在做什么**：模拟一个 pitch=1° 的静态场景，陀螺=0（不转），加计输出 \[1,0,0.0175]（重力在 b 系的投影，pitch=1°）。Mahony 会从 $\mathbf{q}=[1,0,0,0]$（姿态=0）收敛到 pitch=1°。图里能看到指数收敛过程，收敛时间 $\approx \tau = 4$s。

***

## 🔍 断点调试建议

### 调试1：误差收敛验证

在 MATLAB 里跑 test\_AHRS\_Mahony.m，在 MahonyUpdate L41 设断点：

```matlab
% 命中断点后
exyz  % 看误差向量，应该随时间衰减
ahrs.exyzInt  % 看积分项，应该收敛到稳态值
ahrs.Kp, ahrs.Ki  % 看 PI 参数

% 手算误差（对应 L41）
acc_man = [0; 1/glv.deg; 0] / norm([0; 1/glv.deg; 0]);  % 加计归一化
e_acc_man = cros(ahrs.Cnb(3,:)', acc_man);  % 重力方向叉积
norm(exyz - e_acc_man)  % <1e-14 说明加计部分理解对了
```

### 调试2：PI 反馈量验证

在 MahonyUpdate L49 设断点：

```matlab
% KF 更新前
eb  % PI 反馈量 = Kp*exyz + exyzInt
phim  % 陀螺角增量
phim - eb*nts  % 净转动量

% 手算（对应 L49）
eb_man = ahrs.Kp*exyz + ahrs.exyzInt;
q_man = qmul(ahrs.q, rv2q(phim - eb_man*nts));
norm(ahrs.q - q_man)  % <1e-14 说明理解对了
```

### 调试3：自适应参数观察

用 `MahonyInit(0.05)`（自适应模式），在 MahonyUpdate L34 设断点：

```matlab
nm1  % 加速度偏离 9.8 的程度
tau  % 当前自适应 tau
ahrs.Kp, ahrs.Ki  % 当前 PI 参数
% 静态时 nm1≈0, tau≈3, Kp≈1.4, Ki≈0.5
% 模拟加速时 nm1>0.1, tau→300000, Kp≈0, Ki≈0
```

***

## ❌ 初学者最容易踩的坑

1. **磁力计没归一化**：L37 做了 `mag = mag/nm`，你自己移植时容易忘。不归一化 → 叉积大小受磁场强度影响 → PI 参数无效
2. **加计归一化忘了判 nm>0**：如果加计输出 \[0,0,0]（自由落体），除以 0 会 NaN。L18 的 `if nm>0` 是保护
3. **Mahony 的** **$\tau$** **选太大**：$\tau=10$s 看着稳，但加了 10° pitch 要 30s 才收敛。飞控场景 $\tau$ 建议 1-3s
4. **磁力计补偿忘了去东向**：L39 `bxyz(1:2)=[0;norm(...)]` 是把磁场水平投影到北向。不做这步 → 磁倾角会污染 roll/pitch
5. **PI 的 I 项不抗饱和**：如果长时间大加速度，积分项会不断增大。PSINS 的自适应模式通过增大 $\tau$ 来间接减小 $K_i$，但嵌入式上可能需要加抗饱和限幅
6. **四元数没归一化**：MahonyUpdate 没有显式 `qnormlz`！但 `qmul+rv2q` 在小角度下近似保持归一化。**嵌入式移植时建议加上** `q = q / norm(q)`

***

## 🎯 配套练习

### 练习1：收敛时间验证

跑 test\_AHRS\_Mahony.m，回答：

- pitch 从 0° 收敛到 1° 的 63%（0.63°）需要多少秒？应该 $\approx \tau = 4$s
- 改 $\tau=1$ 再跑一次，收敛快了多少？PI 参数变成多少？
- 改 $\tau=10$ 再跑一次，收敛慢了多少？

### 练习2：自适应 vs 固定参数

用 `MahonyInit(0.05)`（自适应模式）跑 test\_AHRS\_Mahony.m，对比固定参数版：

- 自适应模式下 $K_p/K_i$ 怎么随加速度变化？
- 静态时 $\tau \approx$ 多少？动态时 $\tau \approx$ 多少？

### 练习3：误差分解

在 MahonyUpdate L41 断点处，分别打印加计误差和磁力计误差：

```matlab
e_acc = cros(ahrs.Cnb(3,:)', acc)
e_mag = cros(wxyz, mag)
exyz = e_acc + e_mag
```

- 静态时哪个分量为主？
- 如果去掉磁力计（mag=0），哪个分量消失？

### 练习4：嵌入式移植热身

把 MahonyUpdate.m 翻译成 C 伪代码（不需要编译），重点关注：

- L41 的叉积 `cros(a,b)` 怎么写？（提示：$\mathbf{a} \times \mathbf{b} = [a_y b_z - a_z b_y, a_z b_x - a_x b_z, a_x b_y - a_y b_x]^T$）
- L49 的 `qmul` 和 `rv2q` 需要哪些子函数？（提示：看 03\_insupdate.md 附录 A.3）
- 自适应部分（L20-35）在嵌入式上可以简化为什么？（提示：查表法或简单 if-else）

