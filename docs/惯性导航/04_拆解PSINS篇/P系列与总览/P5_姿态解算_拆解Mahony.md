# P5 姿态解算 · 拆解 Mahony（AHRS）

> **定位**：P1–P4 走的是"惯导解算"主线（机械编排 → DR → KF 组合），本篇补上另一条腿——**姿态解算（AHRS）**：只用陀螺 + 加计 + 磁力计，不需要 GNSS、不积分位置，就能持续输出姿态。这是 AHRS 板（如本项目 STM32H743 + ICM42688P/BMI088/IST8310）上电后最先跑起来的算法。
>
> **miniins 里程碑 M-A**：新增 `ahrsinit / triad / quest / magsimu / mahonyupdate` 五个函数与 `verify_ahrs`（6 项自检全 PASS），本篇公式编号 6.x 与代码注释一一对应。

> [!note] 来源与可靠性说明
> - ✅ Wahba 问题 / TRIAD / QUEST / Mahony 滤波均为文献标准算法，公式与 [Shuster 1981（Wahba）]、[Mahony et al. 2008] 一致，本站已数值验证；
> - ✅ 本篇代码为 miniins 自写实现（`assets/miniins/core/`），全部经过 `verify_ahrs` 确定性回归（误差 1e-15 量级）；
> - ✅ 对标 PSINS 源码 `assets/psins260314/base/AHRS/MahonyUpdate.m`（对照表见第 4 节）；
> - ⚠️ 教学版有意简化：未实现 PSINS 的自适应 tau 与 IIR 低通，差异与影响见第 6 节。

## 0. 一图看懂：姿态解算在导航体系里的位置

```text
惯导解算（P1-P4）：  陀螺 ──姿态更新──┐
                    加计 ──速度/位置──┴──→ 姿态+速度+位置（漂移，需 KF/GNSS 修）
姿态解算（本篇）：    陀螺（高频，积分）──┐
                    加计（低频，定水平）─┼──→ 只有姿态（不漂移的"互补"组合）
                    磁力计（低频，定航向）┘
```

核心思想一句话：**陀螺积分短期极准但会漂，加计/磁力计长期不漂但噪声大、且机动时不可信——把高频信号给陀螺、低频信号给加计/磁，就是"互补滤波"**。

## 1. 符号表

| 符号 | 含义 | 单位/约定 |
|------|------|-----------|
| $q,\ \boldsymbol{q}=[q_0;q_1;q_2;q_3]$ | 姿态四元数（体→导航，标量在前） | Hamilton 序 |
| $C_b^n$ | 姿态阵（体→导航），`q2cnb(q)` | 3×3 正交阵 |
| $\mathrm{att}=[\theta_r;\phi_r;\psi]$ | 姿态角 [pitch; roll; yaw]，pitch 绕 x、roll 绕 y、yaw 绕 z | 弧度 |
| $f_b$ | 加计比力（体） | m/s²，静止时 ≈ 天向 g |
| $\boldsymbol{m}_b,\ \boldsymbol{m}_n$ | 磁测量（体）/ 地磁向量（导航 ENU） | nT |
| $e$ | Mahony 误差向量（体） | rad 量纲 |
| $K_p,\ K_i$ | 比例/积分增益 | 1/s |
| $m_H,\ \Theta_{dip},\ D_{dec}$ | 地磁水平强度 / 磁倾角 / 磁偏角 | nT / rad / rad |

机体系约定与全库一致：**x 右、y 前、z 上**（非航空 NED），见 [00 读码地基](00_读码地基.md)。

## 2. 静态定姿：Wahba 问题

### 2.1 问题描述（公式 6.0）

手头有 N 对"观测/参考"向量（体坐标系测到的 vs 导航系里已知的），求姿态阵：

$$
\min_{C_b^n \in SO(3)} \; L\big(C_b^n\big) = \sum_{i=1}^{N} w_i \,\big|\, \boldsymbol{n}_i - C_b^n\, \boldsymbol{b}_i \,\big|^2
$$

两对典型的"天造地设"的向量对：

- **加计 ↔ 重力**：准静态下加计测的是比力 $f_b \approx C_b^{nT}\,[0;0;g]$，参考向量就是导航系天向 $[0;0;1]$；
- **磁力计 ↔ 地磁**：体磁 $m_b$，参考是导航系地磁向量 $\boldsymbol{m}_n$（第 3 节）。

### 2.2 TRIAD：两矢量的确定性解（公式 6.1）

第一对向量定"天向"（管 pitch/roll），第二对只贡献绕天向的转角（管 yaw）——用叉乘构造两个正交标架，姿态阵就是标架间的投影：

$$
C_b^n = T_n\, T_b^{\,T}, \qquad
T_b = \big[\, \hat{b}_1,\ \widehat{b_1 \times b_2},\ \hat{b}_1 \times \widehat{b_1 \times b_2} \,\big]
$$

$T_n$ 用参考向量同构构造。代码 `triad.m` 逐行对应；实现要点：第 2 列里与第 1 列平行的分量会被叉乘自动丢弃——**TRIAD 无条件相信第 1 列**。

### 2.3 QUEST / Davenport q-方法：加权最小二乘（公式 6.1'）

观测有噪声、或想给不同传感器配权重时，把 Wahba 损失改写成 4×4 矩阵最大特征值问题：

$$
B = \sum_i w_i\, \boldsymbol{n}_i \boldsymbol{b}_i^{\,T}, \qquad
K = \begin{bmatrix} \sigma & \boldsymbol{Z}^T \\ \boldsymbol{Z} & S - \sigma I \end{bmatrix}, \quad
\sigma = \mathrm{tr}(B),\ S = B + B^T,\ \boldsymbol{Z} = \textstyle\sum_i w_i (\boldsymbol{n}_i \times \boldsymbol{b}_i)
$$

$K$ 的最大特征值对应的特征向量即最优四元数。⚠️ **约定坑**（数值对拍确认，err 1e-15）：$B=\sum w_i\,\boldsymbol{n}_i\boldsymbol{b}_i^T$ 构造下 Davenport 原生特征向量旋转方向是"参考→体"，本库体→导航约定需取**共轭**——`quest.m` 末行 `qnb = qconj(q)` 就是这一步。

## 3. 地磁场模型与磁参考（公式 6.5）

导航系（ENU）地磁向量由三个标量完全描述：

$$
\boldsymbol{m}_n = \begin{bmatrix} m_H \sin D_{dec} \\ m_H \cos D_{dec} \\ -m_H \tan \Theta_{dip} \end{bmatrix}
\qquad \xrightarrow{\ \text{投到体系}\ } \qquad
\boldsymbol{m}_b = C_b^{nT}\, \boldsymbol{m}_n
$$

- **磁倾角** $\Theta_{dip}$（北京 ≈ +58°）：磁力线扎向地面的角度，北半球天分量为负；
- **磁偏角** $D_{dec}$（北京 ≈ −7°）：磁北 ≠ 真北！**不补偿它，yaw 会系统性偏差 −$D_{dec}$**（见第 6 节实战坑 ①）；
- 真实磁强计还有**硬铁**（安装平台剩磁，表现为固定体偏置）与**软铁**（随姿态变化的畸变）干扰——本教学版只注入硬铁偏置，软铁留到标定篇。

## 4. Mahony 互补滤波（核心）

### 4.1 误差向量：用叉乘"量出"姿态误差（公式 6.2）

同一物理方向（如重力天向）有两个版本：当前姿态**预测**的、传感器**实测**的。两个近似单位向量叉乘，模 ≈ 夹角、方向 = 把预测转到实测所需的旋转轴——天然就是姿态误差向量：

$$
\boldsymbol{e} = \lambda \cdot \big( C_b^n(3,:)^{T} \times \hat{\boldsymbol{f}}_b \big) \;+\; \big( \hat{\boldsymbol{m}}_{b,\text{pred}} \times \hat{\boldsymbol{m}}_b \big)
$$

- 第一项（加计）：$C_b^n$ 第 3 行 = 导航天向在体系的投影（预测的"上"），叉乘实测比力方向；
- 第二项（磁）：预测体磁由实测磁投到导航系、**强制水平化并指向磁北**（只取磁航向，防磁倾角污染 pitch/roll）、再投回体系；
- $\lambda$ 为**准静态门控**：$|\,\|f_b\| - g\,| < 0.05$ 全信加计（λ=1），> 0.2 全不信（λ=0），中间线性过渡。

### 4.2 PI 反馈与姿态更新（公式 6.3、6.4）

$$
\dot{\boldsymbol{e}}_I = K_i\, \boldsymbol{e}, \qquad \boldsymbol{\omega}_{corr} = K_p\, \boldsymbol{e} + \boldsymbol{e}_I
$$

$$
\boldsymbol{q}^{+} = \boldsymbol{q} \otimes \mathrm{rv2q}\Big( \boldsymbol{\varphi}_m - \big( C_b^{nT}\, \boldsymbol{\omega}_{ie} + \boldsymbol{\omega}_{corr} \big)\, \Delta t \Big)
$$

与惯导机械编排（公式 4.5）对比只差一处：右乘的体轴增量里除了陀螺积分，还减去了 **PI 反馈项**——误差大时拉得快（$K_p$），误差积分项稳态时恰好抵消**陀螺零偏**（$K_i$，verify_ahrs ③ 实测 300 s 后 `exyzInt/eb = [1.00 1.00 1.00]`）。

注意减 $C_b^{nT}\omega_{ie}$：陀螺测的是相对惯性系的旋转，姿态相对地球，必须扣掉地球自转（公式 3.3）。

### 4.3 与 PSINS `MahonyUpdate.m` 逐项对照

| 环节 | PSINS（`base/AHRS/`） | miniins（本库） | 说明 |
|------|----------------------|----------------|------|
| 加计误差 | `cros(Cnb(3,:)', acc)` | `cross(Cbn(3,:)', acc)` | 完全一致（第 3 行 = 天向在体系） |
| 磁参考 | `bxyz(1:2)=[0;norm]` 水平朝**真北** | 水平指向**磁北**（`sin(dec);cos(dec)`） | miniins 显式补磁偏角，PSINS 由数据侧保证 |
| 加计可信度 | 自适应 tau（3→10→3×10⁵ s）+ IIR 低通 | 准静态门控 λ（0.05/0.2 线性） | 思路同源；PSINS 更平滑，教学版更直观 |
| PI 结构 | `exyzInt` + `Kp·e` | 相同 | 增益量级一致（Kp≈1–2，Ki≈0.1–1） |
| 姿态更新 | `qmul(q, rv2q(phim−eb·ts))` | `qmul(qnb, rv2q(phim−(CbnT·ωie+eb)·ts))` | miniins 把地球自转补偿并入同一行 |

## 5. 验证结果（verify_ahrs，全 PASS）

| # | 测试 | 结果 |
|---|------|------|
| ① | TRIAD 多姿态 vs 欧拉角真值 | 阵误差 7.1e-15 |
| ② | QUEST（Davenport）同对拍 | 阵误差 1.6e-15 |
| ③ | 静态收敛：3~5° 初始误差 + 100°/h 级陀螺零偏 | 300 s 后 0.0000°，零偏吸收残差 0.0% |
| ④a | 动态跟踪（匀速直行/左转 2°/s/滚转 1°/s） | 稳态最大 0.0245° |
| ④b | **加速度扰动演示**：0.25 m/s² 前向加速 20 s | pitch 偏 1.56°（原理性盲区），结束后 30 s 回收至 0.008° |
| ⑤ | 无磁模式 | pitch/roll 收敛 0.0000°，yaw 保持初值（不可观 ≠ 发散） |

## 6. 演示图（demo_ahrs 三联图）

由 `demos/demo_ahrs.m` 生成（图内文字全 ASCII，中文说明在图下方）。

### 6.1 静态收敛 + 零偏吸收

![静态收敛：3-5° 初始误差，陀螺零偏 50/-30/20 °/h，300 s 后误差归零；下图为积分项/真零偏比值，最终收敛到 1.0](../../../assets/miniins/assets/demo_ahrs_static.png)

### 6.2 动态跟踪（转弯 + 滚转）

![动态跟踪：匀速直行 → 左转 2°/s → 滚转 1°/s，稳态误差 0.025° 量级](../../../assets/miniins/assets/demo_ahrs_dynamic.png)

### 6.3 加速度扰动：Mahony 的原理性盲区

![加速度扰动：0.25 m/s² 前向加速 20 s 使 pitch 被拽偏 1.56°；加速结束后 30 s 内回收至 0.008°](../../../assets/miniins/assets/demo_ahrs_disturb.png)

## 7. 两个实战坑（调试实录）

### 7.1 坑一：磁偏角不补偿，yaw 精确卡在 −7°

首版 `mahonyupdate` 磁参考写死"水平朝真北"（`mb_n(1:2)=[0;mh]`），仿真地磁带 $D_{dec}=-7°$——结果 yaw 收敛到 **−6.87°**，数值恰为磁偏角。机理：滤波器旋转姿态直到"导航系磁东分量 = 0"，即把磁北当成了真北。修复：参考方向改为 $[\sin D_{dec};\cos D_{dec}]$（`ahrsinit` 新增 `dec` 参数）。**教训：参考向量与仿真/真实磁场必须共享同一套地磁参数，否则滤波"忠实地"收敛到错误的天花板。**

### 7.2 坑二：门控拦得住垂直加速度，拦不住水平加速度

直觉上"|‖f‖−g| 超阈就关加计"很安全，但**水平加速度对模长是二阶小量**（0.25 m/s² 前向加速只让 ‖f‖ 变 0.003 m/s²）——门控形同虚设，pitch 被拽偏 atan(0.25/9.78) ≈ 1.46°，叠加积分过冲实测 1.56°。这是 Mahony 的**原理性盲区**（PSINS 自适应 tau 的判据同为 $\|f\|-g$，同样不设防），工程上只能靠：

- GNSS 速度差分算出运动加速度，从比力中显式扣除（准惯导做法）；
- 或直接升级误差状态 KF（把加速度当过程噪声吸收）——这正是 M5 与固件 ESKF 的动机之一。

## 8. 局限与升级路径

- 教学版单样本更新（无圆锥补偿双子样、无 IIR 低通）；真实振动环境下请参考 PSINS 的 `cnscl` + 自适应 tau；
- 磁软铁畸变未建模，实际磁强计需先做**六面法标定**（衔接阶段 B）；
- 加速度盲区 → 升级 ESKF（15 态），即 [P4](P4_SINS+DR组合_拆解test_SINS_DR.md) 的 KF 框架换误差状态；
- C 移植：`quest` 的 `eig` 在嵌入式上换幂迭代/雅可比，其余函数均为基础线性代数（衔接阶段 D SIL 对拍）。

## 9. 代码与数据

| 文件 | 职责 |
|------|------|
| [ahrsinit.m](../../assets/miniins/core/ahrsinit.m) | AHRS 结构体初始化（Kp/Ki/wnie/dec） |
| [triad.m](../../assets/miniins/core/triad.m) | TRIAD 双矢量定姿（公式 6.1） |
| [quest.m](../../assets/miniins/core/quest.m) | Davenport q-方法（公式 6.1'） |
| [magsimu.m](../../assets/miniins/core/magsimu.m) | 磁测量仿真（公式 6.5，含硬铁/噪声注入） |
| [mahonyupdate.m](../../assets/miniins/core/mahonyupdate.m) | Mahony PI 融合单步更新（公式 6.2–6.4） |
| [verify_ahrs.m](../../assets/miniins/verify/verify_ahrs.m) | 6 项确定性回归（本篇第 5 节数据来源） |
| [MahonyUpdate.m](../../assets/psins260314/base/AHRS/MahonyUpdate.m) | PSINS 原版对照（第 4.3 节） |
