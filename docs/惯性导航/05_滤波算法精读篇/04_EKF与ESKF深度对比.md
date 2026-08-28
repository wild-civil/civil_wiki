

# 飞控EKF与ESKF深度对比：从PX4 EKF2源码看两种卡尔曼滤波架构的本质区别

> **读者定位**：研一学生，已掌握一阶互补滤波、Mahony滤波、Madgwick滤波和基础卡尔曼滤波。本文从直觉出发，逐步深入数学推导和源码分析，力求让初学者也能看懂两种滤波架构的本质差异。

---

## 第一部分：为什么飞控需要EKF？——从AHRS到INS/GNSS的跨越

### 1.1 AHRS的局限：只有姿态，没有位置

Mahony 滤波和 Madgwick 滤波属于**AHRS（姿态航向参考系统）** 范畴，它们的共同特点是：

- **输入**：IMU（陀螺仪+加速度计）+ 磁力计
- **输出**：只有姿态（四元数/欧拉角）
- **问题**：无法估计速度和位置，更无法融合GPS等外部传感器

Mahony滤波的核心是互补滤波思想：用加速度计修正陀螺仪的低频漂移，用陀螺仪提供高频动态响应。但它本质上是一个**单状态（姿态）估计器**，无法处理多传感器、多状态的融合问题。

### 1.2 引入GNSS后的新挑战

当引入GPS/GNSS后，系统需要估计的状态变多了：

| 状态类型 | 具体内容 | 维度 |
|---------|---------|------|
| 姿态 | 四元数/欧拉角 | 3 DOF |
| 速度 | NED三个方向 | 3 |
| 位置 | NED三个方向 | 3 |
| 传感器偏差 | 陀螺零偏、加计零偏 | 6 |
| 其他 | 地磁场、风场、地形 | 若干 |

这时候问题来了：**姿态运动学是非线性的**。

回忆一下四元数微分方程：


$$
\dot{\mathbf{q}} = \frac{1}{2} \mathbf{q} \otimes \boldsymbol{\omega}
$$


该方程包含四元数乘法，是关于状态 $\mathbf q$ 的非线性微分方程。标准卡尔曼滤波（KF）仅能严格处理线性高斯系统，无法直接套用，不能直接拿来做姿态解算。

### 1.3 为什么是扩展卡尔曼滤波（EKF）？

扩展卡尔曼滤波（Extended Kalman Filter）的核心思想是：**在当前估计值附近对非线性函数进行一阶泰勒展开，将非线性系统线性化，然后应用卡尔曼滤波**。

对于非线性系统：


$$
\mathbf{x}_k = f(\mathbf{x}_{k-1}, \mathbf{u}_k) + \mathbf{w}_k
$$


$$
\mathbf{z}_k = h(\mathbf{x}_k) + \mathbf{v}_k
$$


EKF通过计算雅可比矩阵来线性化：


$$
\mathbf{F}_k = \frac{\partial f}{\partial \mathbf{x}} \bigg|_{\hat{\mathbf{x}}_{k-1|k-1}}
$$


$$
\mathbf{H}_k = \frac{\partial h}{\partial \mathbf{x}} \bigg|_{\hat{\mathbf{x}}_{k|k-1}}
$$


然后就可以使用标准卡尔曼滤波的预测和更新公式了。

> **白话解释**：EKF就像是在弯曲的山路上开车，你每走一步就把脚下的一小段路看成直的（线性化），然后用直线公式计算下一步。虽然路是弯的，但只要每步足够小，误差就可控。

---

## 第二部分：直接EKF架构——以PX4 EKF2为蓝本

### 2.1 PX4 EKF2概述

PX4 EKF2是当前PX4飞控默认的状态估计器，它是一个**直接状态EKF**（也可视为混合架构，详见后文）。让我们先从宏观上了解它的架构。

**核心文件结构**（基于PX4-Autopilot v1.16）：

```
src/modules/ekf2/EKF/
├── ekf.h / ekf.cpp              # 主类：状态定义、主循环
├── estimator_interface.h/.cpp   # 接口层：传感器数据输入、缓冲管理
├── covariance.cpp               # 协方差预测与更新
├── control.cpp                  # 融合控制中枢
└── aid_sources/                 # 各传感器融合模块
    ├── gnss/                    # GNSS融合
    ├── barometer/               # 气压计融合
    ├── magnetometer/            # 磁力计融合
    └── ...
```

**主循环流程**（ekf.cpp的update函数）：

```cpp
// ekf.cpp 核心循环（简化示意）
bool Ekf::update() {
    if (!_imu_updated) return false;
    
    const imuSample imu_sample_delayed = _imu_buffer.get_oldest();
    
    // 1. 状态预测（四元数积分+速度积分+位置积分）
    predictState(imu_sample_delayed);
    
    // 2. 协方差预测
    predictCovariance(imu_sample_delayed);
    
    // 3. 传感器融合（GPS、气压计、磁力计等）
    controlFusionModes(imu_sample_delayed);
    
    // 4. 输出预测器对齐
    _output_predictor.correctOutputStates(...);
    
    return true;
}
```
&nbsp;

> **注意**：EKF2运行在"延迟时间线"上——它用缓冲区中最旧的IMU数据做预测，这样可以对齐有延迟的传感器数据（如GPS通常有100-200ms延迟）。

### 2.2 24维状态向量详解

PX4 EKF2使用24维状态向量，定义在`state.h`中：

```cpp
// state.h - 状态向量结构（简化示意）
struct StateSample {
    matrix::Quaternion<float> quat_nominal;  // 姿态四元数 [0-2] (3 DOF)
    matrix::Vector3<float> vel;              // NED速度 [3-5]
    matrix::Vector3<float> pos;              // NED位置 [6-8]
    matrix::Vector3<float> gyro_bias;        // 陀螺偏差 [9-11]
    matrix::Vector3<float> accel_bias;       // 加速度计偏差 [12-14]
    matrix::Vector3<float> mag_I;            // 地磁场（NED系） [15-17]
    matrix::Vector3<float> mag_B;            // 磁力计偏差（体坐标系） [18-20]
    matrix::Vector2<float> wind_vel;         // 风速（NE方向） [21-22]
    float terrain;                           // 地形高度 [23]
};

namespace State {
    static constexpr uint8_t size{24};  // 总状态数24
}
```
&nbsp;

> **思考题**：四元数明明有4个分量，为什么自由度是3？
> 
> 答案：因为四元数需要满足归一化约束 $\|\mathbf{q}\|=1$，所以只有3个自由度。这也是直接EKF的痛点之一——协方差矩阵是24×24的，但四元数相关的协方差存在奇异性问题。

| 状态组 | 索引范围 | 维度 | 物理意义 |
|-------|---------|------|---------|
| 姿态四元数 | 0-2 | 3 | 从NED系到机体坐标系的旋转 |
| 速度 | 3-5 | 3 | NED坐标系下的速度 (m/s) |
| 位置 | 6-8 | 3 | NED坐标系下的位置 (m) |
| 陀螺零偏 | 9-11 | 3 | 陀螺仪测量偏差 (rad/s) |
| 加计零偏 | 12-14 | 3 | 加速度计测量偏差 (m/s²) |
| 地磁场 | 15-17 | 3 | NED系下的地磁场矢量 (Gauss) |
| 磁偏置 | 18-20 | 3 | 机体的磁干扰偏差 (Gauss) |
| 风速 | 21-22 | 2 | NED系下的风速 (m/s) |
| 地形高度 | 23 | 1 | 地形高度估计 (m) |

### 2.3 预测步：IMU传播的数学与源码

预测步是EKF的核心，它利用IMU测量值来传播状态和协方差。

#### 2.3.1 状态预测（predictState）

状态预测本质上就是**捷联惯导机械编排**（Strapdown INS Mechanization）。

**四元数更新**：


$$
\mathbf{q}_{k} = \mathbf{q}_{k-1} \otimes \Delta \mathbf{q}(\tilde{\boldsymbol{\omega}} \Delta t - \mathbf{b}_g)
$$


其中 $\Delta \mathbf{q}(\boldsymbol{\theta})$ 是旋转矢量对应的四元数：


$$
\Delta \mathbf{q} = \begin{bmatrix}
\cos(\|\boldsymbol{\theta}\|/2) \\
\frac{\boldsymbol{\theta}}{\|\boldsymbol{\theta}\|} \sin(\|\boldsymbol{\theta}\|/2)
\end{bmatrix}
$$


**速度更新**：


$$
\mathbf{v}_k^n = \mathbf{v}_{k-1}^n + \mathbf{C}_b^n(\mathbf{q}) \cdot (\tilde{\mathbf{a}} - \mathbf{b}_a) \Delta t + \mathbf{g}^n \Delta t
$$


其中 $\mathbf{C}_b^n(\mathbf{q})$ 是从机体坐标系到导航坐标系的方向余弦矩阵，$\mathbf{g}^n = [0, 0, g]^T$ 是重力矢量（NED系下向下为正）。

**位置更新**：


$$
\mathbf{p}_k^n = \mathbf{p}_{k-1}^n + \frac{1}{2}(\mathbf{v}_{k-1}^n + \mathbf{v}_k^n) \Delta t
$$


> **坐标系约定**：本文严格遵循武汉大学牛小骥老师的NED+FRD体系：
> - 导航坐标系（n系）：北-东-地（NED）
> - 机体坐标系（b系）：前-右-下（FRD）
> - $\mathbf{C}_b^n$ 表示从b系到n系的投影变换矩阵（"下进上出"原则）
> - 欧拉角采用ZYX顺序：航向角ψ、俯仰角θ、横滚角φ

现在来看PX4 EKF2中的实现（ekf.cpp中的predictState函数）：

```cpp
// ekf.cpp - predictState 函数（简化示意，保留核心逻辑）
void Ekf::predictState(const imuSample &imu_delayed)
{
    const float dt = imu_delayed.delta_ang_dt;
    
    // 1. 计算校正后的角速度（减去陀螺零偏）
    const Vector3f corrected_delta_ang = imu_delayed.delta_ang - _state.gyro_bias * dt;
    
    // 2. 四元数积分（一阶龙格-库塔）
    Quatf delta_q;
    delta_q.fromAxisAngle(corrected_delta_ang);
    _state.quat_nominal = _state.quat_nominal * delta_q;
    _state.quat_nominal.normalize();  // 强制归一化！
    
    // 3. 计算从机体到导航系的旋转矩阵
    const Dcmf R_to_earth = Dcmf(_state.quat_nominal);
    
    // 4. 速度更新（包含重力补偿）
    const Vector3f corrected_delta_vel = imu_delayed.delta_vel - _state.accel_bias * dt;
    const Vector3f delta_vel_earth = R_to_earth * corrected_delta_vel;
    
    // 重力在NED系中是正的（向下为正）
    const Vector3f gravity(0.0f, 0.0f, CONSTANTS_ONE_G);
    
    _state.vel += delta_vel_earth + gravity * dt;
    
    // 5. 位置更新（梯形积分）
    _state.pos += _state.vel * dt - 0.5f * delta_vel_earth * dt;
    
    // 6. 其他状态（零偏、磁场等）不随IMU变化，保持原值
    // 它们的变化由过程噪声协方差描述
}
```
&nbsp;

> **重要细节**：注意第7行的`normalize()`调用——在直接EKF中，四元数作为状态向量的一部分，理论上协方差传播后会偏离归一化约束，因此必须手动归一化。这是直接EKF的一个"不优雅"之处。

#### 2.3.2 协方差预测（predictCovariance）

协方差预测是EKF中计算量最大的部分，公式为：


$$
\mathbf{P}_{k|k-1} = \mathbf{F}_k \mathbf{P}_{k-1|k-1} \mathbf{F}_k^T + \mathbf{Q}_k
$$


其中 $\mathbf{F}$ 是状态转移矩阵的雅可比矩阵，$\mathbf{Q}$ 是过程噪声协方差矩阵。

对于24维状态，$\mathbf{F}$ 是24×24的矩阵，$\mathbf{P}$ 也是24×24的矩阵。一次矩阵乘法需要 $O(n^3)$ 的计算量。

> **PX4的黑科技**：EKF2的雅可比矩阵不是手写的，而是用**SymForce符号计算工具自动生成**的！
> 
> 源码路径：`src/modules/ekf2/EKF/python/ekf_derivation/`
> 
> 这样做的好处是：推导准确、不易出错、可以快速修改状态定义。缺点是自动生成的代码可读性差。

我们来看covariance.cpp中的核心实现：

```cpp
// covariance.cpp - predictCovariance 函数（简化示意）
void Ekf::predictCovariance(const imuSample &imu_delayed)
{
    const float dt = 0.5f * (imu_delayed.delta_vel_dt + imu_delayed.delta_ang_dt);
    
    // 计算过程噪声
    const float gyro_var = sq(_params.ekf2_gyr_noise);
    float accel_var = sq(_params.ekf2_acc_noise);
    
    // 调用自动生成的协方差预测函数
    P = sym::PredictCovariance(
        _state.vector(), P,
        imu_delayed.delta_vel / imu_delayed.delta_vel_dt, accel_var,
        imu_delayed.delta_ang / imu_delayed.delta_ang_dt, gyro_var,
        dt
    );
    
    // 强制协方差矩阵对称（数值稳定性考虑）
    P.makeSymmetric();
}
```

#### 2.3.3 雅可比矩阵F的数学结构

虽然代码是自动生成的，但我们可以理解雅可比矩阵的分块结构。将状态分为几部分：


$$
\mathbf{x} = \begin{bmatrix} \mathbf{q} \\ \mathbf{v} \\ \mathbf{p} \\ \mathbf{b}_g \\ \mathbf{b}_a \\ \mathbf{m}_I \\ \mathbf{m}_B \\ \mathbf{w} \\ h_{terrain} \end{bmatrix}
$$


状态转移雅可比矩阵 $\mathbf{F}$ 具有以下稀疏结构：


$$
\mathbf{F} = \begin{bmatrix}
\mathbf{F}_{qq} & \mathbf{0} & \mathbf{0} & \mathbf{F}_{qbg} & \mathbf{0} & \mathbf{0} & \mathbf{0} & \mathbf{0} & 0 \\
\mathbf{F}_{vq} & \mathbf{I} & \mathbf{0} & \mathbf{0} & \mathbf{F}_{vba} & \mathbf{0} & \mathbf{0} & \mathbf{0} & 0 \\
\mathbf{0} & \mathbf{I}\Delta t & \mathbf{I} & \mathbf{0} & \mathbf{0} & \mathbf{0} & \mathbf{0} & \mathbf{0} & 0 \\
\mathbf{0} & \mathbf{0} & \mathbf{0} & \mathbf{I} & \mathbf{0} & \mathbf{0} & \mathbf{0} & \mathbf{0} & 0 \\
\mathbf{0} & \mathbf{0} & \mathbf{0} & \mathbf{0} & \mathbf{I} & \mathbf{0} & \mathbf{0} & \mathbf{0} & 0 \\
\mathbf{0} & \mathbf{0} & \mathbf{0} & \mathbf{0} & \mathbf{0} & \mathbf{I} & \mathbf{0} & \mathbf{0} & 0 \\
\mathbf{0} & \mathbf{0} & \mathbf{0} & \mathbf{0} & \mathbf{0} & \mathbf{0} & \mathbf{I} & \mathbf{0} & 0 \\
\mathbf{0} & \mathbf{0} & \mathbf{0} & \mathbf{0} & \mathbf{0} & \mathbf{0} & \mathbf{0} & \mathbf{I} & 0 \\
0 & 0 & 0 & 0 & 0 & 0 & 0 & 0 & 1
\end{bmatrix}
$$


几个关键的非零块：

1. **$\mathbf{F}_{qq}$**：姿态对自身的雅可比。对于四元数运动学 $\dot{\mathbf{q}} = \frac{1}{2}\mathbf{q} \otimes \boldsymbol{\omega}$，离散化后：
   

$$
\mathbf{F}_{qq} = \mathbf{I} - \frac{1}{2} [\Delta\boldsymbol{\theta}]_\times
$$


   其中 $[\cdot]_\times$ 是反对称矩阵算子。

2. **$\mathbf{F}_{vq}$**：速度对姿态的雅可比。加速度测量值通过旋转矩阵投影到导航系，姿态误差会导致速度误差：
   

$$
\mathbf{F}_{vq} = -[\mathbf{C}_b^n (\tilde{\mathbf{a}} - \mathbf{b}_a)]_\times \Delta t
$$


3. **$\mathbf{F}_{qbg}$**：姿态对陀螺零偏的雅可比。陀螺零偏误差会导致姿态积分误差：
   

$$
\mathbf{F}_{qbg} = -\frac{1}{2}\mathbf{C}_b^n \Delta t
$$


> **白话解释**：想象你拿着一个有偏差的指南针走路。指南针偏了1度，你走的方向就偏了1度；走的时间越长，位置偏差就越大。这就是为什么位置误差和姿态误差之间有积分关系。

### 2.4 更新步：多传感器融合的数学与源码

更新步的核心是卡尔曼增益公式：


$$
\mathbf{K}_k = \mathbf{P}_{k|k-1} \mathbf{H}_k^T (\mathbf{H}_k \mathbf{P}_{k|k-1} \mathbf{H}_k^T + \mathbf{R}_k)^{-1}
$$


状态更新：


$$
\hat{\mathbf{x}}_{k|k} = \hat{\mathbf{x}}_{k|k-1} + \mathbf{K}_k (\mathbf{z}_k - h(\hat{\mathbf{x}}_{k|k-1}))
$$


协方差更新（Joseph形式，数值更稳定）：


$$
\mathbf{P}_{k|k} = (\mathbf{I} - \mathbf{K}_k \mathbf{H}_k) \mathbf{P}_{k|k-1} (\mathbf{I} - \mathbf{K}_k \mathbf{H}_k)^T + \mathbf{K}_k \mathbf{R}_k \mathbf{K}_k^T
$$


#### 2.4.1 GNSS位置融合示例

以GNSS位置融合为例，观测方程很简单：


$$
\mathbf{z}_{pos} = \mathbf{p} + \mathbf{v}_{pos}
$$


观测矩阵 $\mathbf{H}$ 是一个3×24的矩阵，只有位置对应的位置是单位矩阵，其余都是0：


$$
\mathbf{H}_{pos} = \begin{bmatrix} \mathbf{0}_{3 \times 3} & \mathbf{0}_{3 \times 3} & \mathbf{I}_{3 \times 3} & \mathbf{0}_{3 \times 15} \end{bmatrix}
$$


我们来看gps_fusion.cpp中的核心实现：

```cpp
// gps_fusion.cpp - 位置融合核心（简化示意）
bool Ekf::fuseHorizontalPosition()
{
    // 1. 计算新息（innovation）：测量值 - 预测值
    const Vector2f innovation(
        _gps_sample_delayed.pos(0) - _state.pos(0),
        _gps_sample_delayed.pos(1) - _state.pos(1)
    );
    
    // 2. 计算观测矩阵H（只有位置对应的位置非零）
    // H是2x24矩阵，对应位置状态的位置为单位矩阵
    
    // 3. 计算新息协方差 S = H*P*H^T + R
    const float pos_obs_var = sq(fmaxf(_params.ekf2_gps_p_noise, 0.01f));
    const float R = pos_obs_var;
    
    // 4. 计算卡尔曼增益 K = P*H^T * S^{-1}
    // 5. 更新状态和协方差
    // ... 具体实现使用矩阵运算
    
    return true;
}
```
&nbsp;

> **工程细节**：实际PX4代码中，融合是分轴进行的（水平位置和高度分开），这样可以避免大矩阵求逆，提高计算效率和数值稳定性。

#### 2.4.2 磁力计融合（非线性观测的例子）

磁力计融合更有趣，因为观测方程是非线性的：


$$
\mathbf{z}_{mag} = \mathbf{C}_n^b(\mathbf{q}) \mathbf{m}_I + \mathbf{m}_B + \mathbf{v}_{mag}
$$


即：机体坐标系下测量的磁场 = 导航系地磁场旋转到机体系 + 机体磁偏置 + 噪声。

观测矩阵 $\mathbf{H}_{mag}$ 需要对姿态求雅可比，这涉及到旋转矩阵的导数：


$$
\frac{\partial (\mathbf{C}_n^b \mathbf{m}_I)}{\partial \delta\boldsymbol{\theta}} = -[\mathbf{C}_n^b \mathbf{m}_I]_\times
$$


> **思考题**：为什么磁力计能估计航向？
> 
> 答案：地磁场在水平面上有一个固定的方向（磁北）。通过测量这个方向并与已知的地磁场方向对比，就可以估计出机体的航向角。这就是为什么磁力计是电子罗盘的原理。

---

## 第三部分：ESKF架构——误差状态卡尔曼滤波

### 3.1 核心思想：名义状态 + 误差状态分离

ESKF（Error-State Kalman Filter，误差状态卡尔曼滤波）是EKF的一种变体，它的核心思想是：

> **把状态拆成两部分："名义状态"（大信号）和"误差状态"（小信号）。名义状态用非线性方程传播，误差状态用线性化的方程传播。**

用数学公式表达：


$$
\mathbf{x}_{true} = \bar{\mathbf{x}} \oplus \delta\mathbf{x}
$$


其中：
- $\bar{\mathbf{x}}$ 是**名义状态**（nominal state）——大信号，非线性传播
- $\delta\mathbf{x}$ 是**误差状态**（error state）——小信号，线性卡尔曼滤波
- $\oplus$ 是**状态合成算子**（composition operator）

对于不同类型的状态，合成算子的定义不同：

| 状态类型 | 合成方式 |
|---------|---------|
| 向量（速度、位置、零偏） | $\delta\mathbf{v} + \bar{\mathbf{v}}$（加法） |
| 旋转（四元数） | $\delta\mathbf{q} \otimes \bar{\mathbf{q}}$（四元数乘法，左扰动） |

> **白话解释**：ESKF就像是"粗调+精调"的思路。名义状态是粗调，用IMU使劲积分，不用管漂移；误差状态是精调，卡尔曼滤波器只估计那个小的误差量，最后把误差补偿回去。

### 3.2 为什么需要ESKF？——直接EKF的四大痛点

#### 痛点1：四元数约束问题

四元数需要满足归一化约束 $\|\mathbf{q}\| = 1$，但在直接EKF中：
- 协方差矩阵会把四元数当作4个独立的量来传播
- 这导致协方差矩阵存在奇异性（因为只有3个自由度）
- 每次更新后都需要手动归一化四元数，这不是严格的卡尔曼滤波步骤

而在ESKF中：
- 名义四元数始终保持归一化（因为四元数积分自然保范）
- 误差状态用3维旋转误差向量 $\delta\boldsymbol{\theta}$ 表示，没有约束问题
- 协方差矩阵定义在切空间上，天然是非奇异的

#### 痛点2：线性化误差大

直接EKF在当前状态估计值处线性化，但如果状态变化大（比如大角度机动），线性化的泰勒展开截断误差就会很大。

ESKF的误差状态始终在原点附近（小量），线性化更准确。这就像：
- 直接EKF：在地球表面某点用切平面近似球面，离该点越远误差越大
- ESKF：始终在原点附近做线性近似，因为误差本身就是小量

#### 痛点3：计算量大

直接EKF用全状态（24维）做卡尔曼滤波，矩阵运算量大。

ESKF只需要对误差状态（通常15维左右）做滤波，名义状态的积分是简单的向量/四元数运算，计算量小很多。

#### 痛点4：物理意义不清晰

直接EKF把零偏、磁场等慢变状态和姿态、速度等快变状态混在一起，物理意义不清晰。

ESKF中，名义状态反映了系统的主体运动，误差状态反映了各种误差源的累积影响，物理意义更清晰。

### 3.3 ESKF的状态向量定义

典型的ESKF状态定义（15维误差状态）：

| 误差状态 | 符号 | 维度 | 物理意义 |
|---------|------|------|---------|
| 姿态误差 | $\delta\boldsymbol{\theta}$ | 3 | 小角度旋转误差（轴角表示） |
| 速度误差 | $\delta\mathbf{v}$ | 3 | NED速度误差 |
| 位置误差 | $\delta\mathbf{p}$ | 3 | NED位置误差 |
| 陀螺零偏误差 | $\delta\mathbf{b}_g$ | 3 | 陀螺仪偏差误差 |
| 加计零偏误差 | $\delta\mathbf{b}_a$ | 3 | 加速度计偏差误差 |

对应的名义状态（16维）：

| 名义状态 | 符号 | 维度 |
|---------|------|------|
| 姿态四元数 | $\bar{\mathbf{q}}$ | 4 |
| 速度 | $\bar{\mathbf{v}}$ | 3 |
| 位置 | $\bar{\mathbf{p}}$ | 3 |
| 陀螺零偏 | $\bar{\mathbf{b}}_g$ | 3 |
| 加计零偏 | $\bar{\mathbf{b}}_a$ | 3 |

> **关键洞察**：注意误差状态是15维，而名义状态是16维（四元数4维 + 其他12维）。这是因为3维的旋转误差向量对应4维四元数的一个切空间——这正是ESKF的精髓所在！

### 3.4 ESKF预测步：双轨并行

ESKF的预测步分为两条并行的轨道：

#### 轨道1：名义状态传播（非线性）

名义状态的传播和直接EKF的状态预测完全一样，就是标准的捷联惯导机械编排：


$$
\dot{\bar{\mathbf{q}}} = \frac{1}{2} \bar{\mathbf{q}} \otimes (\tilde{\boldsymbol{\omega}} - \bar{\mathbf{b}}_g)
$$


$$
\dot{\bar{\mathbf{v}}} = \mathbf{C}_b^n(\bar{\mathbf{q}}) \cdot (\tilde{\mathbf{a}} - \bar{\mathbf{b}}_a) + \mathbf{g}^n
$$


$$
\dot{\bar{\mathbf{p}}} = \bar{\mathbf{v}}
$$


$$
\dot{\bar{\mathbf{b}}}_g = 0, \quad \dot{\bar{\mathbf{b}}}_a = 0
$$


> 零偏的名义值保持不变，它们的变化由误差状态的随机游走描述。

#### 轨道2：误差状态传播（线性）

误差状态的传播方程是线性的，由误差动力学推导而来。本文采用**右扰动（机体坐标系误差）** 约定（即 $\mathbf{R}_{true} = \hat{\mathbf{R}} \mathbf{R}(\delta\boldsymbol{\theta}) \approx \hat{\mathbf{R}}(\mathbf{I} + [\delta\boldsymbol{\theta}]_\times)$）。连续时间的误差状态方程为：


$$
\delta\dot{\boldsymbol{\theta}} = -[\tilde{\boldsymbol{\omega}} - \bar{\mathbf{b}}_g]_\times \delta\boldsymbol{\theta} - \delta\mathbf{b}_g - \mathbf{n}_g
$$


$$
\delta\dot{\mathbf{v}} = -\mathbf{C}_b^n [\tilde{\mathbf{a}} - \bar{\mathbf{b}}_a]_\times \delta\boldsymbol{\theta} - \mathbf{C}_b^n \delta\mathbf{b}_a - \mathbf{C}_b^n \mathbf{n}_a
$$


$$
\delta\dot{\mathbf{p}} = \delta\mathbf{v}
$$


$$
\delta\dot{\mathbf{b}}_g = \mathbf{n}_{bg}, \quad \delta\dot{\mathbf{b}}_a = \mathbf{n}_{ba}
$$


其中 $\mathbf{n}_g, \mathbf{n}_a$ 是陀螺和加计的白噪声，$\mathbf{n}_{bg}, \mathbf{n}_{ba}$ 是零偏随机游走噪声。

> 💡 **架构对齐注解**：
> 注意速度误差微分 $\delta\dot{\mathbf{v}}$ 中的姿态耦合项：由于姿态误差 $\delta\boldsymbol{\theta}$ 在机体系，加速度叉乘必须在机体系进行后、再通过 $\mathbf{C}_b^n$ 投影到导航系（或者写成 $-[\mathbf{C}_b^n(\tilde{\mathbf{a}} - \bar{\mathbf{b}}_a)]_\times \mathbf{C}_b^n \delta\boldsymbol{\theta}$）。同时由于 $\mathbf{a}_{true} = \tilde{\mathbf{a}} - \mathbf{b}_a - \mathbf{n}_a$，零偏和噪声项在误差方程中均引入**负号**。

写成矩阵形式：


$$
\delta\dot{\mathbf{x}} = \mathbf{F}(t) \delta\mathbf{x} + \mathbf{G}(t) \mathbf{n}(t)
$$


离散化后得到误差状态的协方差传播方程：


$$
\mathbf{P}_{k|k-1} = \mathbf{\Phi}_{k,k-1} \mathbf{P}_{k-1|k-1} \mathbf{\Phi}_{k,k-1}^T + \mathbf{Q}_k
$$


其中 $\mathbf{\Phi}_{k,k-1}$ 是状态转移矩阵，$\mathbf{Q}_k$ 是离散过程噪声协方差。

> **对比直接EKF**：注意这里的 $\mathbf{F}$ 矩阵和直接EKF的雅可比矩阵形式上很像，但物理意义不同：
> - 直接EKF的 $\mathbf{F}$ 是全状态非线性方程的雅可比
> - ESKF的 $\mathbf{F}$ 是误差状态的线性动力学矩阵
> - 虽然数学形式相似，但ESKF的线性化更准确，因为误差是小量

### 3.5 ESKF更新步：先修正误差，再注入名义

ESKF的更新步和直接EKF类似，但作用在误差状态上：

1. **计算观测雅可比**：观测对误差状态的偏导数 $\mathbf{H}_\delta$
2. **计算卡尔曼增益**：$\mathbf{K} = \mathbf{P} \mathbf{H}_\delta^T (\mathbf{H}_\delta \mathbf{P} \mathbf{H}_\delta^T + \mathbf{R})^{-1}$
3. **更新误差状态**：$\delta\hat{\mathbf{x}} \leftarrow \delta\hat{\mathbf{x}} + \mathbf{K} (\mathbf{z} - h(\bar{\mathbf{x}}))$
4. **更新误差协方差**：$\mathbf{P} \leftarrow (\mathbf{I} - \mathbf{K} \mathbf{H}_\delta) \mathbf{P}$

关键的一步来了：**误差状态注入（error state injection）**

把估计出的误差状态"加"到名义状态上，然后把误差状态重置为零：

```
// 误差注入伪代码
bar_q = delta_q ⊗ bar_q    // 姿态：四元数左乘
bar_v = bar_v + delta_v    // 速度：加法
bar_p = bar_p + delta_p    // 位置：加法
bar_bg = bar_bg + delta_bg // 陀螺零偏：加法
bar_ba = bar_ba + delta_ba // 加计零偏：加法

delta_x = 0                // 误差状态重置为零
```
&nbsp;
> **为什么要重置误差状态？**
> 
> 因为误差状态的定义是"相对于名义状态的误差"。当我们把误差补偿到名义状态后，新的名义状态已经包含了修正，所以新的误差应该从0开始重新累积。
> 
> 这就像你用尺子量东西：先粗量一个大概（名义状态），然后用游标卡尺读小数（误差状态）。读完之后，你把小数加到整数上，然后游标归零，下次再用。

### 3.6 ESKF源码分析——以PX4早期实现为例

PX4早期的姿态估计器（attitude_estimator_q）实际上就用了ESKF的思想。让我们看一个简化的ESKF实现框架：

```cpp
// ESKF 核心类框架（示意代码，非PX4原始代码）
class ESKF {
public:
    // 名义状态
    Quatf  q;     // 姿态四元数
    Vector3f v;   // 速度
    Vector3f p;   // 位置
    Vector3f bg;  // 陀螺零偏
    Vector3f ba;  // 加计零偏
    
    // 误差协方差（15x15）
    Matrix<float, 15, 15> P;
    
    // 预测步：输入IMU数据
    void predict(const Vector3f& ang_vel, const Vector3f& accel, float dt) {
        // ===== 轨道1：名义状态传播 =====
        // 1. 四元数积分
        Vector3f corrected_omega = ang_vel - bg;
        Quatf delta_q;
        delta_q.fromAxisAngle(corrected_omega * dt);
        q = q * delta_q;
        q.normalize();
        
        // 2. 速度积分
        Dcmf R(q);
        Vector3f corrected_accel = accel - ba;
        v += R * corrected_accel * dt + Vector3f(0, 0, G) * dt;
        
        // 3. 位置积分
        p += v * dt;
        
        // ===== 轨道2：误差协方差传播 =====
        // 计算状态转移矩阵 Phi
        Matrix<float, 15, 15> Phi = computeStateTransition(ang_vel, accel, dt);
        
        // 计算过程噪声矩阵 Q
        Matrix<float, 15, 15> Q = computeProcessNoise(ang_vel, accel, dt);
        
        // 协方差传播
        P = Phi * P * Phi.transpose() + Q;
    }
    
    // 更新步：例如GNSS位置更新
    void updatePosition(const Vector3f& pos_meas, const Vector3f& pos_noise) {
        // 1. 计算新息
        Vector3f innovation = pos_meas - p;
        
        // 2. 观测矩阵（对误差状态的雅可比）
        // 位置观测对位置误差的雅可比是单位矩阵
        Matrix<float, 3, 15> H;
        H.setZero();
        H.block<3, 3>(0, 9) = Matrix3f::Identity();  // 位置误差在索引9-11
        
        // 3. 卡尔曼增益
        Matrix<float, 3, 3> S = H * P * H.transpose();
        S.diagonal() += pos_noise.cwiseProduct(pos_noise);
        Matrix<float, 15, 3> K = P * H.transpose() * S.inverse();
        
        // 4. 更新误差状态
        Matrix<float, 15, 1> dx = K * innovation;
        
        // 5. 误差注入到名义状态
        injectError(dx);
        
        // 6. 更新协方差
        P = (Matrix<float, 15, 15>::Identity() - K * H) * P;
    }
    
private:
    // 误差注入
    void injectError(const Matrix<float, 15, 1>& dx) {
        Vector3f dtheta = dx.block<3, 1>(0, 0);
        Vector3f dv     = dx.block<3, 1>(3, 0);
        Vector3f dp     = dx.block<3, 1>(6, 0);
        Vector3f dbg    = dx.block<3, 1>(9, 0);
        Vector3f dba    = dx.block<3, 1>(12, 0);
        
        // 姿态误差：小角度近似下，delta_q ≈ [1, dtheta/2]
        Quatf delta_q;
        delta_q(0) = 1.0f;
        delta_q(1) = 0.5f * dtheta(0);
        delta_q(2) = 0.5f * dtheta(1);
        delta_q(3) = 0.5f * dtheta(2);
        q = delta_q * q;  // 左扰动
        q.normalize();
        
        // 速度、位置、零偏：加法
        v += dv;
        p += dp;
        bg += dbg;
        ba += dba;
        
        // 误差状态不需要显式清零，因为我们从不存储误差状态
        // 误差只体现在协方差矩阵P中
    }
};
```
&nbsp;
> **重要细节**：注意 ESKF 中没有显式存储误差状态向量 $\delta\mathbf{x}$！为什么?!?
> 
> 因为每次更新后都把误差注入到名义状态，然后误差就"消失"了。唯一需要存储的是误差的不确定性——协方差矩阵 $\mathbf{P}$。
> 
> 这是ESKF一个非常巧妙的设计：**误差状态是虚拟的，只存在于协方差矩阵中**。名义状态是真实的，存储了系统的当前估计。

### 3.7 ESKF的几种"风味"

ESKF有不同的实现变体，主要区别在于：

1. **扰动方向**：
   - **左扰动**：$\mathbf{q}_{true} = \delta\mathbf{q} \otimes \bar{\mathbf{q}}$（误差定义在导航系）
   - **右扰动**：$\mathbf{q}_{true} = \bar{\mathbf{q}} \otimes \delta\mathbf{q}$（误差定义在机体系）
   
   大部分飞控使用右扰动（因为IMU测量在机体系），但也有例外。

2. **误差注入后的协方差处理**：
   - **简单重置**：直接用新的协方差，不做特殊处理
   - **雅可比修正**：考虑误差注入对协方差的影响，乘以雅可比矩阵
   
   当误差很小时，简单重置是可以接受的。但严格来说，需要进行协方差的"重置雅可比"修正。

---

## 第四部分：EKF vs ESKF 本质对比

### 4.1 核心差异对照表

| 对比维度 | 直接EKF（PX4 EKF2风格） | ESKF |
|---------|---------------------|------|
| **状态表示** | 全状态直接估计 | 名义状态 + 误差状态分离 |
| **四元数处理** | 4维四元数进入状态向量，有约束问题 | 误差用3维δθ表示，无约束，协方差天然非奇异 |
| **非线性处理** | 全状态非线性，在当前估计处线性化 | 仅误差状态线性化，误差始终是小量，线性化更准确 |
| **状态维度** | 24维（全状态） | 误差状态15维（更小的矩阵运算） |
| **计算量** | 24×24矩阵运算，量大 | 15×15矩阵运算 + 名义状态积分，量小 |
| **物理直观性** | 状态直观，但四元数约束问题不优雅 | 需要理解"双轨"思想，但误差物理意义清晰 |
| **工程复杂度** | 相对直接，一个状态向量贯穿始终 | 需要处理误差注入、重置，状态合成算子需单独定义 |
| **线性化精度** | 大角度机动时线性化误差大 | 误差始终是小量，线性化精度高 |
| **数值稳定性** | 需注意四元数归一化、协方差对称化 | 天然更稳定，无约束问题 |
| **飞控应用现状** | PX4 EKF2、ArduPilot EKF3（主流） | 早期PX4、部分小型飞控、学术研究 |

### 4.2 数学本质：流形 vs 向量空间

要真正理解EKF和ESKF的区别，需要一点微分几何的视角：

- **直接EKF**：试图把四元数当作4维向量空间中的元素来处理，这是"勉强"的——因为四元数实际上生活在3维球面 $S^3$ 上（归一化约束），而不是4维欧氏空间 $\mathbb{R}^4$。
- **ESKF**：承认姿态生活在李群 $SO(3)$ 流形上，误差状态定义在流形的切空间（李代数 $\mathfrak{so}(3)$）上。卡尔曼滤波只在切空间（向量空间）中运行，名义状态在流形上演化。

> **白话解释**：想象你要描述地球表面上的位置。
> 
> - 直接EKF的做法：用经纬度两个数来表示位置，然后直接对这两个数做卡尔曼滤波。但问题是：经度在极点处会奇异性（所有经线交汇于一点），而且纬度90度和-90度实际上是同一个点。
> 
> - ESKF的做法：先用经纬度表示你的大概位置（名义状态，在球面上），然后用"向北走多少米、向东走多少米"来表示误差（误差状态，在切平面上）。误差是小量，所以切平面近似足够准确。
> 
> 姿态的四元数就像球面上的点（都有归一化约束），而旋转误差向量就像切平面上的位移。ESKF把滤波放在切平面上做，天然避开了奇异性问题。

### 4.3 计算量对比

我们来粗略估算一下两种架构的计算量：

**直接EKF（24维）**：
- 协方差预测：$\mathbf{P} = \mathbf{F}\mathbf{P}\mathbf{F}^T + \mathbf{Q}$，约 $2n^3 = 2 \times 24^3 = 27,648$ 次乘法
- 卡尔曼增益计算：$\mathbf{K} = \mathbf{P}\mathbf{H}^T(\mathbf{H}\mathbf{P}\mathbf{H}^T + \mathbf{R})^{-1}$，取决于观测维度

**ESKF（15维误差）**：
- 协方差预测：约 $2 \times 15^3 = 6,750$ 次乘法
- 名义状态积分：四元数乘法、矩阵乘法等，约几十次运算
- 总计算量约为直接EKF的 1/4

> **但等等**：PX4 EKF2实际上有24个状态，但它的协方差矩阵真的是24×24全矩阵运算吗？
> 
> 答案是：是的。但PX4做了很多优化：
> 1. 利用矩阵的稀疏性（很多状态之间没有耦合）
> 2. 分轴更新（比如水平位置和高度分开更新）
> 3. SymForce生成优化的代码
> 
> 即使如此，24维仍然比15维计算量大。

### 4.4 一个常见的误解：PX4 EKF2到底是不是ESKF？

这是一个非常好的问题。很多资料说PX4 EKF2是ESKF，但也有说它是直接EKF的。真相是：

> **PX4 EKF2是一个混合架构**——它既有直接EKF的特征，也吸收了ESKF的思想。

具体来说：
1. **名义状态 + 误差协方差的思想**：EKF2有`quat_nominal`（名义四元数），协方差矩阵描述的是误差的不确定性，这很像ESKF。
2. **全状态向量**：EKF2的状态向量包含了所有状态（姿态、速度、位置、零偏、磁场、风...），并且协方差矩阵是24×24的全矩阵，这又像直接EKF。
3. **四元数处理**：EKF2使用四元数作为姿态的参数化，但协方差中姿态只占3个自由度（使用了错误状态的思想），这是ESKF的特征。

> **个人观点**：称呼不重要，重要的是理解背后的思想。现代飞控的EKF往往是混合架构，吸收了各种方法的优点。PX4 EKF2更准确的称呼应该是"基于误差状态的EKF"——它用误差状态的思想来处理姿态的约束问题，但同时估计所有状态的误差（不仅仅是15维）。

---

## 第五部分：飞控算法选型思考

### 5.1 为什么PX4从ESKF切换到了"全状态EKF2"？

了解了两种架构的对比后，一个自然的问题是：既然ESKF有这么多优点（计算量小、线性化准、无约束问题），为什么PX4还要切换到EKF2？

答案是：**算力提升 + 需求驱动**。

#### 原因1：MCU算力越来越强

- 早期飞控用的是STM32F4（168MHz Cortex-M4）
- 后来升级到STM32F7（216MHz Cortex-M7）
- 现在主流是STM32H7（480MHz Cortex-M7）

算力提升了3-5倍，24维矩阵运算不再是瓶颈。

#### 原因2：需要估计的状态越来越多

早期的ESKF通常只估计15个状态（姿态、速度、位置、两个零偏）。但现代飞控需要估计的状态越来越多：

- 地磁场（3维）：用于磁力计融合
- 机体磁偏置（3维）：用于校准磁干扰
- 风速（2维）：固定翼飞机需要
- 地形高度（1维）：用于地形跟踪
- 视觉尺度误差：VIO应用
- ...

状态多了之后，ESKF"名义状态+误差状态"的两分法就不那么清晰了——哪些状态应该有名义值？磁场需要吗？风速需要吗？

而直接EKF的全状态框架更灵活：加一个状态就是在状态向量末尾加一维，雅可比矩阵自动生成，不需要额外考虑"名义/误差"的拆分。

#### 原因3：多传感器融合的灵活性

直接EKF可以很方便地添加新的传感器融合类型，只需要：
1. 写观测方程
2. 求观测雅可比
3. 调用标准的EKF更新流程

而ESKF需要考虑每种观测对误差状态的影响，虽然原理一样，但心理上更绕。

### 5.2 ESKF在什么场景下仍然有优势？

虽然主流飞控转向了全状态EKF，但ESKF仍然有它的用武之地：

#### 场景1：资源受限的微控制器

如果你用的是性能较弱的MCU（如STM32F1、F4），或者需要极高的更新频率（如1kHz以上），15维的ESKF比24维的EKF计算量小很多。

#### 场景2：对精度要求极高的应用

ESKF的线性化误差更小，在大角度机动、高动态的场景下，理论上比直接EKF更准确。这对于需要高精度的应用（如无人机测绘、自动驾驶）有价值。

> **但实际上**：现代EKF2的实现也吸收了ESKF的优点，比如用误差状态的思想来处理四元数约束。真正的精度差异可能很小。

#### 场景3：学术研究和教学

ESKF的结构更清晰地分离了"大信号"和"小信号"，更适合教学和理解卡尔曼滤波的本质。很多经典的SLAM（同步定位与地图构建）算法（如MSCKF）也是基于ESKF思想的。

### 5.3 学习建议：从ESKF入门，向全状态EKF进阶

对于初学者（比如正在看这篇文章的你），我的建议是：

1. **先学ESKF**：因为它的结构更清晰，物理意义更明确，能帮你建立"误差"的直觉。搞懂了ESKF，你就真正理解了卡尔曼滤波的本质——它估计的是"误差"，不是"状态"本身。

2. **再学全状态EKF**：理解了ESKF之后，看全状态EKF就会发现它只是把所有状态的误差都放在一个向量里估计，本质是一样的。

3. **读源码的顺序**：
   - 先读简单的ESKF实现（比如小型飞控的姿态估计器）
   - 再读PX4 EKF2的核心部分
   - 最后看EKF2的复杂融合（光流、视觉、激光雷达等）

> **一句话总结**：ESKF是"道"，全状态EKF是"术"。悟了道，术就只是细节。

---

## 第六部分：动手实践——一个简化的ESKF实现

为了帮助你更好地理解，这里提供一个极简的ESKF实现（仅姿态估计）。你可以把它和Mahony滤波对比，体会卡尔曼滤波的不同之处。

```cpp
// 简化版ESKF姿态估计器（仅融合IMU+加速度计）
class SimpleESKF {
public:
    SimpleESKF() {
        q = Quatf::identity();
        P.setZero();
        P.diagonal() << 0.01f, 0.01f, 0.01f,  // 初始姿态方差
                        0.001f, 0.001f, 0.001f; // 初始零偏方差
    }
    
    // 预测步：陀螺仪测量
    void predict(const Vector3f& gyro, float dt) {
        // 名义状态传播
        Vector3f corrected_gyro = gyro - bg;
        Quatf delta_q;
        delta_q.fromAxisAngle(corrected_gyro * dt);
        q = q * delta_q;
        q.normalize();
        
        // 协方差传播
        // 状态转移矩阵 Phi = I + F*dt
        Matrix<float, 6, 6> F;
        F.setZero();
        // 姿态误差动力学：d(dtheta)/dt = -[omega]_x * dtheta - dbg
        F.block<3, 3>(0, 0) = -skew(corrected_gyro);
        F.block<3, 3>(0, 3) = -Matrix3f::Identity();
        // 零偏随机游走：d(dbg)/dt = 0（在Q中体现）
        
        Matrix<float, 6, 6> Phi = Matrix<float, 6, 6>::Identity() + F * dt;
        
        // 过程噪声
        Matrix<float, 6, 6> Q;
        Q.setZero();
        const float gyro_noise = 0.003f;  // 陀螺仪噪声密度 rad/s/sqrt(Hz)
        const float bias_noise = 0.0001f; // 零偏随机游走 rad/s^2/sqrt(Hz)
        Q.block<3, 3>(0, 0) = gyro_noise * gyro_noise * dt * Matrix3f::Identity();
        Q.block<3, 3>(3, 3) = bias_noise * bias_noise * dt * Matrix3f::Identity();
        
        P = Phi * P * Phi.transpose() + Q;
    }
    
    // 更新步：加速度计测量（修正roll和pitch）
    void updateAccel(const Vector3f& accel) {
        // 测量模型：在机体系下，加速度计应该测量到重力的反方向
        // 导航系重力向下（正），旋转到机体系
        Vector3f gravity_body = q.inversed() * Vector3f(0, 0, 1.0f);
        
        // 加速度测量应该和-gravity_body同方向（因为加速度计测量的是比力）
        Vector3f accel_norm = accel.normalized();
        Vector3f expected_norm = -gravity_body.normalized();
        
        // 新息：两个单位向量的误差，用叉乘表示
        Vector3f innovation = expected_norm.cross(accel_norm);
        
        // 观测矩阵：加速度计对姿态误差的雅可比
        // 对于小角度误差，观测方程的雅可比近似为 -[g_body]_x
        Matrix<float, 3, 6> H;
        H.setZero();
        H.block<3, 3>(0, 0) = -skew(gravity_body);
        
        // 测量噪声
        const float accel_noise = 0.1f;
        Matrix3f R = accel_noise * accel_noise * Matrix3f::Identity();
        
        // 卡尔曼增益
        Matrix3f S = H * P * H.transpose() + R;
        Matrix<float, 6, 3> K = P * H.transpose() * S.inverse();
        
        // 更新误差状态并注入
        Vector<float, 6> dx = K * innovation;
        
        // 注入姿态误差
        Vector3f dtheta = dx.segment<3>(0);
        Quatf delta_q;
        delta_q.w() = 1.0f;
        delta_q.vec() = 0.5f * dtheta;
        q = delta_q * q;
        q.normalize();
        
        // 注入零偏误差
        bg += dx.segment<3>(3);
        
        // 更新协方差
        P = (Matrix<float, 6, 6>::Identity() - K * H) * P;
    }
    
    // 获取欧拉角（ZYX顺序）
    Vector3f getEuler() const {
        return q.toEuler();
    }
    
private:
    Quatf q;                // 名义四元数
    Vector3f bg;            // 陀螺零偏
    Matrix<float, 6, 6> P;  // 误差协方差（3姿态 + 3零偏）
    
    // 反对称矩阵工具函数
    static Matrix3f skew(const Vector3f& v) {
        Matrix3f m;
        m << 0, -v(2), v(1),
             v(2), 0, -v(0),
             -v(1), v(0), 0;
        return m;
    }
};
```

> **练习建议**：
> 1. 把这段代码和你学过的Mahony滤波对比，看看有什么异同？
> 2. 卡尔曼增益K和Mahony滤波的Kp、Ki有什么关系？
> 3. 如果我想加入磁力计融合来估计航向，应该怎么修改updateMag函数？

---

## 参考文献与延伸阅读

### 经典论文
1. **Quaternion kinematics for the error-state Kalman filter** - Joan Solà, 2017
   > ESKF领域的经典综述，公式详尽，推导严谨。强烈推荐精读。
   > 地址：https://arxiv.org/abs/1711.02508

2. **Indirect Kalman Filter for 3D Attitude Estimation** - Nikolas Trawny, Stergios Roumeliotis
   > 明尼苏达大学的技术报告，详细推导了间接卡尔曼滤波（即ESKF）的姿态估计。

### 开源项目
1. **PX4 Autopilot** - https://github.com/PX4/PX4-Autopilot
   > 本文的主要参考对象，EKF2模块在 `src/modules/ekf2/` 目录下。

2. **ArduPilot** - https://github.com/ArduPilot/ardupilot
   > 另一个开源飞控，它的EKF3也是直接EKF架构，可以和PX4对比学习。

### 书籍
1. **捷联惯导算法与组合导航原理** - 严恭敏
   > 国内经典教材，详细讲解了捷联惯导的机械编排和误差分析。

2. **最优状态估计：卡尔曼、H∞及非线性滤波** - Dan Simon
   > 卡尔曼滤波的经典教材，从基础到进阶，涵盖EKF、UKF等内容。

---

> **写在最后**：
> 
> 卡尔曼滤波不是一堆公式的堆砌，而是一种"用不确定性推理"的思维方式。无论是直接EKF还是ESKF，本质上都是在做同一件事——用传感器的不确定性来量化状态的不确定性。
> 
> 希望这篇文章能帮你建立起直觉。当你下次再看满屏的矩阵公式时，能笑着说："哦，原来这玩意儿就是这么回事儿啊。"
> 
> —— 一位走过弯路的学长

---


