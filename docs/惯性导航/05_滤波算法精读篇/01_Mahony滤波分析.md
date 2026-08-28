
# Mahony 滤波（Mahony Complementary Filter）分析

---

## 先明确坐标系约定（重要！）

使用牛小骥老师团队的 NED+FRD 约定：

| 坐标系 | 原点 | X 轴 | Y 轴 | Z 轴 |
|--------|------|------|------|------|
| **导航系 (n-frame, NED)** | IMU 初始位置 | 指向北 (North) | 指向东 (East) | 指向地 (Down) |
| **载体系 (b-frame, FRD)** | IMU 中心 | 指向前 (Front) | 指向右 (Right) | 指向地 (Down) |

**四元数约定**：用 $q_b^n$ 表示“把载体系向量变换到导航系”，即：


$$
\mathbf{v}^n = q_b^n \otimes \mathbf{v}^b \otimes (q_b^n)^*
$$


---

## 第一部分：定义和初始化

### 1.1  宏定义（第 23-25 行）

代码里的定义（[MahonyAHRS.c 第 23-25 行](https://github.com/wild-civil/STM32_BMI088_MahonyAHRS/blob/main/Core/Src/MahonyAHRS.c#L23-L25)）：

```c
#define sampleFreq	1000.0f		// 采样频率
#define twoKpDef	(2.0f * 0.5f)	// 2 * 比例增益
#define twoKiDef	(2.0f * 0.0f)	// 2 * 积分增益
```
&nbsp;
>**补充：half 因子的优化技巧**
>**为什么要乘以 2？**
>- 后面计算重力向量时用的是 `halfvx`（完整重力向量的一半）
>- 如果误差是 `halfex = (ay*halfvz - az*halfvy)`，那么完整误差是 `2*halfex`
>- 但如果 `twoKp = 2*Kp`，那么 `twoKp * halfex = (2*Kp)*(e/2) = Kp*e`，结果一样
>- **这是代码优化**，少算一次乘法，老 MCU 上有点用，现在意义不大

---


### 1.2 全局变量（第 30-33 行）
代码里的定义（[MahonyAHRS.c 第 30-33 行](https://github.com/wild-civil/STM32_BMI088_MahonyAHRS/blob/main/Core/Src/MahonyAHRS.c#L30-L33)）：
```c
volatile float twoKp = twoKpDef;           // 比例增益 (可动态调整)
volatile float twoKi = twoKiDef;           // 积分增益 (可动态调整)
volatile float integralFBx = 0.0f;        // 积分反馈 X
volatile float integralFBy = 0.0f;        // 积分反馈 Y
volatile float integralFBz = 0.0f;        // 积分反馈 Z
```

**volatile 的作用**：

- 防止编译器优化
- 允许在中断或主循环外修改这些值

---


## 第二部分：快速逆平方根 `invSqrt()`

### 2.1 代码（函数声明在第 38 行）
代码里该函数的的定义（[MahonyAHRS.c 第 220-228 行](https://github.com/wild-civil/STM32_BMI088_MahonyAHRS/blob/main/Core/Src/MahonyAHRS.c#L220-L228)）：
```c
float invSqrt(float x) {
    float halfx = 0.5f * x;
    float y = x;
    long i = *(long*)&y;               // 把float的位模式当成long
    i = 0x5f3759df - (i>>1);           // 快速近似
    y = *(float*)&i;                   // 把long的位模式当成float
    y = y * (1.5f - (halfx * y * y));  // 牛顿迭代一次
    return y;
}
```

### 2.2 数学原理

**目的**：计算 $\dfrac{1}{\sqrt{x}}$

**传统方法**：

```c
y = 1.0f / sqrtf(x);  // 慢，需要硬件支持
```

**invSqrt 的神奇之处**：


- 初始近似（位魔术）：
  

$$
i \approx \frac{1}{\sqrt{x}} \quad \text{(通过整数运算)}
$$


  其中 $i = \text{0x5f3759df} - (i_{\text{orig}} \gg 1)$，$i_{\text{orig}}$ 是 $x$ 的 IEEE 754 位模式。

- 牛顿迭代一次：
  

$$
y_{\text{new}} = y \cdot \left (1.5 - \frac{x \cdot y^2}{2}\right)
$$


  代码中 `halfx * y * y` 即 $\frac{x}{2} \cdot y^2$，`1.5f - ...` 即 $1.5 - \frac{x y^2}{2}$，相乘得到 $y_{\text{new}}$。

**补充推导**：  
设 $f (y) = \frac{1}{y^2} - x = 0$，牛顿迭代 $y_{n+1} = y_n - \frac{f (y_n)}{f' (y_n)} = y_n - \frac{1/y_n^2 - x}{-2/y_n^3} = y_n + \frac{y_n}{2} - \frac{x y_n^3}{2} = y_n (1.5 - \frac{x y_n^2}{2})$。


### 2.3 直观理解

**类比**：就像用"猜数字"的方法

1. 先猜一个大概的值
2. 验证并微调（牛顿迭代）
3. 几次后就非常准确了

**精度**：单次牛顿迭代后精度 ~0.001%，足够工程使用！


---

## 第三部分：`MahonyAHRSupdate()` 主函数

### 3.1 函数签名（第 46 行）
代码里该函数的的定义（[MahonyAHRS.c 第 46 行](https://github.com/wild-civil/STM32_BMI088_MahonyAHRS/blob/main/Core/Src/MahonyAHRS.c#L46)）：
```c
void MahonyAHRSupdate(float q[4], float gx, float gy, float gz, 
                     float ax, float ay, float az, 
                     float mx, float my, float mz)
```

**参数说明**：

| 参数       | 类型   | 单位  | 说明                 |
| ---------- | ------ | ----- | -------------------- |
| `q[4]`     | in/out | -     | 四元数 [q0, q1, q2, q3] |
| `gx,gy,gz` | input  | rad/s | 陀螺仪角速度         |
| `ax,ay,az` | input  | 任意  | 加速度计             |
| `mx,my,mz` | input  | 任意  | 磁力计（可为 0）      |

---

### 3.2 步骤 1：磁力计有效性检查（第 55-58 行）

```c
// Use IMU algorithm if magnetometer measurement invalid
if((mx == 0.0f) && (my == 0.0f) && (mz == 0.0f)) {
    MahonyAHRSupdateIMU(q, gx, gy, gz, ax, ay, az);
    return;
}
```

**逻辑**：

- 如果磁力计数据全为 0，说明没有磁力计或数据无效
- 就调用**仅 IMU 版本**的函数（不用磁力计修正航向）
- 这样姿态解算照样工作，只是 Yaw 会漂移

---

### 3.3 步骤 2：加速度计有效性检查（第 61 行）

```c
// Compute feedback only if accelerometer measurement valid
if(!((ax == 0.0f) && (ay == 0.0f) && (az == 0.0f))) {
    // ... 计算 ...
}
```

**为什么要检查**：

- 避免除以 0（归一化时）
- 避免 NaN 出现
- 加速度计饱和或故障时跳过修正

---

### 3.4 步骤 3：归一化（第 64-67 行）

```c
// Normalise accelerometer measurement
recipNorm = invSqrt(ax * ax + ay * ay + az * az);
ax *= recipNorm;
ay *= recipNorm;
az *= recipNorm;
```

**公式**：


$$
\mathbf{a}_{\text{norm}} = \frac{\mathbf{a}}{\|\mathbf{a}\|} = \frac{\mathbf{a}}{\sqrt{a_x^2 + a_y^2 + a_z^2}}
$$


**为什么归一化？**

- 只需要**方向**，不需要**大小**
- 静态时加速度应该是重力向量（长度=1g）
- 归一化后不管 IMU 怎么放，方向都是一致的

---

### 3.5 步骤 4：辅助变量（第 75-85 行）

```c
// Auxiliary variables to avoid repeated arithmetic
q0q0 = q[0] * q[0];
q0q1 = q[0] * q[1];
q0q2 = q[0] * q[2];
q0q3 = q[0] * q[3];
q1q1 = q[1] * q[1];
q1q2 = q[1] * q[2];
q1q3 = q[1] * q[3];
q2q2 = q[2] * q[2];
q2q3 = q[2] * q[3];
q3q3 = q[3] * q[3];
```

**作用**：

- 预计算四元数的乘积
- 后面会多次用到这些值
- **减少重复乘法**，提升性能

---

### 3.6 步骤 5：参考磁场方向（第 87-91 行）

```c
// Reference direction of Earth's magnetic field
hx = 2.0f * (mx * (0.5f - q2q2 - q3q3) + my * (q1q2 - q0q3) + mz * (q1q3 + q0q2));
hy = 2.0f * (mx * (q1q2 + q0q3) + my * (0.5f - q1q1 - q3q3) + mz * (q2q3 - q0q1));
bx = sqrt(hx * hx + hy * hy);
bz = 2.0f * (mx * (q1q3 - q0q2) + my * (q2q3 + q0q1) + mz * (0.5f - q1q1 - q2q2));
```

这段代码把**载体系**磁力计测量值 $\mathbf{m}^b = [m_x, m_y, m_z]^T$ 转到**导航系** $\mathbf{m}^n$：


$$
\mathbf{m}^n = \mathbf{q} \otimes \mathbf{m}^b \otimes \mathbf{q}^*
$$


其中乘法按四元数乘法规则展开。记方向余弦矩阵 $\mathbf{C}_b^n (\mathbf{q})$ 的元素为：


$$
\mathbf{C}_b^n = 
\begin{bmatrix}
q_0^2+q_1^2-q_2^2-q_3^2 & 2 (q_1q_2 - q_0q_3) & 2 (q_1q_3 + q_0q_2) \\
2 (q_1q_2 + q_0q_3) & q_0^2 - q_1^2 + q_2^2 - q_3^2 & 2 (q_2q_3 - q_0q_1) \\
2 (q_1q_3 - q_0q_2) & 2 (q_2q_3 + q_0q_1) & q_0^2 - q_1^2 - q_2^2 + q_3^2
\end{bmatrix}
$$


则 $\mathbf{m}^n = \mathbf{C}_b^n \cdot \mathbf{m}^b$。  
计算 $h_x, h_y, h_z$ 为：


$$
\begin{cases}
h_x = m_x (1-2q_2^2-2q_3^2) + m_y (2q_1q_2-2q_0q_3) + m_z (2q_1q_3+2q_0q_2) \\
h_y = m_x (2q_1q_2+2q_0q_3) + m_y (1-2q_1^2-2q_3^2) + m_z (2q_2q_3-2q_0q_1) \\
h_z = m_x (2q_1q_3-2q_0q_2) + m_y (2q_2q_3+2q_0q_1) + m_z (1-2q_1^2-2q_2^2)
\end{cases}
$$


代码中的 `hx`, `hy` 就是上面的表达式。Mahony 原文中的标准公式定义为：


$$
h_x = 2 (q_1q_3+q_0q_2) m_x + 2 (q_1q_2 - q_0q_3) m_y + (1-2q_2^2-2q_3^2) m_z
$$


这里代码与原式一致，只是顺序不同：


$$
hx = 2 \cdot [ m_x (0.5 - q_2^2 - q_3^2) + m_y (q_1q_2 - q_0q_3) + m_z (q_1q_3 + q_0q_2) ]
$$


>验证：$0.5 - q_2^2 - q_3^2 = \frac{1}{2}(1 - 2q_2^2 - 2q_3^2)$，乘外面的 2 得到 $1 - 2q_2^2 - 2q_3^2$，与方向余弦矩阵的第一行第一列一致（矩阵中第一行第一列为 $q_0^2+q_1^2-q_2^2-q_3^2 = 1-2q_2^2-2q_3^2$）。完美对应。

得到 $h_x, h_y$ 后，忽略磁倾角（因为用作修正航向，所以仅保留水平分量）：


$$
b_x = \sqrt{h_x^2 + h_y^2}, \quad b_z = h_z
$$


代码中 `bz` 是通过另一个表达式计算的，实际上就是 $h_z$：


$$
bz = 2 \cdot [ m_x (q_1q_3 - q_0q_2) + m_y (q_2q_3 + q_0q_1) + m_z (0.5 - q_1^2 - q_2^2) ]
$$


乘以外面的 2 得到 $h_z = 2 (q_1q_3 - q_0q_2) m_x + 2 (q_2q_3+q_0q_1) m_y + (1-2q_1^2-2q_2^2) m_z$，与方向余弦矩阵第三行一致。

> `bx, bz` 是地磁场在导航系的估计方向，后面用这个来修正航向

---

### 3.7 步骤 6：估计重力和磁场方向（第 93-99 行）

```c
// Estimated direction of gravity and magnetic field
halfvx = q1q3 - q0q2;              // 重力向量 X 的一半
halfvy = q0q1 + q2q3;              // 重力向量 Y 的一半
halfvz = q0q0 - 0.5f + q3q3;       // 重力向量 Z 的一半

halfwx = bx * (0.5f - q2q2 - q3q3) + bz * (q1q3 - q0q2);
halfwy = bx * (q1q2 - q0q3) + bz * (q0q1 + q2q3);
halfwz = bx * (q0q2 + q1q3) + bz * (0.5f - q1q1 - q2q2);
```

**重力向量估计**  $\hat{\mathbf{g}}^b$ 的推导

在 NED 导航系下，重力向量是 $\mathbf{g}^n = [0, 0, 1]^T$（指向地）。

用当前姿态 $\mathbf{q}_b^n$ 把重力从**导航系**转回**载体系**：


$$
\mathbf{\hat{g}}^b = \begin{bmatrix} v_x \\ v_y \\ v_z \end{bmatrix} = \mathbf{C}_n^b \begin{bmatrix} 0 \\ 0 \\ 1 \end{bmatrix} = (\mathbf{q}_b^n)^* \otimes \begin{bmatrix}0 \\ 0 \\ 1\end{bmatrix} \otimes \mathbf{q}_b^n
$$


展开后就是：


$$
\hat{\mathbf{g}}^b = \begin{bmatrix} 2(q_1 q_3 - q_0 q_2) \\ 2(q_0 q_1 + q_2 q_3) \\ q_0^2 - q_1^2 - q_2^2 + q_3^2 \end{bmatrix} = 2 \begin{bmatrix} \text{halfvx} \\ \text{halfvy} \\ \text{halfvz} \end{bmatrix}
$$


**磁场向量估计** $\hat{\mathbf{m}}^b$ 的推导：

类似的，把导航系的水平磁场 $[b_x, 0, b_z]$ 转回载体系。


$$
\hat{\mathbf{m}}^b = \begin{bmatrix} w_x \\ w_y \\ w_z \end{bmatrix} = \mathbf{C}_n^b \begin{bmatrix} b_x \\ 0 \\ b_z \end{bmatrix} = \begin{bmatrix}
b_x(1 - 2q_2^2 - 2q_3^2) + b_z(2(q_1q_3 - q_0q_2)) \\
b_x(2(q_1q_2 - q_0q_3)) + b_z(2(q_2q_3 + q_0q_1)) \\
b_x(2(q_1q_3 + q_0q_2)) + b_z(1 - 2(q_1^2 + q_2^2))
\end{bmatrix} = 2 \begin{bmatrix} \text{halfwx} \\ \text{halfwy} \\ \text{halfwz} \end{bmatrix}
$$


#### 3.7.1 $\hat{\mathbf{g}}^b$ 是什么？
**$\mathbf{\hat{g}}^b$ 是一个估计值，是“根据当前姿态估计值，预测加速度计应该测到的重力向量”。**

更精确地说：
- 在导航系（n 系）中，重力向量是已知且固定的：$\mathbf{g}^n = \begin{bmatrix}0 & 0 & g\end{bmatrix}^T$（NED 下指向地，大小为 g）。
- 根据陀螺的输出得到一个**当前估计的姿态**（用四元数 $\mathbf{q}_b^n$ 或旋转矩阵 $\mathbf{C}_n^b$ 表示）。
- 利用这个姿态，把导航系的重力向量**变换到载体系（b 系）**，就得到**预测的重力向量在载体系中的分量**。
- 这个预测值就是 $\mathbf{\hat{g}}^b$ 或 $\begin{bmatrix}v_x & v_y & v_z\end{bmatrix}^T$

#### 3.7.2为什么 $\hat{\mathbf{g}}^b$ 可以用来修正姿态？
- 加速度计测量值：$\mathbf{a}^b = [a_x, a_y, a_z]^T$（加速度计直接输出，可能含运动加速度和噪声）
- 估计值（预测值）：$\hat{\mathbf{g}}^b = [\hat{g}_x, \hat{g}_y, \hat{g}_z]^T$，由姿态和已知重力计算得到
**当姿态正确时**（且 IMU 只受重力作用，无外加加速度），应该有：$\mathbf{a}^b \approx \hat{\mathbf{g}}^b$ 。如果两者不一致，说明姿态估计有误差。误差的大小和方向通过**叉积**（Mahony）或**梯度下降**（Madgwick）算出，然后用于修正陀螺积分，让姿态逐渐收敛到正确值。

##### 类比：
想象闭着眼睛（不知道姿态），但手里拿着一个加速度计。你知道重力永远竖直向下（在导航系中固定）。如果你猜了一个姿态（比如认为自己正坐着），那么根据这个猜测，加速度计应该读到某个方向的 1g。这个“应该读到”的值就是预测值。然后你睁开眼看看加速度计**实际**读数，两者不一致，就知道自己猜错了姿态——误差多大、往哪转，就能修正。

##### 总结：
用当前姿态，把已知的重力从导航系投影到载体系，得到一个**估计值** $\hat{\mathbf{g}}^b$，然后与加速度计测量值比较，修正姿态。

---

### 3.8 步骤 7：计算误差（叉积！）（第 101-104 行）

```c
// Error is sum of cross product between estimated and measured direction
halfex = (ay * halfvz - az * halfvy) + (my * halfwz - mz * halfwy);
halfey = (az * halfvx - ax * halfvz) + (mz * halfwx - mx * halfwz);
halfez = (ax * halfvy - ay * halfvx) + (mx * halfwy - my * halfwx);
```

#### 3.8.1 代码与公式映射

<font color="#ff0000">!!! 这里是 mahony 算法的核心!!! </font> `

**公式**：


$$
\mathbf{e} = \underbrace{\mathbf{a}_{\text{meas}} \times \hat{\mathbf{g}}}_{\text{加速度误差}} + \underbrace{\mathbf{m}_{\text{meas}} \times \hat{\mathbf{m}}}_{\text{磁场误差}}
$$


因为代码里的 `halfv` 和 `halfw` 是真实值的一半，所以算出来的误差 `halfe` 也是真实物理误差的一半：


$$
\text{halfex} = \frac{e_x}{2} = (a_y \cdot \text{halfv}_z - a_z \cdot \text{halfv}_y) + (m_y \cdot \text{halfw}_z - m_z \cdot \text{halfw}_y)
$$


**叉积的物理意义**：

| 叉积结果 | 含义                                 |
| -------- | ------------------------------------ |
| 方向     | "绕哪个轴旋转"能让测量值和估计值对齐 |
| 大小     | 误差的大小（与 sin (夹角) 成正比）    |

**举例理解**：

- 假设 IMU 歪了，测量的重力方向和估计的不一致
- 叉积会表明"需要绕哪个轴转多少度"才能对齐

#### 3.8.2 补充：数学原理与推导

通过计算“测量向量”与“估计向量”的叉积（Cross Product）来得到姿态误差。


$$
\mathbf{e} = (\mathbf{a}_{\text{meas}} \times \hat{\mathbf{g}}) + (\mathbf{m}_{\text{meas}} \times \hat{\mathbf{m}})
$$


叉积的矩阵行列式计算公式为：


$$
\mathbf{A} \times \mathbf{B} = \begin{bmatrix} \mathbf{i} & \mathbf{j} & \mathbf{k} \\ A_x & A_y & A_z \\ B_x & B_y & B_z \end{bmatrix} = \begin{bmatrix} A_y B_z - A_z B_y \\ A_z B_x - A_x B_z \\ A_x B_y - A_y B_x \end{bmatrix}
$$


代入加速度误差 $\mathbf{e}_a = \mathbf{a}_{\text{meas}} \times \hat{\mathbf{g}}$：


$$
\mathbf{e}_a = \begin{bmatrix} a_y v_z - a_z v_y \\ a_z v_x - a_x v_z \\ a_x v_y - a_y v_x \end{bmatrix}
$$


$$
\mathbf{e}_a = \begin{bmatrix} a_y \hat{g}_z - a_z \hat{g}_y \\ a_z \hat{g}_x - a_x \hat{g}_z \\ a_x \hat{g}_y - a_y \hat{g}_x \end{bmatrix}
= 2 \begin{bmatrix} a_y \cdot \text{halfvz} - a_z \cdot \text{halfvy} \\ a_z \cdot \text{halfvx} - a_x \cdot \text{halfvz} \\ a_x \cdot \text{halfvy} - a_y \cdot \text{halfvx} \end{bmatrix}
$$


同理代入可得磁力计误差 $\mathbf{e}_m = \mathbf{m}_{\text{meas}} \times \hat{\mathbf{m}}$。

---

### 3.9 步骤 8：PI 控制器（第 106-124 行）

```c
// Compute and apply integral feedback if enabled
if(twoKi > 0.0f) {
    // 积分项： 积分 ＝ 过去累加 ＋ 误差 * dt （累积过去的误差）
    // 这里的 (1.0f / sampleFreq) 就是 dt
    integralFBx += twoKi * halfex * (1.0f / sampleFreq);
    integralFBy += twoKi * halfey * (1.0f / sampleFreq);
    integralFBz += twoKi * halfez * (1.0f / sampleFreq);
    
    // 应用 I 项补偿到角速度
    gx += integralFBx;
    gy += integralFBy;
    gz += integralFBz;
}
else {
    // 清零，防止积分饱和
    integralFBx = 0.0f;
    integralFBy = 0.0f;
    integralFBz = 0.0f;
}

// 应用 P 项补偿到角速度
gx += twoKp * halfex;
gy += twoKp * halfey;
gz += twoKp * halfez;
```

`gx, gy, gz` 作为传入的参数，在函数内部被当作局部变量直接进行了**原地累加修改（In-place update）**：

- **刚进函数时**：`gx, gy, gz` 是陀螺仪直接输出的**原始角速度**（含零偏、有噪声）。
**到步骤 8 时**：

```c
// 1. 先加上 I（积分）项补偿
gx += integralFBx; 
// 2. 再加上 P（比例）项补偿
gx += twoKp * halfex; 
```

执行完这两行后，原始的 `gx` 就已经被**覆盖**了，此时变量 `gx` 里存的已经是**修正后的角速度** $\boldsymbol{\omega}_{\text{cor}}$。


#### 3.9.1 代码与公式映射

Mahony 核心思想是用类似回环控制的原理，把误差通过 PI 控制器补偿到陀螺仪测得的角速度 $\boldsymbol{\omega} = [g_x, g_y, g_z]^T$ 上：


$$
\boldsymbol{\omega}_{\text{cor}} = \boldsymbol{\omega} + \left( K_p \cdot \mathbf{e} + K_i \int \mathbf{e} \, dt \right)
$$


上式括号内的部分即为角速度误差，对于连续域 PI 控制器：


$$
\delta\omega = K_p \cdot \mathbf{e} + K_i \int_0^t \mathbf{e}\, d\tau
$$


离散化（一阶向后差分）：


$$
\delta\omega_k = K_p \mathbf{e}_k + K_i \sum_{j=0}^{k} \mathbf{e}_j \Delta t
$$


因为代码里的误差是 `halfex` ($=\frac{1}{2}\mathbf{e}$)，而宏定义里给定的参数是 `twoKp` ($=2K_p$) 和 `twoKi` ($=2K_i$)。做个简单的代数乘法：


$$
\text{twoKp} \times \text{halfex} = (2K_p) \times \left(\frac{e_x}{2}\right) = K_p \cdot e_x
$$


积分项同理。所以代码与标准公式完全等价。


---


**P（比例）项**：


$$
\delta\omega_P = K_p \cdot \mathbf{e}
$$


- "现在错了多少，就改多少"
- 误差大 → 修正力度大
- 响应快，但会有稳态误差

**I（积分）项**：


$$
\delta\omega_I = K_i \int \mathbf{e} \cdot dt
$$


- "过去一直在错，累积起来修正"
- 消除陀螺仪零偏导致的漂移
- 但可能过度修正导致震荡

**为什么要除以 sampleFreq？**

离散化时：$\int e \cdot dt \approx e \cdot \Delta t = \dfrac{e}{f_{\text{sample}}}$


---

### 3.10 步骤 9：积分四元数变化率（第 127-137 行）

```c
// Integrate rate of change of quaternion
// 代码临时 让修正后的角速度 gx = gx * 0.5 * dt
gx *= (0.5f * (1.0f / sampleFreq));  // 预处理：dt/2
gy *= (0.5f * (1.0f / sampleFreq));
gz *= (0.5f * (1.0f / sampleFreq));

qa = q[0];
qb = q[1];
qc = q[2];

// q0 = q0 + (-q1*gx - q2*gy - q3*gz)
q[0] += (-qb * gx - qc * gy - q[3] * gz);
// q1 = q1 + (q0*gx + q2*gz - q3*gy)
q[1] += (qa * gx + qc * gz - q[3] * gy);
// q2 = q2 + (q0*gy - q1*gz + q3*gx)
q[2] += (qa * gy - qb * gz + q[3] * gx);
// q3 = q3 + (q0*gz + q1*gy - q2*gx)
q[3] += (qa * gz + qb * gy - qc * gx);
```

**核心公式（四元数运动学）**：


$$
\dot{\mathbf{q}} = \frac{1}{2} \mathbf{q} \otimes \boldsymbol{\Omega} = \frac{1}{2} \begin{bmatrix} q_0 \\ q_1 \\ q_2 \\ q_3 \end{bmatrix} \otimes \begin{bmatrix} 0 \\ g_x \\ g_y \\ g_z \end{bmatrix}
$$


>我发现有的代码写的是 $g_x$ 有的写的是 $\omega_x$，这个并不影响，一定要分清楚这里的 g 不是指加速度，而是陀螺 (gyroscope)的意思，所以两者都表示角速度，只是代码符号与数学符号混用造成的结果 。$\boldsymbol{\Omega}$ 也可以表示为 $\boldsymbol{\Omega} = \begin{bmatrix} 0, \ \omega_x, \ \omega_y, \ \omega_z \end{bmatrix}^T$ ，具体代码具体分析吧


**离散化**：

利用一阶欧拉积分更新下一时刻的四元数：


$$
\mathbf{q}_b^n(t+\Delta t) \approx \mathbf{q}_b^n(t) + \dot{\mathbf{q}}_b^n(t) \cdot \Delta t = \mathbf{q}_b^n(t) + \frac{1}{2} \mathbf{q}_b^n(t) \otimes \boldsymbol{\Omega}(t)
$$


根据四元数乘法定义展开 $\dot{\mathbf{q}} = [\dot{q}_0, \dot{q}_1, \dot{q}_2, \dot{q}_3]^T$：


$$
\begin{align}
\dot{q}_0 &= \frac{1}{2} (-q_1 g_x - q_2 g_y - q_3 g_z)\\
\dot{q}_1 &= \frac{1}{2} ( q_0 g_x + q_2 g_z - q_3 g_y)\\
\dot{q}_2 &= \frac{1}{2} ( q_0 g_y - q_1 g_z + q_3 g_x)\\
\dot{q}_3 &= \frac{1}{2} ( q_0 g_z + q_1 g_y - q_2 g_x)
\end{align}
$$


陀螺输出的角速度乘 $\Delta t$ 得到的是叫增量，展开上述四元数乘法：


$$
\begin{bmatrix} q_0 \\ q_1 \\ q_2 \\ q_3 \end{bmatrix}_{t+\Delta t}
= \begin{bmatrix} q_0 \\ q_1 \\ q_2 \\ q_3 \end{bmatrix}_t
+ \frac{1}{2} \begin{bmatrix}
-q_1 \Delta\theta_x - q_2 \Delta\theta_y - q_3 \Delta\theta_z \\
 q_0 \Delta\theta_x + q_2 \Delta\theta_z - q_3 \Delta\theta_y \\
 q_0 \Delta\theta_y - q_1 \Delta\theta_z + q_3 \Delta\theta_x \\
 q_0 \Delta\theta_z + q_1 \Delta\theta_y - q_2 \Delta\theta_x
\end{bmatrix}
$$


代码中的 `gx, gy, gz` 已经乘了 `0.5f * dt`，即 $\frac{\Delta t}{2}$，因此 `gx = Δθ_x/2`，`gy = Δθ_y/2`，`gz = Δθ_z/2`。然后增量部分直接使用这些值，无需再乘 1/2。

```c
// 代码临时令 gx = gx * 0.5 * dt
gx *= (0.5f * (1.0f / sampleFreq)); 
gy *= (0.5f * (1.0f / sampleFreq));
gz *= (0.5f * (1.0f / sampleFreq));
```

这样一来，上面的整个 $\frac{1}{2}$ 和 $\Delta t$ 就都被吸收到 `gx, gy, gz` 中去了，小巧思

---

### 3.11 步骤 10：归一化四元数（第 139-144 行）

```c
// Normalise quaternion
recipNorm = invSqrt(q[0] * q[0] + q[1] * q[1] + q[2] * q[2] + q[3] * q[3]);
q[0] *= recipNorm;
q[1] *= recipNorm;
q[2] *= recipNorm;
q[3] *= recipNorm;
```

**公式**：


$$
\mathbf{q}_{\text{norm}} = \frac{\mathbf{q}}{\|\mathbf{q}\|} = \frac{\mathbf{q}}{\sqrt{q_0^2 + q_1^2 + q_2^2 + q_3^2}}
$$


**为什么必须归一化？**

- 四元数表示旋转时必须是单位四元数
- 数值积分会累积误差，导致模长变化
- 每次更新后必须归一化！

---


## 📖 第四部分：`MahonyAHRSupdateIMU()` 仅 IMU 版本

### 4.1 与完整版的区别

| 功能     | 完整版（ 9 轴） | 仅 IMU 版（6 轴） |
| ------ | --------- | ------------ |
| 磁力计    | ✅ 用       | ❌ 不用         |
| Yaw 修正 | ✅ 有       | ❌ 没有         |
| 计算量    | 多         | 少            |
| Yaw 漂移 | 小         | 有            |

### 4.2 核心差异
**只去掉了磁力计的修正项**

```c
// IMU版：只用加速度计
halfex = (ay * halfvz - az * halfvy);
halfey = (az * halfvx - ax * halfvz);
halfez = (ax * halfvy - ay * halfvx);

// 完整版：加速度计 + 磁力计
halfex = (ay * halfvz - az * halfvy) + (my * halfwz - mz * halfwy);
halfey = (az * halfvx - ax * halfvz) + (mz * halfwx - mx * halfwz);
halfez = (ax * halfvy - ay * halfvx) + (mx * halfwy - my * halfwx);
```

---


## 代码与数学符号对照表

| 代码符号                         | 数学符号                                                                 | 含义               |
| ---------------------------- | -------------------------------------------------------------------- | ---------------- |
| `halfvx`, `halfvy`, `halfvz` | $\frac{1}{2}\hat{g}_x, \frac{1}{2}\hat{g}_y, \frac{1}{2}\hat{g}_z$ | 估计重力向量的一半        |
| `halfwx`, `halfwy`, `halfwz` | $\frac{1}{2}\hat{m}_x, \frac{1}{2}\hat{m}_y, \frac{1}{2}\hat{m}_z$ | 估计磁场向量的一半        |
| `halfex`, `halfey`, `halfez` | $\frac{1}{2}e_x, \frac{1}{2}e_y, \frac{1}{2}e_z$                   | 总误差的一半           |
| `twoKp`, `twoKi`             | $2K_p, 2K_i$                                                       | 两倍增益，与 half 误差抵消 |
| `integralFBx`                | $I_x$                                                              | 积分项（已包含 Ki 和 dt） |
| `gx`, `gy`, `gz`             | $\omega_x, \omega_y, \omega_z$                                     | 陀螺仪角速度（修正后）      |


## 总结：Mahony 滤波的核心思想
1. **陀螺仪积分**：给出快速动态的姿态变化
2. **加速度计/磁力计修正**：通过叉积误差，纠正陀螺仪的漂移
3. **PI 控制器**：平衡响应速度和稳定性
4. **四元数积分**：把角速度变成姿态

**一句话概括**：
> "用陀螺仪开车（积分），用加速度计/磁力计看路牌（修正）"


## 参考资料 

1. **四元数基础**：
   - [维基百科：四元数与空间旋转](https://en.wikipedia.org/wiki/Quaternions_and_spatial_rotation)
   - [3Blue1Brown 四元数视频](https://www.youtube.com/watch?v=zjMuIxRvygQ)

2. **互补滤波原理**：
   - [原版 Mahony 论文](https://ahrs.readthedocs.io/en/latest/filters/mahony.html)

 3. **代码**
- [STM32_BMI088_MahonyAHRS](https://github.com/DoveOutland/STM32_BMI088_MahonyAHRS)


---


```ad-flex
title: ## 💡 进阶思考与工程坑点（备忘）
collapse: close

### 1. 源码中为什么到处都是 "half" 和 "two"？（代码小巧思）
* **现象**：源码中计算估计向量和误差时都乘以了 `0.5f`（如 `halfex = ...`），而增益宏定义却是 `twoKpDef (2.0f * 0.5f)`。
* **原理**：在四元数微分方程中，有公式 $\dot{q} = \frac{1}{2} q \otimes \boldsymbol{\omega}$，这里天然自带一个 $\frac{1}{2}$。
* **骚操作**：Mahony 在计算过程中故意让误差保留在“实际误差的一半（half）”，然后把控制增益定义为“理论增益的两倍（twoKp）”。当它们在修正角速度相乘时：
  

$$
\text{修正量} = \text{twoKp} \times \text{halfex} = (2K_p) \times \left(\frac{1}{2}e_x\right) = K_p \cdot e_x
$$


  **2 和 0.5 完美抵消！** 这直接在 MCU 的最内层循环里省去了好几次浮点数乘法，是早期单片机算力不足时，极其优雅的硬件级代码优化。

### 2. 这里的 Ki（积分项）到底是干嘛用的？
* **核心功能**：**陀螺仪零偏的在线自动追踪（Online Bias Estimation）**。
* **对比**：一阶互补滤波和简易版的 Madgwick 库由于没有积分项，一旦陀螺仪随温度漂移，角度就会越飘越远。而 Mahony 里的 `integralFBx` 会把误差一直累加。只要存在定常的角度偏差，积分项就会变大，反向逼迫并扣除陀螺仪的静态零偏，直到误差清零。
* **工程建议**：静态初始化（校准）时可以把 `Ki` 调大，让零偏快速收敛；正常运行后要把 `Ki` 调得非常小（甚至为 0），防止由于剧烈运动导致积分饱和（Integral Windup），引发姿态振荡。

### 3. 地磁融合的“一损俱损”隐患（磁干扰的致命缺陷）
* **坑点**：源码中把加速度计算出的重力误差 `halfex_acc` 和磁力计算出的地磁误差 `halfex_mag` **直接相加** 成了统一的 `halfex`。
* **隐患**：由于两个误差共享同一个 PI 控制器，一旦机器人靠近电机、铁轨或水下钢结构，磁力计会产生巨大的错误误差。这个错误会直接污染 `halfex`，不仅导致航向角（Yaw）完蛋，还会**强行拉歪原本很准的横滚（Roll）和俯仰（Pitch）**。
* **避坑指南**：在强磁干扰环境下，最稳妥的做法是直接将磁力计代码注释掉（或把磁力计权重设为 0），让 Mahony 退化为标准的 IMU（六轴）姿态解算，把 Roll/Pitch 保住。航向角（Yaw）的漂移交由其他传感器（如双目、激光雷达或里程计）去修正。
```

```ad-hibox
此文档为Ai+古法微调 感谢Ai 感谢中国
```
