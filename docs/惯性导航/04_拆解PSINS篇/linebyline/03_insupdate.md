# insupdate.m 逐行注释 Wiki (PSINS)

> 配套源码: [insupdate.m](file:///workspace/psins/base/base1/insupdate.m)
> 所属层级: L1纯惯导
> 前置依赖: 必须先读 00_glvf.md（四元数/旋转辅助函数）、01_earth.md（地球模型eth）、02_cnscl.md（圆锥划桨补偿）
> 学习目标: 读完后你应能回答哪3个问题
> 1. SINS机械编排"三连更新"（姿态-速度-位置）的**顺序**为什么是速度→位置→姿态？调换顺序会有什么精度损失？
> 2. 速度更新公式中 `ins.an = rotv(-ins.eth.wnin*nts2, ins.fn) + ins.eth.gcc` 每一项的物理含义是什么？为什么要用rotv对比力做wnin半步旋转？
> 3. 位置更新的Mpv矩阵 `[0, 1/RMh, 0; 1/(cl·RNh), 0, 0; 0, 0, 1]` 各元素怎么来的？为什么Mpv(2,1)必须除以cos(L)？

---

## 🧩 函数作用一句话

捷联惯导三连更新：姿态速度位置

---

## 📐 数学原理 / 物理意义

### 1. 坐标系与基本符号约定

在纯惯导（SINS）机械编排中，使用三个右手直角坐标系：

| 坐标系 | 符号 | 原点 | 轴向 | 用途 |
|--------|------|------|------|------|
| **惯性系i** | $O_i x_i y_i z_i$ | 地心 | $z_i$沿地球自转轴，$x_i$指向春分点 | 牛顿力学成立，陀螺/加计原始测量参考系 |
| **地心地固系e** | $O_e x_e y_e z_e$ | 地心 | $z_e$沿地轴，$x_e$过0°经线赤道交点 | 与地球固连旋转，角速度$\omega_{ie}$ |
| **导航系n（当地地理系）** | $O_n E N U$ | 载体位置 | 东E/北N/天U（PSINS用北东地NED惯例） | 机械编排求解参考系 |
| **机体系b** | $O_b x_b y_b z_b$ | IMU安装中心 | 右前上（或按载体定义） | IMU测量敏感轴 |

**关键角度符号**：
- 纬度 $L$（Latitude）：当地水平面法线与赤道面夹角，单位rad，范围[-π/2, π/2]
- 经度 $\lambda$（Longitude）：本初子午面到当地子午面夹角，单位rad，范围[-π, π]
- 高度 $h$（Altitude）：沿椭球法线到参考椭球面距离，单位m

**地球基本参数**（WGS84）：
- 地球自转角速率：$\omega_{ie} = 7.2921151467 \times 10^{-5}$ rad/s
- 椭球长半轴：$a = 6378137.0$ m
- 椭球扁率：$f = 1/298.257223563$
- 子午圈曲率半径 $R_M$（沿经线）、卯酉圈曲率半径 $R_N$（沿纬线）：

$$
R_M = \frac{a(1-e^2)}{(1-e^2\sin^2 L)^{3/2}}, \quad
R_N = \frac{a}{(1-e^2\sin^2 L)^{1/2}}
$$

其中 $e^2 = 2f-f^2$ 为第一偏心率平方。含高度时：$RMh = R_M + h$，$RNh = R_N + h$，单位m。

---

### 2. SINS机械编排三连更新完整公式

设SINS更新周期为 $T_s = n \cdot \Delta t$（n子样），当前时刻 $t_k$，下一时刻 $t_{k+1}=t_k+T_s$。记半步时刻 $t_{k+1/2} = t_k + T_s/2$（中点积分时刻）。

已知状态：$t_k$ 时刻姿态四元数 $\mathbf{Q}_{nb}(t_k)$、速度 $\mathbf{v}^n(t_k)$、位置 $\mathbf{p}(t_k)=[L_k, \lambda_k, h_k]^T$；当前周期IMU增量（经cnscl补偿后）：等效旋转矢量 $\Delta\boldsymbol{\phi}_m$（rad）、等效速度增量 $\Delta\mathbf{v}_{bm}$（m/s）。

#### 三连更新顺序：为什么是"速度→位置→姿态"？

教科书上通常写"姿态→速度→位置"（先更新姿态，用新姿态投影比力，再算速度，再算位置）。但 PSINS 的实际代码顺序是**反过来**的：

| 步骤 | PSINS 实际顺序 | 为什么这个顺序 |
|---|---|---|
| **第1步：速度** | 用 $t_k$ 的姿态 $C_{nb}(t_k)$ 投影比力 → 算 $a_{k+1/2}$ → 中点法算 $v_{k+1}$ | 速度只需要**旧姿态**（$t_k$ 已有），不需要新姿态 |
| **第2步：位置** | 用旧速度 $v_k$ + 新速度 $v_{k+1}$ 取平均 → 梯形法算 $p_{k+1}$ | 位置需要**新旧速度两头**——所以速度必须先算出来 |
| **第3步：姿态** | 用 phim + wnin 更新四元数 → 得到 $C_{nb}(t_{k+1})$ | 姿态最后做——因为更新完 $C_{nb}$ 就变了，后面没人再用它了 |

> 💡 **一句话直觉**：姿态最后更新，是因为**新姿态对速度和位置的计算没有用**（速度用的是 $t_k$ 的旧姿态）。如果先更新姿态，反而要担心"新姿态 vs 旧姿态"混用的问题。所以**把姿态更新推到最后，让速度和位置都用旧姿态算完，再统一换新**。

#### 一个带数字的例子：静止状态下走一步

假设载体静止，IMU 无误差，$T_s = 0.1$ s，初始 $v=0$，$h=0$，$L=34°$。

- 陀螺输出 ≈ 0（静止，只有地球自转 $7.29 \times 10^{-5}$ rad/s，可忽略）
- 加计输出 $\mathbf{f}^b \approx [0, 0, -9.8]$ m/s²（感受重力反向）
- 姿态 $C_{nb} = I$（水平无转角）

**走一步 insupdate 会怎样？**

1. **L22 半步外推**：$v_{01} = 0 + 0 \times 0.05 = 0$，$p_{01}$ 也不变（速度为 0）

2. **L32 加速度**：$a^n = f^n + g_{cc} = [0, 0, -9.8] + [0, 0, +9.8] = [0, 0, 0]$
   > 静止时比力 = -g，重力 = +g，**两者抵消**，加速度 = 0 → 符合直觉！

3. **L34 新速度**：$v_{k+1} = 0 + 0 \times 0.1 = 0$ → 速度不变 ✓

4. **L39 位置变化率**：$M_{pv} \cdot (0+0)/2 = 0$ → 位置不变 ✓

5. **L46 姿态更新**：phim ≈ 0（陀螺无输出），wnin 很小（地球自转+位移角速度），qnb 几乎不变 ✓

> **结论**：静止时 insupdate 每一步都是"零增量"——速度不变、位置不变、姿态不变。这正是"无运动 = 无变化"的物理直觉验证。**如果静止仿真时位置漂移了，说明要么 IMU 有零偏，要么 gcc 符号写错了**（参见坑③）。

---

#### (1) 姿态更新：四元数递推

**姿态微分方程**（泊松方程四元数形式）：

$$
\dot{\mathbf{Q}}_{nb}(t) = \frac{1}{2}\mathbf{Q}_{nb}(t) \otimes \boldsymbol{\omega}_{nb}^b(t)
$$

其中 **机体系b相对于导航系n的角速度在b系投影**：

$$
\boldsymbol{\omega}_{nb}^b = \boldsymbol{\omega}_{ib}^b - \mathbf{C}_{nb}^T \boldsymbol{\omega}_{in}^n
= \underbrace{\boldsymbol{\omega}_{ib}^b}_{\text{陀螺输出}} - \mathbf{C}_{nb}^T \left( \underbrace{\boldsymbol{\omega}_{ie}^n}_{\text{地球自转}} + \underbrace{\boldsymbol{\omega}_{en}^n}_{\text{运载体位移}} \right)
$$

- $\boldsymbol{\omega}_{in}^n = \boldsymbol{\omega}_{ie}^n + \boldsymbol{\omega}_{en}^n$：导航系相对于惯性系的角速度（**两部分之和**），单位rad/s
- $\boldsymbol{\omega}_{en}^n$（位移角速度/牵连角速度）：由载体相对地球运动引起导航系原点转动，公式：

$$
\boldsymbol{\omega}_{en}^n = \begin{bmatrix}
-\frac{v_N}{RMh} \\
\frac{v_E}{RNh} \\
\frac{v_E \tan L}{RNh}
\end{bmatrix}
$$

**离散积分采用"双子样等效旋转矢量法"**（比简单一阶欧拉高两阶精度）：

$$
\mathbf{Q}_{nb}(t_{k+1}) = \mathbf{Q}_{nb}(t_k) \otimes \mathbf{q}_{\Delta}(\Delta\boldsymbol{\phi}_m) \otimes \mathbf{q}_{\omega}(-\boldsymbol{\omega}_{in}^n T_s)
$$

其中：
- $\mathbf{q}_{\Delta}(\Delta\boldsymbol{\phi}_m)$：**右乘项**，IMU等效旋转矢量对应的四元数，体现**机体系相对惯性系的转动**
- $\mathbf{q}_{\omega}(-\boldsymbol{\omega}_{in}^n T_s)$：**左乘项**（四元数乘法顺序对应姿态补偿反向），补偿**导航系本身相对于惯性系的转动**
- 负号：因$\boldsymbol{\omega}_{in}^n$定义为"n系相对i系的角速度"，而我们要维持姿态在n系下，所以反向扣除

PSINS使用`qupdt2(qnb, phim, wnin_nts)`一次性实现这一双向更新，对应L46。

---

#### (2) 速度更新：比力积分 + 有害加速度补偿

**速度微分方程**（比力方程，SINS核心）：

$$
\dot{\mathbf{v}}^n(t) = \mathbf{C}_{bn}(t) \mathbf{f}_{sf}^b(t) - (2\boldsymbol{\omega}_{ie}^n + \boldsymbol{\omega}_{en}^n) \times \mathbf{v}^n(t) + \mathbf{g}^n(t)
$$

离散形式（中点积分，$f_L, f_R, g, \omega$均近似取半步时刻值）：

$$
\mathbf{v}^n(t_{k+1}) = \mathbf{v}^n(t_k) + T_s \cdot \left[ \, \mathbf{C}_{bn}(t_{k+1/2}) \bar{\mathbf{f}}_{sf}^b \;+\; \mathbf{g}^n(t_{k+1/2}) \;-\; (2\boldsymbol{\omega}_{ie}^n + \boldsymbol{\omega}_{en}^n)(t_{k+1/2}) \times \mathbf{v}^n(t_{k+1/2}) \, \right]
$$

将四项合并写为"比力投影 + 有害加速度补偿gcc"：

$$
\mathbf{v}^n(t_{k+1}) = \mathbf{v}^n(t_k) + T_s \cdot \mathbf{a}^n(t_{k+1/2})
$$

其中：

$$
\mathbf{a}^n(t_{k+1/2}) = \underbrace{\mathbf{R}\left(-\frac{\boldsymbol{\omega}_{in}^n T_s}{2}\right) \cdot \mathbf{C}_{bn}(t_k) \bar{\mathbf{f}}_{sf}^b}_{\text{旋转补偿后的比力（导航系）}} \;+\; \underbrace{\mathbf{g}_{cc}^n}_{\text{重力+科里奥利+离心合成项}}
$$

**各项逐项解释**：

| 项 | 公式/代码 | 物理意义 | 单位 |
|----|-----------|----------|------|
| **比力** $\mathbf{f}^n$ | `qmulv(qnb, fb)` = $\mathbf{C}_{bn}\mathbf{f}_{sf}^b$ | 将机体系比力（加计输出）投影到导航系。这是加速度的"原始来源" | m/s² |
| **旋转补偿rotv** | `rotv(-wnin*nts2, fn)` | 比力从t_k时刻的导航系**旋转到半步时刻t_{k+1/2}的导航系**。wnin是导航系相对惯性系的角速度，乘T_s/2是半步旋转角。负号：因$\mathbf{R}(\boldsymbol{\theta})\mathbf{a}$表示"把向量a转过θ"，而wnin使n系在旋转，比力向量需**反向补偿**半步旋转 | m/s² |
| **重力项** | `gcc`内包含的$\mathbf{g}_l$ | 正常重力（沿椭球法线向下，即U轴负方向）。由闭合公式Somigliana近似给出 | m/s² |
| **科里奥利项** | `gcc`内包含的$-2\boldsymbol{\omega}_{ie}^n \times \mathbf{v}^n$ | 地球自转引起的牵连加速度（科里奥利力）。运动物体在旋转参考系中受"虚假偏转力"：北半球向右偏，南半球向左偏 | m/s² |
| **离心力项** | `gcc`内包含的$-\boldsymbol{\omega}_{ie}^n \times (\boldsymbol{\omega}_{ie}^n \times \mathbf{r})$ | 地球自转产生的离心加速度。已合并到"正常重力"g中（g=gravitation-centrifugal，重力=万有引力-离心力），gcc隐含此项 | m/s² |
| **相对离心** | `gcc`内包含的$-\boldsymbol{\omega}_{en}^n \times (\boldsymbol{\omega}_{ie}^n+\boldsymbol{\omega}_{en}^n) \times \mathbf{r}$ | 载体相对地球高速运动引起的附加离心，已合并在gcc中 | m/s² |

**为什么中点积分精度更高？**
普通一阶欧拉积分用区间起点值：$v_{k+1} = v_k + a_k T_s$，截断误差 $O(T_s^2)$。中点积分用区间中点值：$v_{k+1} = v_k + a_{k+1/2} T_s$，截断误差 $O(T_s^3)$，**精度高一阶**。

#### 数值积分三阶梯对比：PSINS 用的是哪一级？

| 阶梯 | 方法 | 速度更新公式 | 截断误差 | PSINS 用的？ |
|---|---|---|---|---|
| ① | **矩形法**（一阶欧拉） | $v_{k+1} = v_k + a_k \cdot T_s$ | $O(T_s^2)$ | ❌ 太粗糙 |
| ② | **梯形法** | $v_{k+1} = v_k + \dfrac{a_k + a_{k+1}}{2} \cdot T_s$ | $O(T_s^3)$ | 接近，但需要 $a_{k+1}$ |
| ③ | **中点法**（PSINS 实际用的） | $v_{k+1} = v_k + a_{k+1/2} \cdot T_s$ | $O(T_s^3)$ | ✅ 就是 L32+L34 |

**梯形法和中点法精度同阶（都是 $O(T_s^3)$），但 PSINS 为什么选了中点法而不是梯形法？**

因为**梯形法需要 $a_{k+1}$，而它要等下一拍才算出来**——下一拍的 $a_{k+1}$ 需要下一拍的姿态 $C_{nb}(t_{k+1})$ 和地球参数 $\mathrm{eth}(t_{k+1})$，这些在本拍还没算出来。

PSINS 的解法：用半步外推把 $a_k$ 推到 $a_{k+1/2}$，用中点法达到和梯形法同阶的精度。**这就是 L22 半步外推存在的根本原因**——你不算半步，就只能用矩形法（一阶精度），误差随时间线性累积。

```
     a_k --------approx--------> a_{k+1/2} --------approx--------> a_{k+1}
      ↑                              ↑                               ↑
   L32 算出来                   L22 外推得到              下一拍才能算
   (用 t_k 姿态)              (用 vn01/pos01 估半步)      (现在拿不到!)
                                      ↓
                              L34: v_{k+1} = v_k + a_{k+1/2}·T_s
                              ← 中点法，O(T_s³)，不需要 a_{k+1}
```

> 💡 **一句话记忆**：梯形法要"两头加速度"（$a_k$ 和 $a_{k+1}$），但未来拿不到；中点法只要"中间加速度"（$a_{k+1/2}$），半步外推就能估出来。**PSINS = 用半步外推 + 中点法，绕开了梯形法"需要未来值"的困境，精度还一样高。**

---

#### (3) 位置更新：经纬度积分

位置（纬度L、经度λ、高度h）与导航系速度(v_E, v_N, v_U)的微分关系（由球面几何或椭球面第一基本形式）：

$$
\dot{L} = \frac{v_N}{RMh}, \quad
\dot{\lambda} = \frac{v_E}{RNh \cos L}, \quad
\dot{h} = v_U
$$

写成矩阵形式 $\dot{\mathbf{p}} = \mathbf{M}_{pv} \mathbf{v}^n$：

$$
\begin{bmatrix} \dot{L} \\ \dot{\lambda} \\ \dot{h} \end{bmatrix}
= \begin{bmatrix}
0 & \frac{1}{RMh} & 0 \\
\frac{1}{RNh \cos L} & 0 & 0 \\
0 & 0 & 1
\end{bmatrix}
\begin{bmatrix} v_E \\ v_N \\ v_U \end{bmatrix}
$$

这就是Mpv矩阵。关键要点：
- **Mpv(1,2)=1/RMh**：北速v_N→纬度变化率，沿子午圈（经线）方向，所以除以RMh
- **Mpv(2,1)=1/(RNh·cosL)**：东速v_E→经度变化率，沿卯酉圈（纬线）方向。纬线圈半径=RNh·cosL（赤道半径RNh，在纬度L处按cosL缩放），所以经度变化=东速/(纬线圈半径)
- **Mpv(3,3)=1**：天速直接变高度率（地心地固近似下）

**离散中点积分**：速度取前后时刻平均 $\bar{\mathbf{v}}^n = (\mathbf{v}^n(t_k) + \mathbf{v}^n(t_{k+1}))/2$

$$
\mathbf{p}(t_{k+1}) = \mathbf{p}(t_k) + T_s \cdot \mathbf{M}_{pv}(t_{k+1/2}) \cdot \frac{\mathbf{v}^n(t_k) + \mathbf{v}^n(t_{k+1})}{2}
$$

#### 位置积分用的就是梯形法！

你可能听说过"惯导里位置用梯形积分"——就是这里。对照上一节的"三阶梯"表：

| 积分对象 | 方法 | 公式 | 对应代码 |
|---|---|---|---|
| **速度**（$\int a \, dt$） | **中点法** | $v_{k+1} = v_k + a_{k+1/2} \cdot T_s$ | L32+L34 |
| **位置**（$\int v \, dt$） | **梯形法** | $p_{k+1} = p_k + \dfrac{v_k + v_{k+1}}{2} \cdot T_s$ | L39+L40 |

**为什么位置能用梯形法而速度不能？** 因为位置积分时，$v_{k+1}$ **已经在本拍算出来了**（L34 算出 vn1），两头速度都有，可以直接取平均。而速度积分时 $a_{k+1}$ 要等下一拍才有——所以速度被迫用中点法，位置可以大方用梯形法。

> 💡 **你之前听说的"速度外推 + 位置梯形积分"完全正确**，对应关系：
> - "速度外推" = L22 的 `vn01 = vn + an*nts2`（半步外推估 $v_{k+1/2}$）→ 配合 L32 估出 $a_{k+1/2}$ → L34 中点法积分
> - "位置梯形积分" = L39 的 `Mpv*(vn+vn1)/2`（新旧速度取平均）→ L40 全步长积分

**为什么需要Mpv半步外推？**
Mpv中的RMh、RNh、cosL都是位置的函数。如果用t_k的L计算Mpv，一阶精度；如果用**半步位置L(t_{k+1/2})** 计算，二阶精度。所以L22用vn, an外推出pos01再更新eth。

---

### 3. 地球参数半步外推的精度机制

insupdate最精妙的"数值小技巧"集中在L22-L24：

**朴素做法（一阶精度）**：

$$
\text{直接用 } \mathbf{p}(t_k), \mathbf{v}^n(t_k) \text{ 算 } \boldsymbol{\omega}_{in}^n, \mathbf{g}_{cc}^n, \mathbf{M}_{pv}
$$

**PSINS做法（二阶精度，L22）**：

$$
\mathbf{v}^n_{01} = \mathbf{v}^n(t_k) + \mathbf{a}^n(t_k) \cdot \frac{T_s}{2}, \quad
\mathbf{p}_{01} = \mathbf{p}(t_k) + \mathbf{M}_{pv}(t_k) \cdot \mathbf{v}^n_{01} \cdot \frac{T_s}{2}
$$

用vn01, pos01调用`ethupdate`得到**半步时刻**的eth参数，再用这些参数做后续积分。本质是**预估-校正法**的预测步：先用旧状态预测半步状态，再用半步状态做高精度积分。

---

## 📝 逐行注释

insupdate共48行，**每一行详细注释，一行不落下**。标⚠️为关键易错行，标★为算法核心行。

| 行号 | 原代码 | 中文注释 | 公式/备注 |
|------|--------|----------|-----------|
| 1 | `function ins = insupdate(ins, imu)` | 函数定义：SINS机械编排更新。输入ins结构体（当前状态）、imu增量数组；输出更新后的ins结构体 | ins结构体字段非常重要，由insinit初始化 |
| 2 | `% SINS Updating Alogrithm including attitude, velocity and position` | 函数摘要：SINS更新算法，含姿态/速度/位置更新 | Alogrithm=Algorithm拼写（无伤大雅笔误） |
| 3 | `% updating.` | 续上一行摘要 |  |
| 4 | 空行 | 空行分隔 |  |
| 5 | `% Prototype: ins = insupdate(ins, imu)` | 函数原型说明 |  |
| 6 | `% Inputs: ins - SINS structure array created by function 'insinit'` | 输入说明：ins结构体由insinit创建 | 含qnb, att, Cnb, vn, pos, an, Mpv, eth等关键字段 |
| 7 | `%         imu - gyro & acc incremental sample(s)` | 输入说明：imu为陀螺/加计增量数据（n行×6列或3列） | 格式：每行=[wx,wy,wz, vx,vy,vz]，单位rad和m/s |
| 8 | `% Output: ins - SINS structure array after updating` | 输出说明：更新后的SINS结构体 | avp字段=[att;vn;pos]便于后续plot |
| 9 | 空行 | 空行分隔 |  |
| 10 | `% See also  insinit, cnscl, earth, inspure, trjsimu, imuadderr, avpadderr, q2att,` | 相关函数交叉引用上一行 | 核心调用：cnscl圆锥补偿、attsyn姿态同步、ethupdate地球参数更新 |
| 11 | `%           inslever, alignvn, aligni0, etm, kffk, kfupdate, insplot.` | 相关函数交叉引用下一行 |  |
| 12 | 空行 | 空行分隔 |  |
| 13 | `% Copyright(c) 2009-2014, by Gongmin Yan, All rights reserved.` | 版权声明，西工大严恭敏老师 |  |
| 14 | `% Northwestern Polytechnical University, Xi An, P.R.China` | 作者单位：西北工业大学 |  |
| 15 | `% 22/03/2008, 12/01/2013, 18/03/2014, 09/09/2014` | 版本日期：四次修订（2008初版→2014最终版） | 2014-11-30又在代码内注释中做了wnb和Mpvvn修改 |
| 16 | `global glv` | 声明全局变量glv | 主要用于cnscl内部（此处也间接需要） |
| 17 | `    nn = size(imu,1);` | 获取当前更新周期内的IMU子样数nn | nn=SINS更新频率÷IMU采样频率。例IMU100Hz+SINS10Hz→nn=10 |
| 18 | `    nts = nn*ins.ts;  nts2 = nts/2;  ins.nts = nts;` | 计算更新周期长度nts=子样数×单样间隔ins.ts；半步时间nts2；保存nts到ins结构体 | 单位：s。nts=T_s，nts2=T_s/2 |
| 19 | ⚠️ `    [phim, dvbm] = cnscl(imu,0);    % coning & sculling compensation` | ⚠️ **最关键第1行**：调用cnscl对IMU多子样做圆锥/划桨/旋转补偿。coneoptimal=0使用Miller最优补偿 | 输出phim(3×1,rad)=补偿后等效旋转矢量$\Delta\boldsymbol{\phi}_m$；dvbm(3×1,m/s)=补偿后速度增量$\Delta\mathbf{v}_{bm}$。注意：cnscl内部已完成"求和+三项补偿"，此处直接得到等价增量 |
| 20 | `    phim = ins.Kg*phim-ins.eb*nts; dvbm = ins.Ka*dvbm-ins.db*nts;  % calibration` | IMU标定补偿：陀螺刻度因子Kg×phim再减零偏eb×时间；加计刻度因子Ka×dvbm再减零偏db×时间 | 纯惯导仿真时Kg=I(3×3), eb=[0;0;0], Ka=I, db=[0;0;0]，所以恒等；实际含误差时标定在此处集中完成 |
| 21 | `    %% earth & angular rate updating ` | 分节：地球参数与角速度更新（半步外推部分） | %%为Matlab cell分隔 |
| 22 | ★ `    vn01 = ins.vn+ins.an*nts2; pos01 = ins.pos+ins.Mpv*vn01*nts2;  % extrapolation at t1/2` | ★ **核心半步外推**：用当前速度vn+加速度an×半步时间，线性外推出**半步时刻t_{k+1/2}的速度vn01**；再用旧Mpv×vn01×半步，外推出**半步位置pos01** | 公式：$\mathbf{v}_{01}=\mathbf{v}(t_k)+\mathbf{a}(t_k)\cdot T_s/2$；$\mathbf{p}_{01}=\mathbf{p}(t_k)+\mathbf{M}_{pv}(t_k)\mathbf{v}_{01}\cdot T_s/2$。这是二阶精度的关键一步——"预估"半步状态 |
| 23 | ⚠️ `    if ins.openloop==0, ins.eth = ethupdate(ins.eth, pos01, vn01);` | ⚠️ **条件外推**：默认模式openloop=0（闭环正常更新），用半步pos01和vn01更新地球参数eth到半步时刻 | eth内从此包含：半步RMh、半步RNh、半步cl=cosL、半步wnie=ω_ie（导航系投影）、半步wnen=ω_en（位移角速度）、半步wnin=ω_ie+ω_en、半步gcc=重力+科里奥利+离心合成。这是L22预测值的"消费方" |
| 24 | `    elseif ins.openloop==1, ins.eth = ethupdate(ins.eth, ins.pos0, ins.vn0); end` | openloop=1开环模式：不用半步外推，用初始时刻pos0和vn0更新eth（地球参数恒定，不随运动变化） | 用于误差特性分析：固定eth→消除"地球参数时变"这一耦合项，单独看纯惯导积分漂移 |
| 25 | `    ins.wib = phim/nts; ins.fb = dvbm/nts;  % same as trjsimu` | 由等效增量反算等效平均角速度wib（rad/s）= phim÷T_s；等效平均比力fb（m/s²）= dvbm÷T_s | 用于记录原始测量均值，与trjsimu.m生成的"真值"wib/fb格式一致，便于后续对比分析 |
| 26 | `    ins.web = ins.wib - ins.Cnb'*ins.eth.wnie;  ins.wbar = 0.9*ins.wbar + 0.1*ins.web;` | 计算机体系相对e系的角速度web = 陀螺输出wib - Cnb^T·wnie（wnie转到b系再扣除）；wbar做一阶低通平滑（α=0.1） | 平滑后wbar用于后续辅助功能（非纯惯导核心）。wnie是地球自转角速度ω_ie在n系投影 |
| 27 | `%     ins.wnb = ins.wib - ins.Cnb'*ins.eth.wnin;` | ⚠️ 旧版代码注释行：wnb旧算法 = wib − Cnb^T·wnin（wnin转到b系扣除）。但**精度略低**，因为wnin使用的是t_k时刻的Cnb，而非半步时刻 | 已弃用；新版见下一行 |
| 28 | `    ins.wnb = ins.wib - (ins.Cnb*rv2m(phim/2))'*ins.eth.wnin;  % 2014-11-30` | ★ **新版高精度wnb**：将姿态矩阵Cnb先向未来旋转半步（乘rv2m(phim/2)=I-[Δφ/2×]一阶近似旋转到t_{k+1/2}），再转置×wnin。即用**半步时刻的Cnb**来转wnin，与整体中点积分策略一致 | 公式：$\boldsymbol{\omega}_{nb}^b = \boldsymbol{\omega}_{ib}^b - \left( \mathbf{C}_{nb}(t_k) \cdot \mathbf{R}(\Delta\boldsymbol{\phi}_m/2) \right)^T \boldsymbol{\omega}_{in}^n(t_{k+1/2})$。这一修正2014-11-30加入，显著提高长航时精度 |
| 29 | `    %% (1)velocity updating` | 分节：**第1步——速度更新**。注意：PSINS顺序是"速度→位置→姿态"而非教科书上的"姿态→速度→位置"。先算新速度，才能在位置更新中用末速度做中点平均 | 顺序背后的思想：速度积分需要姿态（t_k时刻已有），位置积分需要新速度vn1，姿态更新最后做（更新完qnb/Cnb就是新的了，后续无使用） |
| 30 | ⚠️ `    ins.fn = qmulv(ins.qnb, ins.fb);` | ⚠️ 比力投影：用t_k时刻四元数qnb将机体系平均比力fb（加计输出）变换到导航系n下，得到fn | 公式：$\mathbf{f}^n = \mathbf{C}_{bn}(t_k) \bar{\mathbf{f}}_{sf}^b = \mathbf{qmulv}(\mathbf{Q}_{nb}(t_k), \bar{\mathbf{f}}_{sf}^b)$。qmulv=四元数旋转向量。注意此时fn是t_k时刻n系下的比力，还需要半步旋转补偿 |
| 31 | `%     ins.an = qmulv(rv2q(-ins.eth.wnin*nts2),ins.fn) + ins.eth.gcc;` | 旧版加速度计算注释行：用rv2q(-wnin·T_s/2)四元数旋转fn。功能同下一行rotv写法，等价但稍慢 | 已弃用 |
| 32 | ★ `    ins.an = rotv(-ins.eth.wnin*nts2, ins.fn) + ins.eth.gcc;  ins.anbar = 0.9*ins.anbar + 0.1*ins.an;` | ★ **速度更新核心行**：比力先做wnin半步旋转补偿→再加gcc有害加速度合成项→得到半步时刻的导航系比力加速度an。anbar做一阶低通平滑 | 公式：$\mathbf{a}^n(t_{k+1/2}) = \mathbf{R}\left(-\frac{\boldsymbol{\omega}_{in}^n T_s}{2}\right)\mathbf{f}^n(t_k) + \mathbf{g}_{cc}^n$。rotv的物理意义：wnin使n系在T_s内旋转了wnin·T_s，而fn是用区间起点姿态投影的，要近似到区间中点，需把fn**反向旋转一半角度**wnin·T_s/2。gcc=重力+科里奥利+离心，直接加，不用再乘-g！ |
| 33 | `%    ins.an(1:2)=ins.an(1:2)-2*0.207*glv.ws*ins.vn(1:2);` | 注释行：经验补偿（残差科里奥利手动微调系数），默认不启用 | 0.207系数来源不详，非标准算法 |
| 34 | ⚠️ `    vn1 = ins.vn + ins.an*nts;` | ⚠️ **新速度计算**：当前速度vn + 加速度an × 更新周期nts，得到更新后速度vn1 | 公式：$\mathbf{v}^n(t_{k+1}) = \mathbf{v}^n(t_k) + \mathbf{a}^n(t_{k+1/2}) \cdot T_s$。中点积分形式（an为半步估计值），截断误差O(T_s³)。**此处vn1是临时变量，先不赋值给ins.vn——因为位置更新还需要同时用旧vn和新vn1做中点平均** |
| 35 | `    %% (2)position updating` | 分节：**第2步——位置更新** | 需要用到旧速度ins.vn和新速度vn1 |
| 36 | `%     ins.Mpv = [0, 1/ins.eth.RMh, 0; 1/ins.eth.clRNh, 0, 0; 0, 0, 1];` | 旧版Mpv赋值注释行：整矩阵赋值。等价于下一行标量赋值 | clRNh=cosL·RNh。注意Mpv的索引：第1行→L变化，第2行→λ变化，第1列→vE输入，第2列→vN输入 |
| 37 | ⚠️ `    ins.Mpv(4)=1/ins.eth.RMh; ins.Mpv(2)=1/ins.eth.clRNh;` | ⚠️ **Mpv矩阵关键行**：只更新Mpv两个非零非1元素。Matlab列优先存储：Mpv=[M11,M21,M31, M12,M22,M32, M13,M23,M33]，所以Mpv(4)=M12=1/RMh，Mpv(2)=M21=1/(cl·RNh) | Mpv矩阵（n系v=[vE,vN,vU]→p_dot=[L_dot,λ_dot,h_dot]）：M(1,2)=1/RMh对应v_N→L_dot；M(2,1)=1/(cl·RNh)对应v_E→λ_dot。**必须特别小心Mpv(2,1)的cos(L)项，高纬度cosL很小，漏掉会导致λ_dot被放大1/cosL倍→经度飞快发散** |
| 38 | `%     ins.Mpvvn = ins.Mpv*((ins.vn+vn1)/2+(ins.an-ins.an0)*nts^2/3);  % 2014-11-30` | 旧版Mpvvn注释行：在速度中点平均基础上，加(an-an0)·T_s²/3的加速度二阶修正（类似辛普森积分余项） | 2014-11-30加入后**又被注释**，说明该项提升极微，为简化代码已弃用 |
| 39 | `    ins.Mpvvn = ins.Mpv*(ins.vn+vn1)/2;` | ★ **位置积分核心行**：旧速度ins.vn + 新速度vn1取平均（中点积分的梯形速度平均），再乘Mpv得位置变化率向量 | 公式：$\dot{\mathbf{p}}_{avg} = \mathbf{M}_{pv}(t_{k+1/2}) \cdot \frac{\mathbf{v}^n(t_k)+\mathbf{v}^n(t_{k+1})}{2}$。速度取前后平均=中点速度，配合半步Mpv→二阶精度 |
| 40 | ⚠️ `    ins.pos = ins.pos + ins.Mpvvn*nts;  ` | ⚠️ **新位置计算**：旧位置 + 位置变化率Mpvvn × 更新周期nts | 公式：$\mathbf{p}(t_{k+1}) = \mathbf{p}(t_k) + T_s \cdot \dot{\mathbf{p}}_{avg}$。注意Mpvvn量纲是[rad/s; rad/s; m/s]，乘时间s得到[rad; rad; m]，正是pos字段[L;λ;h]的单位。**不要写成×nts2！位置是全步长积分，半步已经体现在Mpv用了pos01和速度平均里** |
| 41 | `    ins.vn = vn1;` | 临时变量vn1写入ins.vn，完成速度更新 | 此时速度从"旧"变"新"，同步于位置更新完成 |
| 42 | `    ins.an0 = ins.an;` | 保存当前an到an0（下一步可能用，如L38注释的二阶修正） | 当前使用中an0只读不写，保留字段供扩展 |
| 43 | `    %% (3)attitude updating` | 分节：**第3步——姿态更新**。最后做：因为姿态更新完qnb/Cnb就变成新的了，后续不再使用 |  |
| 44 | `    ins.Cnb0 = ins.Cnb;` | 备份旧姿态矩阵Cnb到Cnb0（用于外部读取"更新前后姿态差"，如组合导航状态转移矩阵） | 纯惯导本身不使用Cnb0，仅作为对外接口字段 |
| 45 | `%     ins.qnb = qupdt(ins.qnb, ins.wnb*nts);  % lower accuracy than the next line` | 旧版姿态更新注释行：用wnb角速度×时间=简单旋转矢量，单步qupdt。精度**低于下一行**，因为wnb是平均角速度，无法表达圆锥不可交换项 | 已弃用 |
| 46 | ★ `    ins.qnb = qupdt2(ins.qnb, phim, ins.eth.wnin*nts);` | ★ **姿态更新最核心行**：使用双端输入四元数更新函数qupdt2——右乘phim（IMU旋转矢量，机体系相对惯性系的转动），左乘wnin·nts（导航系相对惯性系的转动补偿），一次性完成"加计姿态增量+扣除导航系旋转" | 公式实现：$\mathbf{Q}_{nb}(t_{k+1}) = \mathbf{Q}_{nb}(t_k) \otimes \mathbf{q}(\Delta\boldsymbol{\phi}_m) \otimes \mathbf{q}(-\boldsymbol{\omega}_{in}^n T_s)$。qupdt2内部按高精度等效旋转矢量→四元数转换（含泰勒展开高阶项）。注意：phim是b系相对i系，wnin·T_s是n系相对i系，两者通过四元数"右IMU+左地球"的相对关系消去i系得到b相对n的姿态变化 |
| 47 | ⚠️ `    [ins.qnb, ins.att, ins.Cnb] = attsyn(ins.qnb);` | ⚠️ **姿态同步**：调用attsyn函数，以qnb为基准，同步计算att欧拉角（pitch/roll/yaw，单位°）和Cnb方向余弦矩阵 | attsyn详见attsyn.m：输入4×1四元数→输出同一姿态的三种等价表示。**必做的原因**：qnb更新后att和Cnb是旧值，必须同步保证三者一致；且qnb做归一化（防止浮点累积失归一化）。归一化后的qnb模严格=1，否则后续qmulv/Cnb计算会错 |
| 48 | `    ins.avp = [ins.att; ins.vn; ins.pos];` | 汇总：将9×1状态向量[姿态3×1; 速度3×1; 位置3×1]合并为avp字段（attitude-velocity-position缩写） | avp是insplot绘图和外部数据读取的主要接口。att单位°，vn单位m/s，pos单位[rad;rad;m] |

---

## 🔍 断点调试建议

### 调试0：完整流程逐步手算（推荐新手必做）

**前置准备**：运行 `test_SINS_trj.m` 或 `trjsimu.m` 生成一条轨迹（或用insinit造初始状态），得到ins结构体和前一帧imu数据。

在insupdate L19设断点，运行到断住后，在Command Window手动执行以下每一步，并跟代码比较：

> 💡 **怎么读这些调试代码？——`_man` 变量是什么意思？**
>
> `_man` 后缀 = "manual"（手算的）。调试的套路是：
> 1. 代码已经执行到断点，此时代码里的变量（如 `ins.fn`、`vn1`）已经有了值
> 2. 你在 Command Window 里**用同样的公式手算一遍**，存到 `xxx_man` 变量里
> 3. 用 `norm(代码变量 - 手算变量)` 比对，如果 <1e-14 说明你理解的公式和代码一致
>
> | 代码里的变量 | 你手算的变量 | 对应关系 | 比对命令 |
> |---|---|---|---|
> | `phim`（L19 代码算出来的） | `phim2`（你手动调 cnscl 算的） | 同一个公式，两次计算 | `norm(phim - phim2)` |
> | `ins.fn`（L30 代码算出来的） | `fn_man`（你用 qmulv 手算的） | 同一个公式 | `norm(ins.fn - fn_man)` |
> | `ins.an`（L32 代码算出来的） | `an_man`（你用 rotv+gcc 手算的） | 同一个公式 | `norm(ins.an - an_man)` |
> | `vn1`（L34 代码算出来的） | `vn1_man`（你用 vn+an*nts 手算的） | 同一个公式 | `norm(vn1 - vn1_man)` |
>
> **核心思想**：代码算了一遍，你再手算一遍，两个结果一致 → 说明你理解对了。如果不一致 → 说明你的公式理解和代码不同，要找哪里想错了。

**步骤A——圆锥补偿验证（对照02_cnscl.md练习）**：
```matlab
% 命中断点后
[phim2, dvbm2] = cnscl(imu, 0);   % 手动调用cnscl
norm(phim - phim2)  % 应当 <1e-15，说明L19输入输出关系正确
```

**步骤B——初始量检查**：
```matlab
% 断点停在L20之后，L21之前
nts_exp = size(imu,1) * ins.ts;   % 手算nts
abs(nts_exp - nts) < 1e-12        % 验证L18
% 检查ins.an, ins.vn初始字段存在
keyboard
```

**步骤C——半步外推L22手算验证**：
```matlab
vn01_man = ins.vn + ins.an * nts2;
pos01_man = ins.pos + ins.Mpv * vn01_man * nts2;
norm(vn01 - vn01_man)  % <1e-15
norm(pos01 - pos01_man)  % <1e-15
```

**步骤D——速度更新L30-L34手算**：
```matlab
% L30 比力投影
% dvbm/nts = 速度增量/时间 = 比力 fb（和 L25 的 ins.fb 等价）
fn_man = qmulv(ins.qnb, dvbm/nts);  % 用 dvbm/nts 更直观：展示了 fb 的来源
norm(ins.fn - fn_man)  % <1e-14
% L32 速度更新加速度
wnin_half = - ins.eth.wnin * nts2;
fn_rot = rotv(wnin_half, fn_man);
an_man = fn_rot + ins.eth.gcc;
norm(ins.an - an_man)  % <1e-14
% L34 新速度
vn1_man = ins.vn + an_man * nts;
norm(vn1 - vn1_man)  % <1e-14
```

**步骤E——位置更新L36-L40手算**：
```matlab
% L37 Mpv构造
Mpv_man = zeros(3);
Mpv_man(1,2) = 1/ins.eth.RMh;
Mpv_man(2,1) = 1/ins.eth.clRNh;  % clRNh = cosL * RNh
Mpv_man(3,3) = 1;
norm(ins.Mpv - Mpv_man, 'fro')  % 非零元素应<1e-15
% L39 位置变化率
Mpvvn_man = Mpv_man * (ins.vn + vn1_man) / 2;
norm(ins.Mpvvn - Mpvvn_man)  % <1e-15
% L40 新位置
pos_man = ins.pos + Mpvvn_man * nts;
```

**步骤F——姿态更新L44-L47手算**：
```matlab
% L46 qupdt2展开
qnb_man = qupdt(qupdt(ins.qnb, phim),  -ins.eth.wnin*nts);
% 注意qupdt2的顺序和精度更高，但差应<1e-12
[qnb2, att2, Cnb2] = attsyn(qnb_man);
norm(q2mat(ins.qnb) - q2mat(qnb2), 'fro')  % <1e-10
```

---

### 调试1：去掉半步外推看精度差（配套练习预演）

在insupdate L22设断点，命中断点后手动强制：
```matlab
vn01 = ins.vn;    % 不外推，直接用旧速度
pos01 = ins.pos;  % 不外推，直接用旧位置
dbstep in 2;      % 单步跳入ethupdate，观察输入就是旧pos/vn
```
跑完600s后位置RMS明显增大——此即L22半步外推的价值。

---

## ❌ 初学者最容易踩的坑

### 坑①：Mpv(2,1)漏掉cos(L)，高纬度经度飞速发散

**表现**：修改Mpv时按直觉写 `Mpv(2,1)=1/RNh`（忘记除以cosL），在纬度L=70°仿真时经度λ 600s内漂移几十度，正常应当几海里。

**为什么错**：纬线（东向行驶）所在的平行圆半径不是RNh，而是**RNh·cos(L)**！东向行驶1 m对应的经度变化不是1/RNh rad，而是1/(RNh·cosL) rad。在L=70°，cosL≈0.342，所以漏掉cosL会导致经度变化率被放大约2.92倍——短期就明显偏，长期发散。

**验证**：L=0°（赤道）cosL=1没问题；L=80°cosL≈0.1736→漏除以放大5.76倍→几小时就漂一圈。

---

### 坑②：姿态更新四元数左乘(-wnin)和右乘(phim)顺序写反

**表现**：自行改写insupdate时写成 `qnb = qmul(rv2q(-wnin*nts), qmul(qnb, rv2q(phim)))`（wnin乘在qnb左边而不是右边），结果姿态漂移超快，10°/h以上。

**为什么错**：四元数姿态的物理定义是"n→b的旋转"：

$$
\mathbf{r}^b = \mathbf{Q}_{nb} \otimes \mathbf{r}^n \otimes \mathbf{Q}_{nb}^*
$$

IMU增量$\Delta\boldsymbol{\phi}_m$是**b系本身的旋转**（体固连），所以要**从右侧乘**$\mathbf{Q}_{nb}$：

$$
\mathbf{Q}_{nb}' = \mathbf{Q}_{nb} \otimes \mathbf{q}(\Delta\boldsymbol{\phi}_m)
$$

而wnin·T_s是**n系本身的旋转**（导航系在惯性空间转动了一个角度），我们需要把Qnb调整为"新n→旧b→新b"之间的新关系，对应**右侧再乘一个反向旋转**：

$$
\mathbf{Q}_{nb,\text{new}} = \mathbf{Q}_{nb} \otimes \mathbf{q}(\Delta\boldsymbol{\phi}_m) \otimes \mathbf{q}(-\boldsymbol{\omega}_{in}^n T_s)
$$

左右顺序错 = 把坐标系旋转作用在错误的参考系 = 姿态漂移量级等于ω_ie·T≈15°/h完全没补偿。

---

### 坑③：ins.an里gcc已包含重力+科里奥利+离心，又额外加-g

**表现**：为了"加重力"在L32后面补写 `ins.an(3) = ins.an(3) - 9.8`，结果高度h在几十秒内从0掉到几百米，速度天向vU快速累积负号。

**为什么错**：gcc字段（重力+科里奥利+离心合成项）是这样定义的（参考earth.m/ethupdate.m）：

$$
\mathbf{g}_{cc} = \mathbf{g}_{l}^n - (2\boldsymbol{\omega}_{ie}^n + \boldsymbol{\omega}_{en}^n) \times \mathbf{v}^n - \boldsymbol{\omega}_{ie}^n \times (\boldsymbol{\omega}_{ie}^n \times \mathbf{r})
$$

其中$\mathbf{g}_l^n$是"正常重力"，方向沿ENU的U轴负方向，NED惯例下是正z（地向）。PSINS中gcc在NED下已经是"应该加到速度微分上的全部有害加速度"——不需要再手动加任何-g项。再减一次9.8等于把重力算了两遍，方向相反地叠加，直接把天向速度"向下加速"。

---

### 坑④（补充）：vn1先覆盖ins.vn再做位置更新，丢失中点速度

**表现**：把L34 `vn1 = ins.vn + ins.an*nts;` 直接写成 `ins.vn = ins.vn + ins.an*nts;`，然后L39里`(ins.vn+vn1)/2`改成`ins.vn`，结果位置RMS变大。

**为什么错**：位置积分中点平均需要用到**旧速度(t_k)和新速度(t_{k+1})的平均值**。如果先覆盖ins.vn就丢了t_k的速度值，只剩t_{k+1}。梯形法则变成左矩形法则，精度降一阶，误差O(T_s²)而非O(T_s³)。

---

## 🎯 配套练习

### 练习题：去掉L22半步外推，看全程RMS退化多少

**题目**：将insupdate中第22行 `vn01 = ins.vn+ins.an*nts2; pos01 = ins.pos+ins.Mpv*vn01*nts2;` 修改为直接用旧状态：
```matlab
vn01 = ins.vn;   % 不外推，用t_k时刻速度代替t_{k+1/2}
pos01 = ins.pos; % 不外推，用t_k时刻位置代替t_{k+1/2}
```
然后运行PSINS自带的标准算例（如 `test_SINS.m` 或 `test_SINS_trj.m` 生成600 s轨迹），对比修改前后**全航段位置均方根误差（RMS）**的差异，体会"半步外推"这个小数值技巧带来的精度收益。

**实验步骤**：

1. **备份原版insupdate**：
```bash
cd /workspace/psins/base/base1
cp insupdate.m insupdate_original.m
```

2. **修改insupdate.m L22**（直接用Edit工具）：把vn01和pos01外推替换为旧状态直接赋值（即把预估步跳过，相当于一阶精度）。

3. **跑原版基线baseline**：先恢复original版本跑一遍，保存结果：
```matlab
% 在Matlab命令行
% 先切到原版文件（如果已经改过，用cp覆盖回）
! cp insupdate_original.m insupdate.m
run('test_SINS.m');  % 假设会生成trj真值和SINS解算结果inserr
% 保存误差RMS
rms_pos_baseline = sqrt(mean(inserr.pos_err.^2, 1));  % 3×1向量 [N;E;U] 误差RMS，单位m
fprintf('【原版】位置RMS N/E/U = %.3f / %.3f / %.3f m\n', rms_pos_baseline);
rms_3d_baseline = norm(rms_pos_baseline);
save /tmp/ins_baseline.mat ins err rms_pos_baseline rms_3d_baseline;
```

4. **跑修改版本（无半步外推）**：
```matlab
% 修改L22为vn01=ins.vn; pos01=ins.pos;后
run('test_SINS.m');
rms_pos_modified = sqrt(mean(inserr.pos_err.^2, 1));
rms_3d_modified = norm(rms_pos_modified);
fprintf('【修改】位置RMS N/E/U = %.3f / %.3f / %.3f m\n', rms_pos_modified);
fprintf('【退化倍数】3D RMS = %.2f 倍 (原版%.2f → 修改后%.2f)\n', ...
    rms_3d_modified / rms_3d_baseline, rms_3d_baseline, rms_3d_modified);
```

5. **预期结果分析**：
   - 短航段（60s内）：退化可能不明显，RMS增幅<5%，因为半步外推是二阶项，小T_s下T_s²很小。
   - 600s中长航段：**3D RMS通常退化1.3～2.5倍**。因为每一步误差O(T_s²)累计，随时间T（而非T²）增长。在高动态转弯或变加速运动场景下退化更严重（>3倍），因为an本身快速变化，旧an与半步an偏差大。
   - 高纬度（L>60°）和高航速（>300m/s）下退化显著，因为wnin和Mpv对位置强敏感。

6. **进阶思考题**：如果把L22改成"vn01用外推但pos01不用"，或"pos01外推vn01不用"，分别跑一次，看哪一项的贡献更大？（提示：位置积分Mpv中RMh/RNh随纬度变化慢，主要由vn01驱动的外推更关键；但高动态下两者都重要）

---

## 📎 附录 A：飞控 vs 惯导——解算策略对比

> 这个附录是为做 MEMS 飞控/低精度惯导的读者写的。虽然我们在拆解 PSINS（200Hz、二阶精度、全状态解算），但很多读者实际做的是 1kHz+ 的 MEMS 系统，甚至只做姿态解算。这里把两者的工程取舍讲清楚。

### A.1 解算什么？——取决于你的应用

| 飞控/系统 | 解算什么 | 顺序 | 为什么 |
|---|---|---|---|
| **Betaflight / Cleanflight**（穿越机） | **只解算姿态** | — | 只管姿态稳定，位置靠遥控器目视 |
| **PX4 / Ardupilot**（飞控层） | **只解算姿态**（姿态控制器） | — | 姿态环 400Hz，位置/高度靠 GPS+气压计单独做 |
| **PX4 EKF2/EKF3**（导航层） | 姿态+速度+位置 | EKF 一次矩阵乘，无顺序 | 用卡尔曼滤波不是机械编排，$\Phi \cdot \mathbf{x}$ 一步全推 |
| **PSINS**（惯导工具箱） | 姿态+速度+位置 | 速度→位置→姿态 | 机械编排，有明确的数值积分顺序 |

**为什么飞控只解算姿态？**

- 多旋翼/固定翼的**位置靠 GPS**，不需要惯导位置推算（MEMS 位置漂移 1km/h，飞 10 分钟就漂 10km，没用）
- 但**姿态必须高频更新**（400Hz+），否则飞机翻过来都来不及纠正
- 所以飞控的核心是"陀螺+加计 → 姿态"，位置交给 GPS

### A.2 "姿态→速度→位置" vs "速度→位置→姿态"——先算姿态会怎样？

关键在于：**速度更新需要姿态来投影比力，用旧姿态还是新姿态？**

| 方案 | 顺序 | 速度更新用的姿态 | 精度 |
|---|---|---|---|
| **PSINS** | 速度→位置→姿态 | 旧姿态 $C_{nb}(t_k)$ + rotv 半步补偿 | 二阶 $O(T_s^3)$ |
| **先姿态** | 姿态→速度→位置 | 新姿态 $C_{nb}(t_{k+1})$ | **等价于一阶**（用区间末点，类似后向欧拉） |

**先算姿态会怎样？** 如果先更新姿态得到 $C_{nb}(t_{k+1})$，再用它投影比力算速度，相当于用区间**末点**的姿态代表整个区间——这是后向欧拉，只有一阶精度 $O(T_s^2)$。要达到二阶精度，还得做半步补偿（用 $C_{nb}(t_{k+1/2})$ 而非 $C_{nb}(t_{k+1})$），那就又回到 PSINS 的思路了。

> **一句话**：PSINS 用"旧姿态 + rotv 半步旋转"达到二阶精度；先算姿态用"新姿态"只有一阶精度，要二阶还得补偿半步——绕了一圈又回来了。**但如果你只做姿态解算（不关心速度/位置），那"先姿态"就是唯一选择，没有这个问题。**

### A.3 飞控的姿态积分方法——和 PSINS 对照

以下是飞控嵌入式场景常见的姿态积分方法，和 PSINS 对照：

| 方法 | 公式 | 精度 | 飞控用的？ | PSINS 的对应 |
|---|---|---|---|---|
| **① 一阶欧拉** | $\mathbf{q}_{k+1} = \mathbf{q}_k + \frac{1}{2}\mathbf{q}_k \otimes \bar{\boldsymbol{\omega}}^b \cdot \Delta t$ | $O(\Delta t^2)$ | ✅ 1-8kHz 飞控主循环 | PSINS 旧版 L45 注释行 `qupdt(qnb, wnb*nts)` |
| **② 中点法/RK2** | $\mathbf{q}_{k+1} = \mathbf{q}_k + \frac{\Delta t}{2}(\dot{\mathbf{q}}_k + \dot{\mathbf{q}}_{k+1/2})$ | $O(\Delta t^3)$ | 少用（需半步姿态） | PSINS 没用（和速度更新一样的困境） |
| **③ 旋转矢量法** | $\Delta\mathbf{q} = \begin{bmatrix}\cos(\frac{|\Delta\boldsymbol{\theta}|}{2})\\\frac{\Delta\boldsymbol{\theta}}{|\Delta\boldsymbol{\theta}|}\sin(\frac{|\Delta\boldsymbol{\theta}|}{2})\end{bmatrix}, \quad \mathbf{q}_{k+1}=\mathbf{q}_k\otimes\Delta\mathbf{q}$ | 精确（单步内） | ✅ 低频场景 | ✅ **就是 PSINS 的 rv2q** |

#### 飞控选①一阶欧拉的工程理由

- IMU 输出 1-8kHz，$\Delta t$ 极小（0.125-1ms）
- 一阶欧拉截断误差 $\sim O(\Delta t^2)$，在 $\Delta t = 0.125$ ms 下 $\sim 1.6 \times 10^{-8}$，**已经远小于 MEMS 陀螺本身的噪声**
- 算力有限（STM32 F4/H7），每步省一次叉乘+归一化就是省几百周期
- **圆锥误差在 8kHz 下可忽略**：$(\omega h)^2 \sim (5° \times 0.000125)^2 \sim 4 \times 10^{-10}$ rad² → 比陀螺零偏小 6 个数量级

#### 积分后必须归一化

$$\mathbf{q} \leftarrow \frac{\mathbf{q}}{\|\mathbf{q}\|} = \frac{\mathbf{q}}{\sqrt{q_0^2+q_1^2+q_2^2+q_3^2}}$$

浮点累积会导致 $\|\mathbf{q}\| \neq 1$，不归一化后续所有旋转计算都会带误差。PSINS 在 [attsyn.m](file:///workspace/psins/base/base1/attsyn.m) 里做归一化（L47），飞控在每次积分后做。

> **快速逆平方根**（飞控嵌入式技巧）：归一化需要算 $1/\sqrt{x}$，经典方法用"魔数"近似（Quake III 源码中的 `0x5f3759df`），一次牛顿迭代即达浮点精度。PSINS 在 MATLAB 里不需要这个（直接 `q/norm(q)`）。

### A.4 飞控姿态积分 vs PSINS 姿态更新——关键区别

| | 飞控①一阶欧拉 | PSINS qupdt2 |
|---|---|---|
| 输入 | $\boldsymbol{\omega} \cdot \Delta t$（单子样，直接乘） | $\boldsymbol{\phi}_m$（经 cnscl 多子样补偿） |
| 圆锥补偿 | ❌ 没有 | ✅ 有 $\frac{2}{3}\mathbf{wm}_1 \times \mathbf{wm}_2$ |
| 导航系补偿 | 通常不做（或不做地球自转） | ✅ 左乘 $-\boldsymbol{\omega}_{in}^n T_s$ |
| 频率 | 1-8kHz | 100-200Hz |
| 适用 | 飞控姿态稳定 | 惯导全状态解算 |

> **关键直觉**：飞控 8kHz 下圆锥误差 $(\omega h)^2$ 项可以忽略，一阶欧拉 + 归一化就够了。但放到 PSINS 的 100-200Hz 场景，就**必须加圆锥补偿**，否则高动态下姿态会漂。**方法没有好坏，只有"频率+精度要求+算力"的取舍。**

### A.5 卡尔曼滤波 vs 机械编排——到底谁在"算导航"？

> 常见疑问："卡尔曼滤波不是滤波/融合数据用的吗？怎么还能用来惯导解算？"
>
> 你说得对——**KF 是滤波/融合用的，惯导解算靠的是机械编排。** 但不同系统的架构选择不同，这里讲清楚。

#### 两个概念

| | 机械编排（Mechanization） | 卡尔曼滤波（KF） |
|---|---|---|
| **干什么** | 用 IMU 数据推算姿态/速度/位置 | 用 GNSS/ODO 等外部量测修正误差 |
| **输入** | 陀螺+加计原始数据 | 机械编排的结果 + 外部量测 |
| **输出** | 导航解（att, v, pos） | 误差估计（δatt, δv, δpos, 零偏...） |
| **公式** | $\dot{\mathbf{v}}^n = \mathbf{C}_b^n \mathbf{f} + \mathbf{g}_{cc} - (2\boldsymbol{\omega}_{ie}^n+\boldsymbol{\omega}_{en}^n)\times \mathbf{v}^n$ | $\mathbf{x}_{k+1} = \Phi \mathbf{x}_k$, $\mathbf{K} = \mathbf{P}\mathbf{H}^T(\mathbf{H}\mathbf{P}\mathbf{H}^T+\mathbf{R})^{-1}$ |
| **PSINS 里** | [insupdate.m](file:///workspace/psins/base/base1/insupdate.m) | [kfupdate.m](file:///workspace/psins/base/kf/kfupdate.m) + [kffeedback.m](file:///workspace/psins/base/kf/kffeedback.m) |

#### PSINS 的做法：机械编排 + KF 分开

```
    IMU数据
      ↓
  insupdate.m        ← 机械编排：算出姿态/速度/位置（会漂移）
      ↓
  kfupdate.m          ← KF：拿 GNSS 量测和 insupdate 的结果对比
      ↓                   → 估出误差（δatt, δv, δpos, 零偏...）
  kffeedback.m        ← 反馈：把误差扣回 ins 结构体
      ↓
  修正后的姿态/速度/位置（不再漂移）
```

**机械编排是"干活的主力"，KF 是"纠偏的监工"。** KF 不算导航解——它只估误差，然后反馈给机械编排去修正。

#### PX4 EKF2 的做法：合并成一个 EKF

PX4 EKF2 把所有状态（姿态+速度+位置+零偏）放进一个 24+ 维的状态向量，**用 EKF 的预测步直接推演所有状态**：

$$\mathbf{x}_{k+1} = \Phi \cdot \mathbf{x}_k \quad (\text{含姿态、速度、位置、零偏一起推})$$

这里 $\Phi$ 里的姿态更新部分**用的还是同一套物理方程**（四元数微分、比力方程），只是写成状态空间形式。**物理没有变，代码结构变了。**

#### 对比表

| | PSINS | PX4 EKF2 |
|---|---|---|
| **机械编排** | ✅ 独立的 insupdate.m | ❌ 没有独立模块 |
| **谁推算导航解** | insupdate（机械编排） | EKF 预测步 $\Phi \cdot \mathbf{x}$ |
| **KF 的角色** | 只估误差，反馈给机械编排 | 直接推算+修正全状态 |
| **导航解从哪来** | insupdate 的输出 | EKF 状态向量本身 |
| **优点** | 机械编排和 KF 职责清晰，便于调试 | 一个模块搞定，状态一致性有保证 |
| **缺点** | 两个模块要同步 | 调试时难分"是机械编排错了还是 KF 错了" |

> **一句话**：PSINS = 机械编排（insupdate）+ KF（kfupdate）**分开做**；PX4 EKF2 = 把两者**合并成一个 EKF**。物理一样，代码架构不同。**PX4 并没有"用 KF 代替机械编排"，而是把机械编排的方程塞进了 KF 的预测模型里。**

---

## 📎 附录 B：半步外推不是"鸡生蛋"——$a_k$ 来自上一拍

### 常见疑问

"半步外推需要 $a_{k+1/2}$，但 $a_{k+1/2}$ 不也要算吗？这不就是鸡生蛋蛋生鸡？"

**不是！关键在于 $a_k$ 是上一拍已经算好的，不是本拍要算的。**

### 数据流图

```
上一拍 L32: 算出 a_k，存到 ins.an     ← 已知！不是本拍算的
    ↓
本拍 L22: v_{k+1/2} = v_k + a_k × T_s/2   ← 用上一拍的 a_k 外推
         p_{k+1/2} = p_k + Mpv × v_{k+1/2} × T_s/2
    ↓
本拍 L23: eth(t_{k+1/2}) = ethupdate(p_{k+1/2}, v_{k+1/2})  ← 半步地球参数
    ↓
本拍 L30: f^n = C_nb(t_k) × f^b          ← 用旧姿态投影比力
    ↓
本拍 L32: a_{k+1/2} = rotv(-wnin×T_s/2, f^n) + gcc(t_{k+1/2})
         ← 用旧姿态 + 半步地球参数 + rotv旋转 = 真正的 a_{k+1/2}
    ↓
本拍 L34: v_{k+1} = v_k + a_{k+1/2} × T_s   ← 中点法积分
```

**没有循环依赖**：$a_k$ 来自上一拍的 L32（存在 `ins.an` 里），不是本拍要算的。本拍用 $a_k$ 做半步外推 → 得到半步地球参数 → 再用旧姿态 + rotv 算出真正的 $a_{k+1/2}$。

> **梯形法**需要 $a_{k+1}$（**本拍算不出来的未来值**）→ 死路
> **中点法**需要 $a_{k+1/2}$（**用上一拍的 $a_k$ 外推得到的**）→ 活路
