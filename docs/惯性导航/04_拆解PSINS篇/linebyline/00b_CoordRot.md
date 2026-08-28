# 00b 坐标变换与旋转矩阵 Wiki — 从"东北天是左手系？"说起

> 所属层级: L0基础 · 前置阅读（在 [00a\_INSBasics.md](00a_INSBasics.md) 之后、[00\_glvf.md](00_glvf.md) 之前读）
> 前置依赖: [00a\_INSBasics.md](00a_INSBasics.md) 第 8 节（角速度符号约定："相对于"和"投影到"）
> 学习目标: 读完你应能回答
>
> 1. 东北天(ENU) 和北东地(NED) 哪个是右手系？怎么不用手势验证？
> 2. 主动旋转和被动旋转的区别是什么？惯导里用的是哪个？
> 3. 旋转矩阵里那个 $-\sin\theta$ 的负号从哪来？
> 4. 为什么"被动矩阵 = 主动矩阵的转置"？
> 5. 给一个旋转角，怎么"一眼看出"旋转矩阵每一列的符号？

***

> 📚 **衔接 wiki 数学主线**：本文从 PSINS 实战角度讲"三步法写旋转矩阵 + 东北天手性验证"；通用原理推导（单轴矩阵符号机理、三矩阵乘法顺序、$C_n^b$ 等式、主动/被动可视化）见 [坐标变换与旋转矩阵（推导入门）](../../00_前置数学基础/坐标变换与旋转矩阵.md)。两者互补，符号约定以具体工程为准。

## 🧩 这个文件为什么存在

很多初学者卡在惯导的第一步——**坐标变换**。典型症状：

- 看着"东北天"觉得它是左手系（**错觉**！）
- 旋转矩阵里一会儿 $+\sin\theta$ 一会儿 $-\sin\theta$，搞不清负号从哪来
- 听人说"被动变换 = 主动变换的转置"，但不知道为什么
- 教材里写 $C_1^2$、$R(\theta)$、$C_b^n$，分不清谁是谁的转置

这个文件就是把这些"第一步的坑"一次性填平。**不靠手势、不靠死记**，只用两个工具：

1. **叉乘公式**（验证坐标系手性）
2. **"旧 X 轴去哪了"三步法**（一眼写出旋转矩阵每一列）

学完后，你看 [11\_Mahony.md](11_Mahony.md) / [12\_QEAHRS.md](12_QEAHRS.md) 里的 $C_b^n$、$\mathbf{q}\otimes$、`rv2q` 就不会再被符号困扰。

***

## 1. 🦶 坐标系手性：东北天是左手系？（纠正一个直觉错觉）

### 1.1 错觉从哪来

很多人第一次看"东北天(ENU)"觉得它是左手系，原因出在**默认把 X 轴当成了北**。

如果你心里想的是"X=北、Y=东、Z=天"，然后伸右手四指从北(食指)转向东(中指)，大拇指确实指向**地**而不是天——看起来像左手系。

**但这是把轴顺序搞反了**。ENU 的标准定义是 **X=东、Y=北、Z=天**，不是 X=北。

### 1.2 叉乘法验证（不靠手势，靠公式）

手势容易搞混，用**叉乘的数学定义**最严谨。设 $\mathbf{i}, \mathbf{j}, \mathbf{k}$ 是笛卡尔基向量，叉乘基本性质：

$$\mathbf{i} \times \mathbf{j} = \mathbf{k}, \quad \mathbf{j} \times \mathbf{k} = \mathbf{i}, \quad \mathbf{k} \times \mathbf{i} = \mathbf{j}$$

> **右手系判据**：如果 $\mathbf{e}_1 \times \mathbf{e}_2 = \mathbf{e}_3$（第三个轴 = 前两个轴的叉乘），就是右手系。

| 坐标系 | 轴顺序 | 叉乘验证 $\mathbf{e}_1 \times \mathbf{e}_2 = \mathbf{e}_3$? | 结论 |
|---|---|---|---|
| **东北天 (ENU)** | X→东、Y→北、Z→天 | $\text{东} \times \text{北} = \mathbf{i} \times \mathbf{j} = \mathbf{k} = \text{天}$ ✓ | **右手系** |
| **北东地 (NED)** | X→北、Y→东、Z→地 | $\text{北} \times \text{东} = \mathbf{i} \times \mathbf{j} = \mathbf{k} = \text{地}$ ✓ | **右手系** |
| "北西天"（虚构） | X→北、Y→西、Z→天 | $\text{北} \times \text{西} = \mathbf{i} \times (-\mathbf{j}) = -\mathbf{k} = \text{地} \neq \text{天}$ ✗ | 左手系 |

**关键**：东北天和北东地**都是右手系**，区别只在"哪根轴叫 X"。把 X/Y 顺序对换，左手系立刻变右手系。

### 1.3 PSINS 用的是哪个？

看 [MahonyUpdate.m](file:///workspace/psins/base/AHRS/MahonyUpdate.m#L38-L40) 的关键代码：

```matlab
bxyz = ahrs.Cnb*mag;            % L38: 磁力计从 b 系转到 n 系
bxyz(1:2) = [0;norm(bxyz(1:2))]; % L39: 把 n 系磁场的"第1分量"清零
wxyz = ahrs.Cnb'*bxyz;          % L40: 转回 b 系
```

**L39 把第 1 分量清零、第 2 分量保留**，物理意义是"参考磁场只含北向和天向，去掉东向"。这说明 **n 系第 1 分量 = 东、第 2 分量 = 北、第 3 分量 = 天**——正是 ENU。

> **结论**：PSINS 默认导航系 n = 东北天(ENU)，右手系。代码里 `Cnb` 的列就是按"东-北-天"顺序排列的。

### 1.4 一句话记忆

> **东北天和北东地都是右手系，区别只是"哪根轴叫 X"。判手性不靠手势，靠叉乘 $\mathbf{e}_1 \times \mathbf{e}_2 = \mathbf{e}_3$。**

***

## 2. 🔄 主动 vs 被动：谁在动？

### 2.1 两种变换的定义

想象桌面上有一张白纸，纸上画了坐标系和一个箭头（向量）。

| 变换类型 | 谁动 | 谁不动 | 结果 | 公式 |
|---|---|---|---|---|
| **主动变换**（active） | **向量**转 +θ | 坐标系不动 | 向量在坐标系下的投影变了 | $\mathbf{r}_{\text{new}} = R(\theta)\,\mathbf{r}_{\text{old}}$ |
| **被动变换**（passive） | **坐标系**转 +θ | 向量不动 | 向量在新坐标系下的投影变了 | $\mathbf{r}_{\text{new}} = C\,\mathbf{r}_{\text{old}} = R(\theta)^T\,\mathbf{r}_{\text{old}}$ |

**关键洞察**：让向量顺时针转 $\theta$（主动），和让坐标系逆时针转 $\theta$（被动），**投影结果一样**。所以主动用 $R(\theta)$，被动用 $R(\theta)^T$——这是同一个旋转，两种描述方式。

### 2.2 惯导里用的是哪个？

**被动变换**——99% 的惯导坐标变换都是被动。

| 场景 | 谁动 | 物理量 | 变换 |
|---|---|---|---|
| 重力对准 | 飞机姿态在变(b系转) | 重力 $\mathbf{g}$ 在空间不动 | $C_b^n$（被动）把 $\mathbf{g}^n$ 投影到 b 系 |
| 磁场修正 | 飞机姿态在变(b系转) | 地磁场 $\mathbf{m}$ 在空间不动 | $C_b^n$（被动）把 $\mathbf{m}^n$ 投影到 b 系 |
| 速度积分 | 飞机姿态在变(b系转) | 速度是物理量 | $C_b^n$（被动）把 $\mathbf{v}^b$ 投影到 n 系 |

**主动变换**用在哪？用在**描述刚体自身姿态更新**——姿态四元数乘法 $\mathbf{q}_{k+1} = \mathbf{q}_k \otimes \text{rv2q}(\boldsymbol{\omega}T_s)$ 是主动旋转，描述机体系自己转了多少。

### 2.3 两者数学关系：互为转置

$$\boxed{C_{\text{被动}}(\theta) = R_{\text{主动}}(\theta)^T = R_{\text{主动}}(-\theta)}$$

最后一等号是因为旋转矩阵正交：$R^T = R^{-1} = R(-\theta)$。

> **记忆**：被动 = 主动的转置 = 主动的反向旋转。下面第 6 节会从"列拼起来"的角度证明这个等式。

***

## 3. 📐 投影的几何本质：cos(夹角)

旋转矩阵的每一项都是"投影"。理解投影，符号问题就解决了一半。

### 3.1 投影 = 作垂线

**投影的几何定义**：从向量末端 $P$ 向坐标轴**作垂线**，垂足到原点的距离就是投影。

这画出一个直角三角形：斜边 = 向量本身，两条直角边 = 在两个坐标轴上的投影。

### 3.2 单位向量投影 = cos / sin

直角三角形的边角关系（初中几何）：

$$\text{邻边} = \text{斜边} \times \cos(\text{夹角}), \quad \text{对边} = \text{斜边} \times \sin(\text{夹角})$$

如果向量是**单位向量**（长=1），与 X 轴夹角 = $\theta$，则：

- 水平边（X 轴投影）$= 1 \times \cos\theta = \cos\theta$
- 垂直边（Y 轴投影）$= 1 \times \sin\theta = \sin\theta$（因为垂直边与 Y 轴夹角 = $90°-\theta$，$\cos(90°-\theta) = \sin\theta$）

> **投影万能公式**：任意向量在某轴上的投影 = 向量长度 × cos(向量与该轴的夹角)。

### 3.3 负号从哪来？

如果夹角 $> 90°$（向量偏向了轴的反方向），$\cos$ 自动变负。**负号不是公式硬塞的，是几何上"向量偏向反方向"的自然结果**。

***

## 4. ➡️ 主动旋转矩阵推导

### 4.1 三步法：问"旧 X 轴去哪了"

矩阵乘法的基本性质：

$$M \begin{bmatrix}1\\0\\0\end{bmatrix} = M \text{ 的第 1 列}$$

**第一列 = 把旧 X 轴单位向量 $[1,0,0]^T$ 喂给这个矩阵，看它吐出什么**。这是"一眼看出"的钥匙——不用背公式，问自己：

> **"旧 X 轴那个向量，经过这个变换后，变成了什么？"**

**三步法**（任何旋转矩阵都适用）：

1. **问清是主动还是被动**（决定向量转还是系转）
2. **第一列 = 旧 X 轴 $[1,0,0]$ 的"去处"**
3. **第二列 = 旧 Y 轴 $[0,1,0]$ 的"去处"**，第三列同理

### 4.2 第一列推导（主动：旧 X 轴转 +θ）

- 旧 X 轴 $[1,0,0]$ 被主动转 $+\theta$ 角
- 转到哪？→ 与 X 轴夹角变成 $\theta$ → 新位置 $[\cos\theta, \sin\theta, 0]$
- **第一列 = $[\cos\theta, \sin\theta, 0]^T$** ✓

### 4.3 第二列推导（主动：旧 Y 轴转 +θ）

- 旧 Y 轴 $[0,1,0]$ 本来与 X 轴夹角 $90°$，转 $+\theta$ 后夹角变 $90°+\theta$
- 在 X 轴投影 = $\cos(90°+\theta) = -\sin\theta$（**负号！**因为 $90°+\theta > 90°$，向量偏向 X 轴反方向）
- 在 Y 轴投影 = $\sin(90°+\theta) = \cos\theta$
- **第二列 = $[-\sin\theta, \cos\theta, 0]^T$** ✓

### 4.4 拼出主动矩阵 $R(\theta)$

绕 Z 轴转 $\theta$（Z 轴不动，所以第三列 = $[0,0,1]^T$）：

$$\boxed{R_z(\theta) = \begin{bmatrix} \cos\theta & -\sin\theta & 0 \\ \sin\theta & \cos\theta & 0 \\ 0 & 0 & 1 \end{bmatrix}}$$

**这就是教材里那个 $\Psi$ 矩阵**——每一项都从"旧轴去哪了"推出来，没有一项是硬塞的。

***

## 5. ⬅️ 被动旋转矩阵推导

### 5.1 关键：向量相对新系的夹角成了 $(\phi-\theta)$

被动变换下，向量在空间里**纹丝不动**，但坐标系转了 $+\theta$。

设向量初始与旧 X 轴夹角 = $\phi$（向量初始角）。坐标系逆时针转 $\theta$ 后，向量**相对新 X' 轴**的夹角变成：

$$\boxed{\phi_{\text{相对新系}} = \phi - \theta}$$

**为什么是减号**？因为坐标系"跑"到向量前面去了 $\theta$，向量在坐标系里看就"后退"了 $\theta$——夹角从 $\phi$ 变成 $\phi-\theta$。

### 5.2 $(\phi-\theta)$ 投影公式

向量在新系的坐标 = 向量长度 × cos(向量与新轴的夹角)：

$$\mathbf{r}_{\text{新系}} = \begin{bmatrix} r\cos(\phi-\theta) \\ r\sin(\phi-\theta) \\ 0 \end{bmatrix}$$

这就是你那个 HTML 文件底部写的：

> **被动旋转**：$v_2 = C_1^2 \cdot v_1 = [r\cos(\phi-\theta),\, r\sin(\phi-\theta),\, 0]^T$

### 5.3 符号反转：$\sin(\phi-\theta)$ 跨越 0 轴

用和差公式展开：

$$\cos(\phi-\theta) = \cos\phi\cos\theta + \sin\phi\sin\theta$$
$$\sin(\phi-\theta) = \sin\phi\cos\theta - \cos\phi\sin\theta$$

**关键现象**：当 $\theta > \phi$ 时，$\sin(\phi-\theta) < 0$——**新系下 Y' 轴投影变负**！这就是你 HTML 里"红线向下"那个临界点。

### 5.4 拼出被动矩阵 $C = R(\theta)^T$

把"旧 X 轴"和"旧 Y 轴"分别作为初始向量（$\phi=0$ 和 $\phi=90°$），套用第 5.2 节公式：

**第一列**（旧 X 轴，$\phi=0$）：
- 相对新系夹角 = $0-\theta = -\theta$
- 在新 X' 轴投影 = $\cos(-\theta) = \cos\theta$（cos 是偶函数，**不变号**）
- 在新 Y' 轴投影 = $\sin(-\theta) = -\sin\theta$（sin 是奇函数，**反号了**！）
- **第一列 = $[\cos\theta, -\sin\theta, 0]^T$** ✓

**第二列**（旧 Y 轴，$\phi=90°$）：
- 相对新系夹角 = $90°-\theta$
- 在新 X' 轴投影 = $\cos(90°-\theta) = \sin\theta$
- 在新 Y' 轴投影 = $\sin(90°-\theta) = \cos\theta$
- **第二列 = $[\sin\theta, \cos\theta, 0]^T$** ✓

拼起来（绕 Z 轴，第三列 $[0,0,1]^T$）：

$$\boxed{C_z(\theta) = \begin{bmatrix} \cos\theta & \sin\theta & 0 \\ -\sin\theta & \cos\theta & 0 \\ 0 & 0 & 1 \end{bmatrix} = R_z(\theta)^T}$$

> **负号的唯一来源**：被动变换下，旧轴相对新系的夹角是 $-\theta$（而不是 $+\theta$），$\sin(-\theta) = -\sin\theta$ 就反号了。这不是公式硬塞的，是几何上"向量相对新轴后退了"的自然结果。

***

## 6. 🔗 被动 = 主动的转置（列拼起来证明）

把第 4 节和第 5 节推出的两组列并排放：

| | 第 1 列 | 第 2 列 |
|---|---|---|
| **主动** $R(\theta)$ | $[\cos\theta,\, +\sin\theta]^T$ | $[-\sin\theta,\, \cos\theta]^T$ |
| **被动** $C(\theta)$ | $[\cos\theta,\, -\sin\theta]^T$ | $[\sin\theta,\, \cos\theta]^T$ |

**对照看**：

- 主动第 1 列 $[\cos\theta, +\sin\theta]^T$ ↔ 被动第 1 **行** $[\cos\theta, +\sin\theta]$
- 主动第 2 列 $[-\sin\theta, \cos\theta]^T$ ↔ 被动第 2 **行** $[-\sin\theta, \cos\theta]$

**被动矩阵的行 = 主动矩阵的列**——这正是**转置**的定义！

### 6.1 几何解释

- 主动矩阵的列 = "旧轴转 $+\theta$ 后的位置"
- 被动矩阵的列 = "旧轴在新系里的坐标" = "旧轴相对新系成了 $-\theta$ 角时的投影"
- 这两个描述**角度符号相反**，恰好对应"转置 = 反向旋转"

### 6.2 代数证明（一行）

旋转矩阵是正交矩阵：$R(\theta)^{-1} = R(\theta)^T = R(-\theta)$。

- 主动转 $+\theta$ 的逆 = 主动转 $-\theta$
- 被动转 $+\theta$（坐标系转 $+\theta$）= 等价于向量主动转 $-\theta$（向量相对新系后退 $\theta$）
- 所以 $C(\theta) = R(-\theta) = R(\theta)^T$ ✓

> **一句话记忆**：被动 = 主动的转置，因为"坐标系转 $+\theta$"等价于"向量相对坐标系转 $-\theta$"，角度反号 → 矩阵转置。

***

## 7. 🎯 三个轴的旋转矩阵汇总

上面只推了绕 Z 轴。绕 X、Y 轴同理，用三步法（"旧轴去哪了"）可以推出。

### 7.1 绕 Z 轴（航向 $\psi$）

$$R_z(\psi) = \begin{bmatrix} \cos\psi & -\sin\psi & 0 \\ \sin\psi & \cos\psi & 0 \\ 0 & 0 & 1 \end{bmatrix}, \quad C_z(\psi) = R_z(\psi)^T = \begin{bmatrix} \cos\psi & \sin\psi & 0 \\ -\sin\psi & \cos\psi & 0 \\ 0 & 0 & 1 \end{bmatrix}$$

### 7.2 绕 X 轴（横滚 $\gamma$）

$$R_x(\gamma) = \begin{bmatrix} 1 & 0 & 0 \\ 0 & \cos\gamma & -\sin\gamma \\ 0 & \sin\gamma & \cos\gamma \end{bmatrix}, \quad C_x(\gamma) = R_x(\gamma)^T = \begin{bmatrix} 1 & 0 & 0 \\ 0 & \cos\gamma & \sin\gamma \\ 0 & -\sin\gamma & \cos\gamma \end{bmatrix}$$

**推导**（绕 X 轴，X 轴不动，看 Y/Z 轴）：
- 旧 Y 轴 $[0,1,0]$ 转到 $[0, \cos\gamma, \sin\gamma]^T$（向 Z 方向偏）→ 第 2 列
- 旧 Z 轴 $[0,0,1]$ 转到 $[0, -\sin\gamma, \cos\gamma]^T$（向 Y 反方向偏）→ 第 3 列，**负号在这里**

### 7.3 绕 Y 轴（俯仰 $\theta$）

$$R_y(\theta) = \begin{bmatrix} \cos\theta & 0 & \sin\theta \\ 0 & 1 & 0 \\ -\sin\theta & 0 & \cos\theta \end{bmatrix}, \quad C_y(\theta) = R_y(\theta)^T = \begin{bmatrix} \cos\theta & 0 & -\sin\theta \\ 0 & 1 & 0 \\ \sin\theta & 0 & \cos\theta \end{bmatrix}$$

**注意**：绕 Y 轴的主动矩阵里 $+\sin\theta$ 在右上，$-\sin\theta$ 在左下——这是因为 Y 轴旋转的"正方向"（右手定则）是 X→Z 方向，符号位置和绕 Z/X 轴略不同。**用三步法推一次就记住了，不要硬背**。

### 7.4 欧拉角顺序（Z-Y-X，PSINS 默认）

PSINS 的 `m2att` / `att2m` 用的是 **Z→Y→X（yaw→pitch→roll）** 顺序的欧拉角。被动变换的合成（坐标系依次转 $\psi, \theta, \gamma$）：

$$C_b^n = C_z(\psi) \cdot C_y(\theta) \cdot C_x(\gamma)$$

注意**矩阵乘法不交换**——这就是 [00a\_INSBasics.md](00a_INSBasics.md) 第 1 节讲"圆锥误差"的数学根源。

***

## 8. 💻 PSINS 里的 $C_b^n$ 是什么

### 8.1 $C_b^n$ = 被动变换（b→n 投影）

PSINS 里 `ins.Cnb` / `ahrs.Cnb` 是**从 b 系（机体系）到 n 系（导航系）的坐标变换矩阵**，**被动变换**：

$$\mathbf{r}^n = C_b^n \cdot \mathbf{r}^b$$

**读法**：$C_b^n$ = "把 b 系向量投影到 n 系"。下标 b 是"源坐标系"，上标 n 是"目标坐标系"。

### 8.2 $C_b^n{}'$ = 主动变换（n→b 投影）

因为 $C_b^n$ 正交，它的转置就是逆：

$$(C_b^n)^T = (C_b^n)^{-1} = C_n^b$$

**所以 `ahrs.Cnb'`（转置）= 从 n 系到 b 系的变换**。代码里常见：

```matlab
bxyz = ahrs.Cnb*mag;    % n→b? 不，这是 b→n
wxyz = ahrs.Cnb'*bxyz;  % n→b（转置）
```

- `ahrs.Cnb * mag`：`mag` 是 b 系磁力计，乘 $C_b^n$ → 得 n 系磁场（b→n 投影）
- `ahrs.Cnb' * bxyz`：`bxyz` 是 n 系参考磁场，乘 $C_n^b$ → 得 b 系参考（n→b 投影）

### 8.3 代码对照

[MahonyUpdate.m](file:///workspace/psins/base/AHRS/MahonyUpdate.m#L38-L40)（已在第 1.3 节引用）：

```matlab
bxyz = ahrs.Cnb*mag;             % L38: b→n 投影
bxyz(1:2) = [0;norm(bxyz(1:2))]; % L39: 清零东向（n系第1分量=东）
wxyz = ahrs.Cnb'*bxyz;           % L40: n→b 投影（转置）
```

[QEAHRSUpdate.m](file:///workspace/psins/base/AHRS/QEAHRSUpdate.m) 里状态量 $\mathbf{q}$ 通过 `q2dcm` 转 $C_b^n$，再用 $C_b^n$ 把 n 系重力 $[0,0,-g]^T$ 投影到 b 系做量测——**全程被动变换**。

> **代码阅读技巧**：看到 `Cnb * X` 就是 b→n（X 是 b 系量），看到 `Cnb' * X` 就是 n→b（X 是 n 系量）。**矩阵的上下标 + 是否转置**，决定了投影方向。

***

## 9. 🎨 配套可视化

[active_vs_passive_rotation_modified.html](file:///workspace/active_vs_passive_rotation_modified.html) 提供了一个**双滑块交互式对比**：

- **左滑块 $\phi$**：控制向量初始角
- **右滑块 $\theta$**：控制旋转角
- 左图：主动变换（向量转 $+\theta$，坐标系不动）
- 右图：被动变换（坐标系转 $+\theta$，向量不动）
- 底部矩阵：实时显示 $R(\theta)$ 和 $C = R(\theta)^T$ 的数值

**建议操作**：

1. 把 $\phi=20°, \theta=35°$，看右图被动变换下向量末端向新 X' 轴作垂线，**Y' 投影是负的**（红线向下）
2. 把 $\theta$ 拉到 $\theta > \phi$（如 $\phi=20°, \theta=50°$），看 $\sin(\phi-\theta)$ 变负——**这就是符号反转的临界点**
3. 对照两个矩阵，验证"被动 = 主动的转置"——左矩阵第 1 列 = 右矩阵第 1 行

> **学习建议**：边玩边对照本文第 5.2 节的 $(\phi-\theta)$ 公式，5 分钟就能彻底理解符号来源。

***

## 10. ❌ 初学者最容易踩的坑

1. **把"东北天"误判为左手系**：本质是把 X 轴默认成了北。ENU 的标准定义是 X=东、Y=北、Z=天，按此顺序叉乘 $\text{东} \times \text{北} = \text{天}$ 完全符合右手系。
2. **混淆主动和被动**：看到旋转矩阵就以为是"向量在转"。惯导里 $C_b^n$ 是被动变换——物理量不动，机体系在转。
3. **死记 $-\sin\theta$ 的位置**：不要背，用"旧 X 轴去哪了"三步法推一次就记住了。负号来自"旧轴相对新系成了 $-\theta$ 角"。
4. **以为被动矩阵是新东西**：它就是主动矩阵的转置。代码里 `Cnb'` 就是 $C_n^b$。
5. **搞混 $C_b^n$ 的上下标**：下标 b 是源（被投影的系），上标 n 是目标（投影到哪个系）。`Cnb * X` = b→n。
6. **欧拉角顺序记不住**：PSINS 用 Z-Y-X（yaw→pitch→roll）。矩阵乘法不交换，顺序错了结果完全不同——这就是圆锥误差的根源。

***

## 11. 🎯 配套练习

### 练习 1：手推绕 X 轴的主动矩阵

用三步法（"旧轴去哪了"）推 $R_x(\gamma)$。提示：X 轴不动，看 Y 轴和 Z 轴分别转到哪。

**验证**：第 2 列 = $[0, \cos\gamma, \sin\gamma]^T$（旧 Y 轴向 Z 方向偏），第 3 列 = $[0, -\sin\gamma, \cos\gamma]^T$（旧 Z 轴向 Y 反方向偏）。

### 练习 2：验证被动 = 主动转置

写一段 MATLAB 代码：

```matlab
theta = 35 * pi/180;
R = [cos(theta) -sin(theta) 0; sin(theta) cos(theta) 0; 0 0 1];
C = R';   % 被动 = 主动转置
% 验证：把 [1;0;0]（旧X轴）分别喂给 R 和 C
disp(R * [1;0;0]);   % 应得 [cos(theta); sin(theta); 0]  —— 主动：旧X轴转+theta
disp(C * [1;0;0]);   % 应得 [cos(theta); -sin(theta); 0] —— 被动：旧X轴相对新系成-theta
```

**对照**：[active_vs_passive_rotation_modified.html](file:///workspace/active_vs_passive_rotation_modified.html) 把 $\phi=0, \theta=35°$，左图末端 = $[\cos 35°, \sin 35°]$，右图末端 = $[\cos 35°, -\sin 35°]$，与上面代码输出一致。

### 练习 3：PSINS 代码追踪

打开 [MahonyUpdate.m](file:///workspace/psins/base/AHRS/MahonyUpdate.m#L38-L40)，回答：

1. L38 `ahrs.Cnb*mag` 中 `mag` 是 b 系还是 n 系量？结果 `bxyz` 是 b 系还是 n 系量？
2. L39 为什么清零第 1 分量？这和"n 系第 1 分量 = 东"有什么关系？
3. L40 `ahrs.Cnb'` 为什么加转置？

**答案**：1. `mag` 是 b 系量，`bxyz` 是 n 系量；2. 清零东向 = 让参考磁场只含北向和天向，避免磁力计污染 pitch/roll；3. 转置 = 把 n 系量 `bxyz` 转回 b 系做叉积误差。

### 练习 4：手算符号反转临界点

设 $\phi=20°$。问 $\theta$ 取多少时，被动变换下 Y' 轴投影开始变负？

**解**：$\sin(\phi-\theta) < 0 \Rightarrow \phi-\theta < 0 \Rightarrow \theta > \phi = 20°$。所以 $\theta = 20°$ 是临界点，$\theta > 20°$ 时 Y' 投影为负。

**在 HTML 里验证**：把左滑块拉到 $\phi=20°$，右滑块从 $20°$ 慢慢拉到 $50°$，观察右图红线（Y' 投影）从向上变成向下。

***

## 📚 下一站

读完本文件，你就可以去 [00\_glvf.md](00_glvf.md) 了——那里的 `glv.cs / glv.ws / glv.dph` 不再陌生。

然后顺序往下：

- [00\_glvf.md](00_glvf.md) → 全局参数总入口
- [01\_earth.md](01_earth.md) → 地球参数计算（$\omega_{ie}^n$ 在这里落地）
- [02\_cnscl.md](02_cnscl.md) → 圆锥+划桨补偿实现层
- [03\_insupdate.md](03_insupdate.md) → SINS 三连更新核心（$C_b^n$ 在这里被更新）
- [11\_Mahony.md](11_Mahony.md) / [12\_QEAHRS.md](12_QEAHRS.md) → AHRS 算法（$C_b^n$ 的两种估法）
