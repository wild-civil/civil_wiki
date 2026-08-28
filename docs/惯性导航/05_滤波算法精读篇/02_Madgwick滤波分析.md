
# Madgwick 滤波（梯度下降姿态解算）分析

> 对标 Mahony 滤波的进阶学习笔记，从梯度下降优化的角度理解四元数姿态解算。
> 本文分析蓝本：**Arduino MadgwickAHRS 开源库**（x-io 官方算法的标准移植）
> GitHub 仓库：https://github.com/arduino-libraries/MadgwickAHRS

---

## 先明确坐标系约定（和 Mahony 完全一致）

在牛小骥老师团队的 NED+FRD 约定下：

| 坐标系 | 原点 | X 轴 | Y 轴 | Z 轴 |
|--------|------|------|------|------|
| **导航系 (n-frame, NED)** | IMU 初始位置 | 指向北 (North) | 指向东 (East) | 指向地 (Down) |
| **载体系 (b-frame, FRD)** | IMU 中心 | 指向前 (Front) | 指向右 (Right) | 指向地 (Down) |

**重力方向**：导航系中重力沿 +Z 方向（指向地），即 $\mathbf{g}^n = [0, 0, g]^T$

**四元数定义**：${}^n_b q$ 表示从 b 系到 n 系的旋转，即 $\mathbf{v}^n = q \otimes \mathbf{v}^b \otimes q^*$

> 注意：Madgwick 原始代码使用 ENU 约定（q3 对应 Z 轴向上），但公式推导的数学本质与坐标系选择无关。
> 本文采用武大 NED 体系重新解读，原理完全等价。

---

## 第一部分：定义与初始化

### 1.1 宏定义与核心参数

以 MadgwickAHRS 库为例（[MadgwickAHRS.cpp 第 29-30 行](https://github.com/arduino-libraries/MadgwickAHRS/blob/master/src/MadgwickAHRS.cpp#L29-L30)）：

```c
#define sampleFreqDef   512.0f          // sample frequency in Hz
#define betaDef         0.1f            // 2 * proportional gain
```

**参数说明**：

| 参数 | 典型值 | 含义 |
|------|--------|------|
| `sampleFreqDef` | 512 Hz | 采样频率，Madgwick 算法对低采样率容忍度很高 |
| `beta` | 0.1 | **梯度下降增益**，相当于 Mahony 中的 $K_p$，控制加速度计/磁力计修正力度 |

> 💡 **beta 的物理意义**
> 
> `beta = 0.1` 是 Madgwick 论文推荐的默认值，代表陀螺仪的测量误差（漂移率）。
> 单位是 rad/s，即陀螺仪的零偏不稳定性约为 0.1 rad/s ≈ 5.7°/s。
> 
> - beta 越大 → 越信任加速度计/磁力计 → 收敛快但动态误差大
> - beta 越小 → 越信任陀螺仪 → 平滑但漂移修正慢
> 
> 调参口诀：**静态精度差就调大 beta，动态精度差就调小 beta**

---

### 1.2 类成员变量（滤波器状态）

（[MadgwickAHRS.h 第 24-36 行](https://github.com/arduino-libraries/MadgwickAHRS/blob/master/src/MadgwickAHRS.h#L24-L36)）

```c
class Madgwick{
private:
    float beta;                 // algorithm gain
    float q0, q1, q2, q3;      // quaternion of sensor frame relative to auxiliary frame
    float invSampleFreq;        // 1 / sampleFreq
    float roll, pitch, yaw;     // 缓存的欧拉角
    char anglesComputed;        // 角度计算标志位（延迟计算优化）
    ...
};
```

**变量分类**：

| 类别 | 变量 | 作用 |
|------|------|------|
| **滤波参数** | `beta` | 梯度下降步长增益 |
| **姿态状态** | `q0, q1, q2, q3` | 姿态四元数（核心状态量） |
| **时间参数** | `invSampleFreq` | 采样周期的倒数（预计算优化） |
| **输出缓存** | `roll, pitch, yaw` | 欧拉角缓存，避免重复计算 |
| **优化标志** | `anglesComputed` | 懒加载标志，只有调用 get 时才计算欧拉角 |

> 💡 **和 Mahony 的对比**
> 
> | 特性 | Mahony | Madgwick |
> |------|--------|----------|
> | 姿态表示 | 四元数 | 四元数 |
> | 误差计算 | 向量叉乘（几何直观） | 梯度下降（优化视角） |
> | 比例增益 | $K_p$ | $\beta$ |
> | 积分增益 | $K_i$（估计零偏） | 无（IMU 版本无零偏估计） |
> | 计算量 | 小（~50 次运算） | 大（~110 次运算） |

---

### 1.3 构造函数与初始化

（[MadgwickAHRS.cpp 第 39-47 行](https://github.com/arduino-libraries/MadgwickAHRS/blob/master/src/MadgwickAHRS.cpp#L39-L47)）

```c
Madgwick::Madgwick() {
    beta = betaDef;
    q0 = 1.0f;
    q1 = 0.0f;
    q2 = 0.0f;
    q3 = 0.0f;
    invSampleFreq = 1.0f / sampleFreqDef;
    anglesComputed = 0;
}
```

初始四元数 $q = [1, 0, 0, 0]$，对应单位旋转（b 系与 n 系完全重合）。

> ⚠️ **实际使用注意**
> 
> 上电时 IMU 不一定水平，所以初始四元数应该用加速度计计算初始姿态，
> 而不是直接设为单位四元数。否则滤波器需要数秒才能收敛到正确姿态。

---

## 第二部分：核心数学原理（梯度下降法）

### 2.1 核心思想：把姿态解算转化为优化问题

Mahony 用的是**几何直观**（叉乘找误差方向），Madgwick 用的是**优化视角**（最小二乘找最优姿态）。

**问题定义**：
- 已知：加速度计测量值 $\mathbf{a}^b$（b 系），重力参考向量 $\mathbf{g}^n = [0, 0, 1]^T$（n 系，归一化）
- 求解：最优四元数 $q$，使得将 $\mathbf{g}^n$ 旋转到 b 系后，与 $\mathbf{a}^b$ 尽可能接近

**目标函数**（残差函数）：


$$
f(q, \mathbf{g}^n, \mathbf{a}^b) = q^* \otimes \mathbf{g}^n \otimes q - \mathbf{a}^b
$$


我们的目标是找到 $q$ 使得 $\|f\|^2$ 最小——这就是一个典型的非线性最小二乘问题。

---

### 2.2 梯度下降法

对于最小化 $\|f(q)\|^2$ 的问题，梯度下降法的迭代公式为：


$$
q_{k+1} = q_k - \alpha \cdot \nabla f
$$


其中梯度 $\nabla f$ 是目标函数的雅可比矩阵的转置乘以残差：


$$
\nabla f = J^T(q) \cdot f(q)
$$


$J(q)$ 是 $f(q)$ 关于 $q$ 的雅可比矩阵。

---

### 2.3 加速度计残差的雅可比推导

加速度计的目标函数（展开为标量形式）：


$$
f_g(q, \mathbf{a}^b) = \begin{bmatrix}
2(q_1 q_3 - q_0 q_2) - a_x \\
2(q_0 q_1 + q_2 q_3) - a_y \\
2(0.5 - q_1^2 - q_2^2) - a_z
\end{bmatrix}
$$


> 这是将 n 系重力 $[0,0,1]^T$ 用四元数旋转到 b 系的结果，减去加速度计测量值。

对四元数各分量求偏导，得到雅可比矩阵 $J_g$（3×4 矩阵）：


$$
J_g = \frac{\partial f_g}{\partial q} = \begin{bmatrix}
-2q_2 & 2q_3 & -2q_0 & 2q_1 \\
2q_1 & 2q_0 & 2q_3 & 2q_2 \\
0 & -4q_1 & -4q_2 & 0
\end{bmatrix}
$$


梯度方向 = 雅可比转置 × 残差：


$$
\nabla f_g = J_g^T \cdot f_g
$$


这是一个 4 维向量，对应四元数四个分量的修正方向。

---

### 2.4 磁力计残差（AHRS 版本）

对于带磁力计的 AHRS 系统，还需要增加磁场的目标函数。

地磁场在 n 系的参考方向为 $\mathbf{b}^n = [b_x, 0, b_z]^T$（北向和地向分量）。

磁力计的目标函数：


$$
f_b(q, \mathbf{m}^b, \mathbf{b}^n) = q^* \otimes \mathbf{b}^n \otimes q - \mathbf{m}^b
$$


对应的雅可比矩阵 $J_b$（3×4 矩阵）。

总梯度 = 加速度计梯度 + 磁力计梯度：


$$
\nabla f = \nabla f_g + \nabla f_b
$$


---

### 2.5 梯度下降修正步长

代码中计算的 `s0, s1, s2, s3` 就是梯度方向 $\nabla f$：

```c
// Gradient decent algorithm corrective step（IMU 版本，第 196-199 行）
s0 = _4q0 * q2q2 + _2q2 * ax + _4q0 * q1q1 - _2q1 * ay;
s1 = _4q1 * q3q3 - _2q3 * ax + 4.0f * q0q0 * q1 - _2q0 * ay - _4q1 + _8q1 * q1q1 + _8q1 * q2q2 + _4q1 * az;
s2 = 4.0f * q0q0 * q2 + _2q0 * ax + _4q2 * q3q3 - _2q3 * ay - _4q2 + _8q2 * q1q1 + _8q2 * q2q2 + _4q2 * az;
s3 = 4.0f * q1q1 * q3 - _2q1 * ax + 4.0f * q2q2 * q3 - _2q2 * ay;
```

> 🧮 **代码优化技巧**
> 
> 你看到的 `_2q0`, `_4q0`, `_8q1`, `q0q0` 等都是预计算的辅助变量，
> 目的是避免重复计算乘法（第 180-193 行）。这是典型的嵌入式优化手段——
> 用内存换算力，把公共因子提前算好存起来。

计算完梯度方向后，需要**归一化**（第 200-204 行）：

```c
recipNorm = invSqrt(s0 * s0 + s1 * s1 + s2 * s2 + s3 * s3);
s0 *= recipNorm;
s1 *= recipNorm;
s2 *= recipNorm;
s3 *= recipNorm;
```

> 为什么要归一化梯度？
> 
> 因为我们只关心梯度的**方向**，不关心其大小。
> 归一化后，修正步长完全由 `beta` 参数控制，确保稳定性。
> 这相当于把梯度下降变成了「固定步长的最速下降法」。

---

### 2.6 融合陀螺仪与梯度修正

Madgwick 的核心融合公式（第 130-133 行 / 第 207-210 行）：

```c
qDot1 -= beta * s0;
qDot2 -= beta * s1;
qDot3 -= beta * s2;
qDot4 -= beta * s3;
```

数学表达式：


$$
\dot{q}_{\text{final}} = \dot{q}_{\text{gyro}} - \beta \cdot \frac{\nabla f}{\|\nabla f\|}
$$


即：
- 陀螺仪提供动态的姿态变化率 $\dot{q}_{\text{gyro}}$
- 梯度下降提供修正项，把姿态往「满足重力/磁场约束」的方向拉
- `beta` 控制修正的力度

---

## 第三部分：完整 updateIMU 函数逐行解析

（[MadgwickAHRS.cpp 第 154-226 行](https://github.com/arduino-libraries/MadgwickAHRS/blob/master/src/MadgwickAHRS.cpp#L154-L226)）

`updateIMU` 是纯 IMU 版本（加速度计 + 陀螺仪，无磁力计），也是最常用的版本。

### 3.1 步骤 1：陀螺仪单位转换

```c
// Convert gyroscope degrees/sec to radians/sec（第 161-163 行）
gx *= 0.0174533f;
gy *= 0.0174533f;
gz *= 0.0174533f;
```

> 注意：Madgwick 库的输入是 **度/秒**，内部转换成 **弧度/秒** 再计算。
> 0.0174533 = π / 180

---

### 3.2 步骤 2：陀螺仪积分（四元数微分方程）

```c
// Rate of change of quaternion from gyroscope（第 166-169 行）
qDot1 = 0.5f * (-q1 * gx - q2 * gy - q3 * gz);
qDot2 = 0.5f * (q0 * gx + q2 * gz - q3 * gy);
qDot3 = 0.5f * (q0 * gy - q1 * gz + q3 * gx);
qDot4 = 0.5f * (q0 * gz + q1 * gy - q2 * gx);
```

**对应公式**（四元数运动学方程）：


$$
\dot{q} = \frac{1}{2} q \otimes \omega^b
$$


其中 $\omega^b = [0, g_x, g_y, g_z]$ 是 b 系下角速度的四元数表示。

展开后就是上面四行代码。这和 Mahony 滤波**完全相同**。

---

### 3.3 步骤 3：加速度计有效性判断

```c
// Compute feedback only if accelerometer measurement valid（第 172 行）
if(!((ax == 0.0f) && (ay == 0.0f) && (az == 0.0f))) {
    ...
}
```

防止加速度计全零（如未初始化）导致除零错误。

---

### 3.4 步骤 4：加速度计归一化

```c
// Normalise accelerometer measurement（第 175-178 行）
recipNorm = invSqrt(ax * ax + ay * ay + az * az);
ax *= recipNorm;
ay *= recipNorm;
az *= recipNorm;
```

梯度下降推导中假设加速度计测量值是单位向量，所以必须归一化。

这里用了快速逆平方根算法 `invSqrt`（第 232-241 行），比 `1.0f / sqrtf(x)` 快几倍。

---

### 3.5 步骤 5：预计算辅助变量

```c
// Auxiliary variables to avoid repeated arithmetic（第 181-193 行）
_2q0 = 2.0f * q0;
_2q1 = 2.0f * q1;
_2q2 = 2.0f * q2;
_2q3 = 2.0f * q3;
_4q0 = 4.0f * q0;
_4q1 = 4.0f * q1;
_4q2 = 4.0f * q2;
_8q1 = 8.0f * q1;
_8q2 = 8.0f * q2;
q0q0 = q0 * q0;
q1q1 = q1 * q1;
q2q2 = q2 * q2;
q3q3 = q3 * q3;
```

**工程优化思想**：把梯度公式中反复出现的公共因子提前算好。
例如 `_2q0` 会在 s0、s1、s2 中各用一次，如果不预计算就要算 3 次。

> 对比 Mahony：Mahony 的公式简单，不需要这么多预计算变量。
> 这也是 Madgwick 计算量更大的直观体现。

---

### 3.6 步骤 6：梯度下降修正量计算

```c
// Gradient decent algorithm corrective step（第 196-199 行）
s0 = _4q0 * q2q2 + _2q2 * ax + _4q0 * q1q1 - _2q1 * ay;
s1 = _4q1 * q3q3 - _2q3 * ax + 4.0f * q0q0 * q1 - _2q0 * ay - _4q1 + _8q1 * q1q1 + _8q1 * q2q2 + _4q1 * az;
s2 = 4.0f * q0q0 * q2 + _2q0 * ax + _4q2 * q3q3 - _2q3 * ay - _4q2 + _8q2 * q1q1 + _8q2 * q2q2 + _4q2 * az;
s3 = 4.0f * q1q1 * q3 - _2q1 * ax + 4.0f * q2q2 * q3 - _2q2 * ay;
```

**对应公式**：$\mathbf{s} = J_g^T \cdot f_g$（梯度方向）

这是整个算法最硬核的部分——把雅可比转置乘残差的矩阵运算，
完全展开成了标量运算，去掉了所有冗余计算。

> 🔍 **理解诀窍**
> 
> 不要尝试背这些公式！理解原理即可：
> 1. $J_g$ 是 3×4 雅可比矩阵
> 2. $f_g$ 是 3 维残差向量
> 3. $J_g^T \cdot f_g$ 得到 4 维梯度方向
> 
> 实际工程中直接用库就行，不需要手写展开。

---

### 3.7 步骤 7：梯度归一化

```c
// normalise step magnitude（第 200-204 行）
recipNorm = invSqrt(s0 * s0 + s1 * s1 + s2 * s2 + s3 * s3);
s0 *= recipNorm;
s1 *= recipNorm;
s2 *= recipNorm;
s3 *= recipNorm;
```

把梯度方向变成单位向量，确保修正步长只由 `beta` 决定。

---

### 3.8 步骤 8：应用梯度修正

```c
// Apply feedback step（第 207-210 行）
qDot1 -= beta * s0;
qDot2 -= beta * s1;
qDot3 -= beta * s2;
qDot4 -= beta * s3;
```

**核心融合公式**：


$$
\dot{q}_{\text{out}} = \dot{q}_{\text{gyro}} - \beta \cdot \frac{\nabla f}{\|\nabla f\|}
$$


减去梯度方向 = 往残差减小的方向走 = 让姿态更符合重力约束。

---

### 3.9 步骤 9：四元数积分 + 归一化

```c
// Integrate rate of change of quaternion to yield quaternion（第 214-217 行）
q0 += qDot1 * invSampleFreq;
q1 += qDot2 * invSampleFreq;
q2 += qDot3 * invSampleFreq;
q3 += qDot4 * invSampleFreq;

// Normalise quaternion（第 220-224 行）
recipNorm = invSqrt(q0 * q0 + q1 * q1 + q2 * q2 + q3 * q3);
q0 *= recipNorm;
q1 *= recipNorm;
q2 *= recipNorm;
q3 *= recipNorm;
```

一阶欧拉积分 + 归一化。和 Mahony 完全一样。

> ⚠️ **数值漂移问题**
> 
> 浮点运算有累积误差，每次积分后必须归一化，否则四元数的模会逐渐偏离 1，
> 导致姿态精度下降甚至发散。

---

## 第四部分：AHRS 版本（加磁力计）解析

`update()` 函数（第 49-149 行）是完整 AHRS 版本，比 `updateIMU()` 多了磁力计融合。

### 4.1 磁力计的作用

加速度计只能修正 Roll 和 Pitch（倾斜角），无法修正 Yaw（航向角）。
磁力计测量地磁场方向，提供绝对航向参考。

### 4.2 地磁场参考方向计算

```c
// Reference direction of Earth's magnetic field（第 111-116 行）
hx = mx * q0q0 - _2q0my * q3 + _2q0mz * q2 + mx * q1q1 + _2q1 * my * q2 + _2q1 * mz * q3 - mx * q2q2 - mx * q3q3;
hy = _2q0mx * q3 + my * q0q0 - _2q0mz * q1 + _2q1mx * q2 - my * q1q1 + my * q2q2 + _2q2 * mz * q3 - my * q3q3;
_2bx = sqrtf(hx * hx + hy * hy);
_2bz = -_2q0mx * q2 + _2q0my * q1 + mz * q0q0 + _2q1mx * q3 - mz * q1q1 + _2q2 * my * q3 - mz * q2q2 + mz * q3q3;
_4bx = 2.0f * _2bx;
_4bz = 2.0f * _2bz;
```

**原理**：
1. 把磁力计测量值 $\mathbf{m}^b$ 旋转到 n 系，得到 $\mathbf{m}^n$
2. 假设地磁水平分量指向北，垂直分量指向地
3. 计算参考磁场向量 $\mathbf{b}^n = [b_x, 0, b_z]^T$

`_2bx` 和 `_2bz` 就是 $2b_x$ 和 $2b_z$，作为后续梯度计算的参考值。

> 💡 **为什么不需要磁偏角？**
> 
> Madgwick 算法会自动将磁力计水平方向定义为 "北"，不需要输入当地磁偏角。
> 但这也意味着：**Madgwick 给出的航向是磁北，不是真北**，
> 需要真北的话要额外叠加磁偏角修正。

### 4.3 磁力计梯度修正

AHRS 版本的梯度 `s0~s3` 计算（第 119-122 行）比 IMU 版本长得多，
因为包含了**加速度计梯度 + 磁力计梯度**两部分之和。

数学本质：


$$
\nabla f_{\text{total}} = \nabla f_g + \nabla f_b
$$


两个传感器的修正方向叠加，共同约束姿态。

---

## 第五部分：快速逆平方根（invSqrt）

（[MadgwickAHRS.cpp 第 232-241 行](https://github.com/arduino-libraries/MadgwickAHRS/blob/master/src/MadgwickAHRS.cpp#L232-L241)）

```c
float Madgwick::invSqrt(float x) {
    float halfx = 0.5f * x;
    float y = x;
    long i = *(long*)&y;
    i = 0x5f3759df - (i >> 1);
    y = *(float*)&i;
    y = y * (1.5f - (halfx * y * y));
    y = y * (1.5f - (halfx * y * y));
    return y;
}
```

### 5.1 算法原理

这就是传说中的 **"0x5f3759df" 魔法数**，源自 Quake III 引擎。

原理是利用 IEEE 754 浮点数的二进制表示特性，
通过整数位移和魔法常数快速得到 $\frac{1}{\sqrt{x}}$ 的近似值，
然后用两次牛顿迭代把精度提高到 float 级别。

### 5.2 性能对比

| 方法 | 相对耗时 | 精度 |
|------|---------|------|
| `1.0f / sqrtf(x)` | 100% | 最高 |
| `invSqrt` (2次迭代) | ~30% | float 精度 |
| `invSqrt` (1次迭代) | ~15% | 约 3 位有效数字 |

> 🤔 **现代 MCU 还需要这个吗？**
> 
> Cortex-M4/M7 等带 FPU 的 MCU 有硬件 sqrt 指令，速度已经很快了。
> 但在 Cortex-M0/M3 等无 FPU 的芯片上，invSqrt 仍然能带来显著的性能提升。
> 
> **工程建议**：除非你在极度追求性能，否则直接用 `1.0f / sqrtf()` 更稳妥，
> 可读性和可移植性都更好。

---

## 第六部分：四元数转欧拉角

（[MadgwickAHRS.cpp 第 245-251 行](https://github.com/arduino-libraries/MadgwickAHRS/blob/master/src/MadgwickAHRS.cpp#L245-L251)）

```c
void Madgwick::computeAngles()
{
    roll = atan2f(q0*q1 + q2*q3, 0.5f - q1*q1 - q2*q2);
    pitch = asinf(-2.0f * (q1*q3 - q0*q2));
    yaw = atan2f(q1*q2 + q0*q3, 0.5f - q2*q2 - q3*q3);
    anglesComputed = 1;
}
```

**对应公式**（ZYX 内旋顺序，航向-俯仰-横滚）：


$$
\begin{cases}
\phi = \arctan2(2(q_0 q_1 + q_2 q_3), 1 - 2(q_1^2 + q_2^2)) \\
\theta = \arcsin(2(q_0 q_2 - q_1 q_3)) \\
\psi = \arctan2(2(q_0 q_3 + q_1 q_2), 1 - 2(q_2^2 + q_3^2))
\end{cases}
$$


> 📐 **万向节锁提醒**
> 
> 欧拉角表示在 pitch = ±90° 时会出现万向节锁。
> 四元数本身不会万向节锁，但转换成欧拉角输出时会遇到这个问题。
> 实际应用中尽量在四元数空间做运算，最后输出时再转欧拉角。

---

## 第七部分：Madgwick vs Mahony 深度对比

### 7.1 数学本质对比

| 维度 | Mahony | Madgwick |
|------|--------|----------|
| **核心思想** | 互补滤波 + 叉乘误差 | 梯度下降优化 |
| **误差定义** | $\mathbf{e} = \hat{\mathbf{v}} \times \mathbf{a}$（向量叉乘） | $\nabla f = J^T \cdot f$（梯度） |
| **修正方向** | 几何直观，直接指向旋转轴 | 优化视角，残差下降最快的方向 |
| **理论基础** | 控制论（PI 控制器） | 数值优化（梯度下降法） |

### 7.2 性能对比

| 特性 | Mahony | Madgwick |
|------|--------|----------|
| **计算量** | 小（约 50 次浮点运算） | 大（约 110 次浮点运算） |
| **收敛速度** | 快 | 相当 |
| **静态精度** | 高 | 相当 |
| **动态精度** | 良好 | 良好 |
| **参数数量** | 2 个（Kp, Ki） | 1 个（beta） |
| **零偏估计** | 有（积分项） | 无（IMU 版本） |
| **代码复杂度** | 低 | 中 |

### 7.3 怎么选？

**选 Mahony 的场景**：
- MCU 算力有限（如 Cortex-M0/M3）
- 需要在线估计陀螺仪零偏
- 追求代码简洁易维护
- 学习姿态解算的入门阶段

**选 Madgwick 的场景**：
- 理论研究，理解梯度下降在姿态解算中的应用
- 需要统一的优化框架（方便扩展其他传感器）
- 论文引用需要（Madgwick 的论文引用量更高）

> 💡 **实际工程建议**
> 
> 绝大多数飞控/机器人项目中，Mahony 和 Madgwick 的实际表现差距极小，
> 远小于传感器本身的噪声水平。**把时间花在传感器校准和机械减震上，
> 收益比纠结选哪个算法大得多**。
> 
> 如果只能选一个入门，**推荐先学 Mahony**，几何直观更强，更容易建立直觉。
> 掌握 Mahony 后再看 Madgwick，会发现就是换了一种误差计算方式而已。

---

## 第八部分：参数调优指南

### 8.1 beta 参数怎么调？

**默认值**：`beta = 0.1`（对应约 5.7°/s 的陀螺漂移假设）

**调节方向**：

| 现象 | 调整方向 | 原因 |
|------|---------|------|
| 静态时水平角度漂移大 | 增大 beta | 加大加速度计修正力度 |
| 快速运动时角度 "歪了" | 减小 beta | 减小加速度计权重，更信任陀螺 |
| 静止时有高频抖动 | 减小 beta | 修正太猛，把噪声也放大了 |
| 开机后很久才能稳定 | 增大 beta | 加快收敛速度 |

**推荐调试步骤**：
1. 从默认值 0.1 开始
2. 拿在手里快速晃动，看姿态是否跟着走，有没有 "滞后" 或 "飘逸"
3. 静止放置 1 分钟，看角度是否漂移
4. 动态和静态是 trade-off，找到平衡点

### 8.2 采样率的影响

Madgwick 算法对采样率不敏感。论文显示：
- 10Hz 采样仍能工作
- 50Hz 以上精度提升很小
- 512Hz 是原始论文的测试条件

**实际建议**：
- 普通平衡车/机器人：50~100Hz 足够
- 飞控/高速运动：200~500Hz
- 不需要追求 1kHz 以上，收益微乎其微

---

## 代码与数学符号对照表

| 代码符号 | 数学符号 | 含义 |
|---------|---------|------|
| `beta` | $\beta$ | 梯度下降增益（比例修正系数） |
| `q0, q1, q2, q3` | $q_0, q_1, q_2, q_3$ | 姿态四元数 |
| `gx, gy, gz` | $\omega_x, \omega_y, \omega_z$ | 陀螺仪角速度（rad/s） |
| `ax, ay, az` | $a_x, a_y, a_z$ | 加速度计测量值（归一化后） |
| `mx, my, mz` | $m_x, m_y, m_z$ | 磁力计测量值（归一化后） |
| `s0, s1, s2, s3` | $\mathbf{s} = \nabla f / \|\nabla f\|$ | 归一化梯度方向 |
| `_2q0, _4q0` 等 | 预计算因子 | 优化用的中间变量 |
| `invSampleFreq` | $\Delta t$ | 采样周期 |

---

## 总结：Madgwick 滤波的核心思想

1. **姿态表示**：四元数（无奇点、计算方便）
2. **动态更新**：陀螺仪积分 + 四元数运动学方程
3. **绝对参考**：加速度计测重力、磁力计测地磁场
4. **误差修正**：梯度下降法最小化测量值与参考值的偏差
5. **参数简洁**：只有一个 beta 参数控制融合权重

**一句话概括**：
> "陀螺仪负责快速跟踪运动，梯度下降负责把姿态往重力/磁场方向拉，
> 两者一结合，就得到了既快又准的姿态估计。"

---

## 参考资料

### 开源代码

1. **Arduino MadgwickAHRS（本文分析蓝本）**：
   - 仓库：https://github.com/arduino-libraries/MadgwickAHRS
   - 特点：官方标准移植，代码规范，注释清晰

2. **x-io 官方 Fusion 库（最新版本）**：
   - 仓库：https://github.com/xioTechnologies/Fusion
   - 特点：Madgwick 博士亲自维护的最新版本，API 更完善

3. **Mahony 滤波（对比学习）**：
   - 仓库：https://github.com/wild-civil/STM32_BMI088_MahonyAHRS

### 理论资料

1. **Madgwick 博士论文**：
   - 标题：An efficient orientation filter for inertial and inertial/magnetic sensor arrays
   - 下载：https://x-io.co.uk/open-source-imu-and-ahrs-algorithms/

2. **梯度下降法入门**：
   - 理解梯度下降的几何意义，对理解 Madgwick 帮助极大

3. **四元数运动学**：
   - 推荐阅读：《捷联惯导算法与组合导航原理》（严龚敏）

---


```ad-flex
title: ## 💡 进阶思考与工程坑点（备忘）
collapse: close

### 1. 为什么在 loop 里敢“只迭代 1 次”？
* **核心假设**：算法假设**“系统的采样频率远高于载体的运动速度”**。
* **原理**：在 100Hz 以上的高频采样下，前后两帧之间姿态变化极其微小。上一时刻的最优解 $q_{k-1}$ 已经处于当前极小值谷底附近了。因此，每一帧只需要沿着梯度方向“迈一小步”（迭代 1 次），就足以实时跟踪上载体的姿态，从而极大地节省了 MCU 的算力。

### 2. 地磁融合的抗干扰妙招（为什么令 $b_y = 0$？）
* **原理**：算法在计算地理坐标系下的地磁向量时，通过 `_2bx = sqrtf(hx*hx + hy*hy);` 强行将 Y 轴分量设为 0。
* **本质**：这是一种聪明的**解耦设计**。它剥离了地磁场中可能污染横滚和俯仰（Roll/Pitch）的分量，让磁力计**只负责约束航向角（Yaw）**，而把 Roll/Pitch 的修正权完全留给更可靠的加速度计。这让算法在面对环境磁干扰时具备更强的工程鲁棒性。

### 3. Arduino 开源库的遗憾：缺失零偏估计
* **注意**：原作者 Madgwick 的论文中是有陀螺仪在线零偏估计（积分项 $\zeta$）的。但 Arduino 官方的 `MadgwickAHRS` 库为了极致精简，**把零偏追踪代码删掉了**。
* **后果**：如果传感器芯片随温度发生零偏漂移，该简易库无法在线消除漂移，静态下姿态可能会出现角度死区或缓慢漂移。复杂工程项目建议使用标准 `Fusion` 库。
```
