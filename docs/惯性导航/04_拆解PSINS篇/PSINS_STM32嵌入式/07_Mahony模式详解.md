# 07 Mahony 互补滤波详解

> 对应工程模式 `case 0x1111`，源码入口 [main.cpp#L34-L51](../../assets/PSINS_STM32F4xx_Keil4_V2.1/scr/main.cpp#L34-L51)。
> 算法实现 [PSINS.cpp#L3449-L3496](../../assets/PSINS_STM32F4xx_Keil4_V2.1/Psinscore/PSINS.cpp#L3449-L3496)，类定义 [PSINS.h#L921-L932](../../assets/PSINS_STM32F4xx_Keil4_V2.1/Psinscore/PSINS.h#L921-L932)。

本工程提供两种 AHRS 后端：基于 PI 互补滤波的 `CMahony` 与基于四元数 EKF 的 `CQEAHRS`。`0x1111` 模式使用前者，输出 `qnb → q2att → 欧拉角`，是工程中最轻量、最常用的姿态解算路径。本文逐行解析 `CMahony::Update` 的数学含义与工程实现细节。

---

## 一、类结构与构造

### 1.1 成员定义

```cpp
class CMahony
{
public:
    double tk, Kp, Ki;          // 时间累计、比例增益、积分增益
    CQuat qnb;                  // body→nav 四元数（核心状态）
    CMat3 Cnb;                  // body→nav 方向余弦阵（qnb 的矩阵形式缓存）
    CVect3 exyzInt, ebMax;      // 积分项、积分限幅阈值

    CMahony(double tau=4.0, const CQuat &qnb0=qI);
    void SetTau(double tau=4.0);
    void Update(const CVect3 &wm, const CVect3 &vm, double ts, const CVect3 &mag=O31);
};
```

`qnb` 是唯一的姿态状态量，`Cnb` 仅是其矩阵化缓存，二者始终同步——`Update` 末尾用 `Cnb = q2mat(qnb)` 强制一致，避免四元数与 DCM 漂移。

### 1.2 构造函数与 τ→Kp/Ki 推导

[PSINS.cpp#L3450-L3463](../../assets/PSINS_STM32F4xx_Keil4_V2.1/Psinscore/PSINS.cpp#L3450-L3463):

```cpp
CMahony::CMahony(double tau, const CQuat &qnb0)
{
    SetTau(tau);
    qnb = qnb0;
    Cnb = q2mat(qnb);
    exyzInt = O31;  ebMax = One31*glv.dps;   // 默认 ±1°/s
    tk = 0.0;
}

void CMahony::SetTau(double tau)
{
    double beta = 2.146/tau;
    Kp = 2.0f*beta, Ki = beta*beta;
}
```

**推导**：二阶临界阻尼系统极点 $s = -\beta$（阻尼比 $\zeta = 1/\sqrt{2}$），对应连续域传递函数

$$
\ddot{\theta} + 2\zeta\omega_n \dot{\theta} + \omega_n^2 \theta = \omega_n^2 \theta_{\text{ref}}
$$

对照 PI 控制器 $u = K_p e + K_i \int e\,dt$，自然得到 $K_p = 2\beta$、$K_i = \beta^2$。常数 `2.146` 即 $\sqrt{2}\cdot\sqrt{2}/\sqrt[?]{\,}$ 的工程取值，使得截止频率 $f_c \approx 1/(2\pi\tau)$。

- `tau = 10.0`（`main.cpp` 默认）→ $\beta = 0.2146$ → `Kp = 0.4292`, `Ki = 0.0461`。
- τ 越大滤波越柔（抗噪强但收敛慢），τ 越小跟踪快但噪声大。

### 1.3 `ebMax` 限幅

`ebMax = One31 * glv.dps` 即 $\pm 1\,°/s$。陀螺零偏的物理量级通常在几 ~ 几十 $°/h$，1°/s 留足裕量。若传感器零偏漂移超过该值，应改硬件或在 `Update` 前做静态标定，而不是盲目放大 `ebMax`。

---

## 二、主循环调用链

[main.cpp#L34-L51](../../assets/PSINS_STM32F4xx_Keil4_V2.1/scr/main.cpp#L34-L51):

```cpp
void Mahony_main(void)
{
  CMahony mahony(10.0);              // tau=10s
  USART1_Configuration(0);
  while(1)
  {
    if(pcmd->cmd1==0xa5a5) {...}     // PC 退出命令
    if(GAMT_OK_flag==0) continue;     // 等 100Hz TIM2 中断置位
    GAMT_OK_flag = 0;
    wm = (*(CVect3*)mpu_Data_value.Gyro * glv.dps - eb) * TS;
    vm = (*(CVect3*)mpu_Data_value.Accel * glv.g0 - db) * TS;
    mahony.Update(wm, vm, TS);
    AVPUartOut(q2att(mahony.qnb));   // 四元数→欧拉角→DMA 输出
    MainProcessDone();
  }
}
```

要点：

| 步骤 | 表达式 | 物理含义 |
|---|---|---|
| 陀螺预处理 | `wm = (ω_raw·DPS - eb)·TS` | $°/s \to \text{rad/s}$，扣零偏 $e_b$，乘 $T_s$ 得**角增量** |
| 加计预处理 | `vm = (a_raw·g0 - db)·TS` | $g \to \text{m/s}^2$，扣零偏 $d_b$，乘 $T_s$ 得**速度增量** |
| 增益常量 | `glv.dps = DEG = π/180`，`glv.g0 = 9.7803267714` | 来自 [PSINS.h#L66-L74](../../assets/PSINS_STM32F4xx_Keil4_V2.1/Psinscore/PSINS.h#L66-L74) |
| 调用 | `Update(wm, vm, TS)` | TS = 1/100 = 0.01 s |
| 输出 | `q2att(mahony.qnb)` | 四元数→欧拉角 `[roll, pitch, yaw]` |

> 指针强转 `*(CVect3*)mpu_Data_value.Gyro` 的合法性见 [06_C与CPP桥接.md](06_C与CPP桥接.md)——前提是 `CVect3` 为 POD 且 8 字节对齐，二者在本工程均满足。

---

## 三、`CMahony::Update` 逐行解析

[PSINS.cpp#L3465-L3496](../../assets/PSINS_STM32F4xx_Keil4_V2.1/Psinscore/PSINS.cpp#L3465-L3496)。坐标系约定：导航系为 **ENU**（东-北-天），`qnb` 表示 body→ENU。

### 3.1 加速度归一化

```cpp
nm = norm(vm)/ts;                          // 模长，m/s^2
acc0 = nm>0.1 ? vm/(nm*ts) : O31;          // 归一化重力方向（体坐标系）
```

- `vm` 是速度增量（含 $T_s$），`norm(vm)/ts` 还原为比力模 $|f^b|$（m/s²）。
- `vm/(nm*ts)` = $f^b / |f^b|$，得到机体观测到的**单位重力方向**。
- 阈值 `0.1`：当 $|f^b| < 0.1\,\text{m/s}^2$（自由落体或强烈机动）时，加速度不可信，置零向量，后续误差项相应失效。这是工程上对"加速度假设 = 重力方向"失效场景的硬保护。
- 坐标系含义：理想静止时 ENU 下重力方向在导航系为 $-g\hat U$，体坐标系投影为 $-C_n^b \hat U$，即测得"重力向上"。

---

> **算法能力 vs 工程使用的边界**：本节（3.2~3.3）讲的是 `CMahony::Update` 函数本身的算法实现，函数签名 `Update(wm, vm, ts, mag=O31)` 第 4 个参数支持磁力计。但 [main.cpp#L47](../../assets/PSINS_STM32F4xx_Keil4_V2.1/scr/main.cpp) 中 `mahony.Update(wm, vm, TS)` 只传 3 个参数，`mag` 取默认值 `O31`（零向量），代入下面 `nm = norm(mag)` 得 0 < 0.1 进入 else 分支，磁场项被自动跳过。**所以工程实际只用加速度叉乘，磁力计分支在本工程不激活**——这里讲磁力计是为了说明算法完整能力，便于后续 H743 移植时启用。相关算法原理另见 [01 Mahony 滤波分析](../../05_滤波算法精读篇/01_Mahony滤波分析.md)。

### 3.2 磁力计参考向量构造（关键技巧）

```cpp
nm = norm(mag);
if(nm>0.1)
{
    mag0 = mag/nm;                         // 归一化磁场方向（体坐标系）
    bxyz = Cnb*mag0;                       // 投影到导航系 → b^n
    bxyz.j = normXY(bxyz);  bxyz.i = 0.0; // 保留水平模长，剥离 East 分量
    wxyz = (~Cnb)*bxyz;                    // 反变换回体系 → 参考方向 w^b
}
else
{
    mag0 = wxyz = O31;
}
```

逐步：

1. `mag0 = mag/|mag|`：体坐标系下实测磁场单位向量 $m^b$。
2. `bxyz = Cnb * mag0`：$m^n = C_b^n m^b$，转换到导航系。ENU 下地磁水平分量主要在 N 方向，垂直分量随磁倾角变化。
3. `bxyz.j = normXY(bxyz); bxyz.i = 0`：把 N、U 分量重构成新向量 $b^n = [0, \sqrt{m_E^2+m_N^2}, m_U]$，**人为置 East=0**。这等价于"只信任磁力计给出的水平方向模长 + 垂直分量"，避免水平磁偏角（declination）污染 yaw。
4. `wxyz = (~Cnb) * bxyz`：`~Cnb` 是 $C_n^b$（转置），把重构后的参考磁场反变换回体系，得到 $w^b$。
   - 在姿态完全正确时，应有 $w^b \approx m^b$；二者叉乘即误差。

> 这一步是 Mahony 算法处理磁力计的标准"倾角补偿（tilt-compensated）"做法。剥离 East 分量是为了让 yaw 误差不通过 roll/pitch 通道耦合回来——磁力计只修正 yaw，roll/pitch 只靠加速度。

### 3.3 误差计算（叉乘法）

```cpp
exyz = *((CVect3*)&Cnb.e20)*acc0 + wxyz*mag0;
```

拆解：

- `Cnb.e20`：`CMat3` 的内存是行主序 `e00..e02, e10..e12, e20..e22`，`e20` 是第 3 行首元素。`*((CVect3*)&Cnb.e20)` 取出第 3 行三个元素，即 $C_b^n$ 的第三行 = $C_n^b$ 的第三列 = **导航系 D 轴（ENU 的 U 轴反向）在体系下的表示**。记该向量为 $g_{\text{ref}}^b$。
- `acc0`：实测归一化比力 $f_0^b$。
- 第 1 项 $g_{\text{ref}}^b \times f_0^b$：参考重力方向与实测重力方向的叉乘 → 旋转误差向量 $e_{\text{acc}}$。
- 第 2 项 $w^b \times m^b$：参考磁场与实测磁场的叉乘 → 旋转误差向量 $e_{\text{mag}}$。
- 二者相加得总误差 $e = e_{\text{acc}} + e_{\text{mag}}$。

数学上：对任意两单位向量 $\hat{a}, \hat{b}$，叉乘 $\hat{a}\times\hat{b} = \sin\theta\,\hat{n}$，小角度下 $\sin\theta \approx \theta$，故叉乘向量直接给出三轴姿态误差。这是 Mahony 的核心思想——**用向量观测构造姿态误差，再用 PI 控制器修正陀螺**。

### 3.4 PI 控制与零偏估计

```cpp
exyzInt += exyz * (Ki*ts);          // 积分项
CVect3 eb = Kp*exyz + exyzInt;      // 估计的陀螺零偏（rad/s）
```

- 比例项 `Kp*exyz`：对当前误差的即时响应。
- 积分项 `exyzInt`：累计历史误差，估计**恒定陀螺零偏** $e_b$。
- 输出 `eb` 即补偿后的零偏估计（单位 rad/s，因为 `exyz` 是无量纲 sin 误差，`Kp` 量纲 1/s）。

### 3.5 加速度失效时的退化处理

```cpp
if(nm<0.1) {
    CVect3 en = Cnb*eb;   en.k = 0;   eb = (~Cnb)*en;
}
```

当加速度模过小（自由落体/大机动），$e_{\text{acc}}$ 不可信，但 $e_b$ 仍会被 `exyzInt` 污染。此处将 $e_b$ 投影到导航系后**清零垂直分量**再投回体系，物理含义是"只保留水平方向的零偏估计、丢掉垂向（yaw）通道"。原因是：yaw 方向零偏靠磁力计支撑，水平方向靠重力支撑；加速度失效时水平估计也不可信，但水平方向若不约束会导致 roll/pitch 漂移，故而保留。

### 3.6 四元数更新

```cpp
qnb *= rv2q(wm - eb*ts);
Cnb = q2mat(qnb);
tk += ts;
```

- `wm - eb*ts`：陀螺角增量扣除零偏增量。`eb` 是 rad/s，`eb*ts` 是该周期内的零偏角增量。
- `rv2q`：旋转矢量→四元数。实现 [PSINS.cpp#L408-L429](../../assets/PSINS_STM32F4xx_Keil4_V2.1/Psinscore/PSINS.cpp#L408-L429) 使用 5 阶泰勒展开处理小角度，避免 $\sin\theta/\theta$ 数值病态：

  ```cpp
  if(n2 < (PI/180)^2) {        // 小于 1°
      c = 1 - n2/8 + n4/384;   // cos 半角泰勒
      f = 0.5 - n2/48 + n4/3840;
  } else {
      c = cos(|rv|/2);  f = sin(|rv|/2)/(|rv|/2)*0.5;
  }
  return CQuat(c, f*rv.i, f*rv.j, f*rv.k);
  ```

- 右乘更新：$q_{k+1} = q_k \otimes \delta q$，符合 body→nav 右乘增量（body 系增量）。
- 末尾 `Cnb = q2mat(qnb)` 同步缓存。

### 3.7 积分限幅（防 windup）

```cpp
if(exyzInt.i>ebMax.i)  exyzInt.i=ebMax.i;
else if(exyzInt.i<-ebMax.i)  exyzInt.i=-ebMax.i;
// j, k 同理
```

三方向独立钳位在 $\pm 1\,°/s$。若长期存在大误差（如初始姿态偏差大），积分项不会无限累积，避免一旦收敛后 $e_b$ 仍偏大导致反向发散。

---

## 四、输出：四元数→欧拉角

[PSINS.cpp#L907-L918](../../assets/PSINS_STM32F4xx_Keil4_V2.1/Psinscore/PSINS.cpp#L907-L918):

```cpp
CVect3 q2att(const CQuat &qnb)
{
    double q11=q0*q0, q12=q0*q1, q13=q0*q2, q14=q0*q3,
           q22=q1*q1, q23=q1*q2, q24=q1*q3,
           q33=q2*q2, q34=q2*q3, q44=q3*q3;
    CVect3 att;
    att.i = asinEx(2*(q34+q12));                                    // roll
    att.j = atan2Ex(-2*(q24-q13), q11-q22-q33+q44);                // pitch
    att.k = atan2Ex(-2*(q23-q14), q11-q22+q33-q44);                // yaw
    return att;
}
```

对应 ZYX 欧拉角序列（偏航→俯仰→滚转），ENU 下：

$$
\phi = \arcsin(2(q_0q_1+q_2q_3)),\quad
\theta = \arctan\frac{-2(q_0q_3-q_1q_2)}{q_0^2-q_1^2-q_2^2+q_3^2},\quad
\psi = \arctan\frac{-2(q_0q_2-q_1q_3)}{q_0^2-q_1^2+q_2^2-q_3^2}
$$

`asinEx`/`atan2Ex` 是工程上的奇异点处理（$\theta=\pm 90°$ 时 $\phi,\psi$ 不唯一），实现略。输出经 `AVPUartOut` 打包进 `outFrame`，详见 [05_串口输出帧.md](05_串口输出帧.md)。

---

## 五、坐标系一致性核对

本工程的 ENU 约定，可由三处代码交叉验证：

1. **`glv.g0` 与 `vm` 的预处理**：`vm = Accel*g0*TS` 把 $g$ 还原为 m/s²。若为 NED，重力方向应取 $+g\hat D$；ENU 中取 $-g\hat U$。Mahony 中以 `Cnb.e20`（D 轴行）作为参考，等价于取"负 U 方向"——与 ENU 静止时 $f = -g\hat U$ 自洽。
2. **`GPS_Vn` 映射**：[usart.c#L13-L18](../../assets/PSINS_STM32F4xx_Keil4_V2.1/scr/usart.c#L13-L18) 中 `GPS_Vn[0]=vE, GPS_Vn[1]=vN, GPS_Vn[2]=-vU`（UBX 的 down 取反得 up），与 ENU 速度场一致。
3. **`GPS_Pos`**：`GPS_Pos[0]=lat, GPS_Pos[1]=lon, GPS_Pos[2]=height`，符合 PSINS MATLAB 的 `pos=[lat,lon,h]` 约定。

> 此处的 ENU↔NED 变换关系见 [01_基础篇/01_坐标系与变换.md](../../01_基础篇/01_坐标系与变换.md)。本工程**无需**做 ENU↔NED 转换，因为算法层与导航层一致使用 ENU。

---

## 六、与 `CQEAHRS` 对比

[PSINS.cpp#L3498-L3509](../../assets/PSINS_STM32F4xx_Keil4_V2.1/Psinscore/PSINS.cpp#L3498-L3509) 定义了基于 7 状态 EKF 的 AHRS：

| 维度 | `CMahony` | `CQEAHRS` |
|---|---|---|
| 状态 | $q_{4}, e_{b,3}$（隐式） | $q_4 + e_{b,3}$ = 7 维 |
| 增益来源 | τ 单参数 | $P, Q, R$ 三矩阵 |
| 协方差 | 无 | 有，可融合多源噪声 |
| 计算量 | 极小（叉乘 + PI） | 中（7×7 矩阵运算） |
| 适用场景 | MEMS、资源受限 MCU | 需要噪声统计的场合 |
| 工程选择 | `0x1111` 默认 | 工程未在主循环使用 |

`CMahony` 在 STM32F4 + MPU9250 平台足够，工程不启用 `CQEAHRS`。

---

## 七、调参与失效场景

### 7.1 τ 的选择

| 场景 | τ 推荐 | 理由 |
|---|---|---|
| 静态/低动态 | 10~20 s | 强过滤陀螺噪声 |
| 一般车载/船载 | 4~8 s | 平衡噪声与跟踪 |
| 高机动（无人机、机器人） | 1~3 s | 快速跟踪 roll/pitch |
| 自由落体/抛物 | 任意 | 加速度失效，仅靠陀螺，τ 影响小 |

工程默认 `tau = 10.0`，与陀螺零偏 `eb = CVect3(-4.0, 1.3, 0.0)*DPS` 的设定配套，适合桌面级静态测试。

### 7.2 已知失效模式

- **持续大机动**（≥2.5 g 协调转弯）：加速度 ≠ 重力，`acc0` 错误，`e_acc` 误差污染 $e_b$，roll/pitch 可能发散。本项目仅靠 `nm<0.1` 硬阈值保护，对持续 1~2 g 的机动无能为力。这也是惯导组合（`0x2222`/`0x3333` 模式）存在的根本动机，见后续 [08_SINS_GNSS静态组合.md](08_SINS_GNSS静态组合.md)。
- **磁场干扰**：附近铁磁物体会让 `mag0` 偏离地磁，`e_mag` 误差污染 yaw。工程无磁干扰检测，需硬件远离或外加屏蔽。
- **初始姿态偏差大**：`exyzInt` 限幅在 ±1°/s，初次启动收敛较慢，建议加初始化对齐（静态几秒取平均加速度方向作为初始 `qnb`）。工程构造函数 `CMahony(tau, qnb0=qI)` 默认 `qnb0 = qI`，即初始姿态为单位四元数（body 与 nav 完全对齐），若上电时机体非水平，需要数秒收敛。

### 7.3 工程改进建议

- 上电静态对齐：在 `Mahony_main` 进入 `while(1)` 前采集 N 帧加速度均值，构造初始 `qnb0`，可显著缩短收敛时间。
- 加计有效判据：用 $|f^b - g|$ 偏差而非单纯模长阈值，对 1~2 g 持续机动更鲁棒。
- 磁干扰检测：连续若干帧 $|m^b|$ 与历史均值偏差超阈值时禁用磁力计项。

> 上述改进属于可选优化，工程原版以"能用、可教学"为标准，不在本 wiki 的修改范围内。

---

## 八、附录：核心数学量速查

| 量 | 符号 | 代码 | 单位 |
|---|---|---|---|
| 陀螺角速度 | $\omega^b$ | `mpu_Data_value.Gyro` | $°/s$ |
| 陀螺角增量 | $w_m$ | `wm = (ω·DPS - eb)·TS` | rad |
| 比力 | $f^b$ | `mpu_Data_value.Accel·g0` | m/s² |
| 速度增量 | $v_m$ | `vm = (a·g0 - db)·TS` | m/s |
| 归一化比力 | $f_0^b$ | `acc0 = vm/(nm·ts)` | — |
| 归一化磁场 | $m^b$ | `mag0 = mag/|mag|` | — |
| 参考磁场 | $w^b$ | `wxyz = (~Cnb)*bxyz` | — |
| 姿态误差 | $e$ | `exyz` | — |
| 估计零偏 | $\hat e_b$ | `eb = Kp*exyz + exyzInt` | rad/s |
| 姿态四元数 | $q_b^n$ | `qnb` | — |
| 方向余弦阵 | $C_b^n$ | `Cnb` | — |
| 欧拉角 | $[\phi,\theta,\psi]$ | `q2att(qnb)` | rad |

---

## 参考资料

- [Mahony, R., Hamel, T., Pflimlin, J.-M. (2008). *Nonlinear Complementary Filters on the Special Orthogonal Group.* IEEE Transactions on Automatic Control, 51(1).](https://ieeexplore.ieee.org/document/4358931) — 本工程 CMahony::Update 的算法原型，PI 控制律、SO(3) 上的非线性互补滤波推导
- [严恭敏教授 PSINS 官网](http://www.psins.org.cn/) — CMahony 类定义、SetTau 推导、ebMax 限幅等工程实现细节
- [严恭敏教授 CSDN 博客](https://blog.csdn.net/yan_gong_min) — AHRS 互补滤波在 MEMS 惯导中的应用系列
- [Quaternion Kinematics for the Error-State Kalman Filter (Sola, 2017)](https://arxiv.org/abs/1711.02508) — 四元数更新 `v2q`、`q2att` 欧拉角提取的数学背景
- [四元数姿态表示与 SO(3) 群入门](https://en.wikipedia.org/wiki/Quaternions_and_spatial_rotation) — 右乘增量、`q_{k+1} = q_k \otimes \delta q` 的物理含义
- [PSINS MATLAB 版 `CMahony` 源码对照](https://github.com/yanliang-zhu/PSINS-MATLAB) — 本嵌入式工程算法层与 MATLAB 版的 1:1 对照
- [本 wiki：01 Mahony 滤波分析](../../05_滤波算法精读篇/01_Mahony滤波分析.md) — 滤波算法精读篇对 Mahony 算法数学推导、增益设计、与 Madgwick/EKF 对比的深度分析

---

## 导航

- 上一篇：[06_C与CPP桥接.md](06_C与CPP桥接.md)
- 下一篇：[08_SINS_GNSS静态组合.md](08_SINS_GNSS静态组合.md)
- 回到总览：[00_总览与架构.md](00_总览与架构.md)
