# cnscl.m 逐行注释 Wiki (PSINS)

> 配套源码: [cnscl.m](file:///workspace/psins/base/base1/cnscl.m)
> 所属层级: L0基础 / L1纯惯导
> 前置依赖: 必须先读 00_glvf.md（圆锥补偿系数表glv.cs）、01_earth.md（地球参考系）
> 学习目标: 读完后你应能回答哪3个问题
> 1. 为什么双子样下 $\boldsymbol{\omega}_{m1}+\boldsymbol{\omega}_{m2} \neq \boldsymbol{\omega}_{m,\text{total}}$，差的那一项叫什么？
> 2. 圆锥补偿 $\Delta\boldsymbol{\phi}$、划桨补偿 $\Delta\boldsymbol{v}_s$、旋转补偿 $\Delta\boldsymbol{v}_r$ 三者物理意义分别是什么？
> 3. `glv.cs(n-1,:)` 这一行系数为什么只乘前 $n-1$ 个样本，最后一个样本用叉乘单独处理？

---

> 💡 **学习心态**：这一章涉及较多数学知识（旋转矢量、不可交换性、Bortz 方程等），初学阶段**"知道它是干嘛的、什么时候需要、怎么调用"就够了**，推导细节是研究生级别的内容。先会用，有兴趣再深究。可将重心放在 [03_insupdate.md](03_insupdate.md)。
>
> 你现在需要掌握的：
> 1. **物理直觉**：两个旋转不可交换顺序 → 直接相加有误差 → 补一个叉乘项
> 2. **什么时候用**：高动态/振动环境必须用，低动态 MEMS 可跳过
> 3. **怎么调用**：PSINS 里 `cnscl(imu, 0)` 返回 `[phim, dvbm]`，直接喂给 insupdate
>
> 不需要掌握的（等以后有需要再深挖）：
> - 旋转矢量微分方程（Bortz 方程）的推导
> - $\frac{2}{3}$、$\frac{9}{20}$、$\frac{27}{40}$ 这些系数怎么从泰勒展开解出来的
> - 多子样算法的最优性证明
>
> **一句话**：cnscl.m 是 PSINS 的"黑盒入口"——你把 IMU 数据扔进去，它吐出补偿后的角增量 $\boldsymbol{\phi}_m$ 和速度增量 $\Delta\mathbf{v}_m$，你拿着这俩去更新姿态和速度就行。至于盒子里面怎么算的，等你需要自己写嵌入式版的时候再拆。

---

## 🧩 函数作用一句话

IMU多子样圆锥/划桨/旋转补偿

---

## 📐 数学原理 / 物理意义

### 1. 旋转不可交换性误差（圆锥误差来源）

考虑刚体在时间间隔 $[t_k, t_k+h]$ 内做两次连续转动：
- 先绕 $x$ 轴转 $\Delta\theta_1$：旋转矢量 $\boldsymbol{\phi}_1 = [\Delta\theta_1, 0, 0]^T$，单位：rad
- 再绕 $y$ 轴转 $\Delta\theta_2$：旋转矢量 $\boldsymbol{\phi}_2 = [0, \Delta\theta_2, 0]^T$，单位：rad

合成旋转矩阵用方向余弦矩阵连乘：

$$
\mathbf{C}_{\text{total}} = \mathbf{C}_y(\Delta\theta_2) \cdot \mathbf{C}_x(\Delta\theta_1)
$$

小角度近似下 $\mathbf{C}(\boldsymbol{\phi}) \approx \mathbf{I} - [\boldsymbol{\phi}\times]$，代入得：

$$
\mathbf{C}_{\text{total}} \approx (\mathbf{I} - [\boldsymbol{\phi}_2\times])(\mathbf{I} - [\boldsymbol{\phi}_1\times])
= \mathbf{I} - [(\boldsymbol{\phi}_1+\boldsymbol{\phi}_2)\times] + [\boldsymbol{\phi}_2\times][\boldsymbol{\phi}_1\times]
$$

但如果**直接求和** $\boldsymbol{\phi}_{\text{sum}} = \boldsymbol{\phi}_1+\boldsymbol{\phi}_2$，其矩阵近似为：

$$
\mathbf{C}_{\text{sum}} \approx \mathbf{I} - [(\boldsymbol{\phi}_1+\boldsymbol{\phi}_2)\times]
$$

**两者差了一个二阶叉乘项！** 利用恒等式 $[\boldsymbol{a}\times][\boldsymbol{b}\times] - [\boldsymbol{b}\times][\boldsymbol{a}\times] = [(\boldsymbol{a}\times\boldsymbol{b})\times]$，精确到二阶的合成旋转矢量应为：

$$
\boldsymbol{\phi}_{\text{total}} = \boldsymbol{\phi}_1 + \boldsymbol{\phi}_2 + \frac{1}{2}\boldsymbol{\phi}_1 \times \boldsymbol{\phi}_2 + \cdots
$$

这就是**旋转不可交换性定理**：有限转动的合成不满足加法交换律，必须加叉乘补偿项。

---

### 2. 双子样圆锥补偿公式推导（Bortz方程）

设 IMU 采样间隔为 $h$（单位：s），在一个更新周期内采 $n$ 个子样。第 $i$ 个子样角增量：

$$
\Delta\boldsymbol{\theta}_i = \int_{t_{k,i-1}}^{t_{k,i}} \boldsymbol{\omega}_{ib}^b(\tau) d\tau \quad \text{单位：rad}
$$

对于**典型圆锥运动**（绕两个正交轴做正弦/余弦耦合振荡）：

$$
\boldsymbol{\omega}_{ib}^b(t) = \begin{bmatrix} \Omega a \cos(\Omega t) \\ \Omega a \sin(\Omega t) \\ \omega_0 \end{bmatrix}
$$

其中 $a$ 为圆锥半角（rad），$\Omega$ 为圆锥角频率（rad/s）。

对 $n=2$（双子样）积分一个周期 $h$，得到两个子样：

$$
\Delta\boldsymbol{\theta}_1 = \int_0^{h/2} \boldsymbol{\omega} dt, \quad
\Delta\boldsymbol{\theta}_2 = \int_{h/2}^{h} \boldsymbol{\omega} dt
$$

代入圆锥运动角速度精确积分，再用 Bortz 旋转矢量微分方程：

$$
\dot{\boldsymbol{\phi}} = \boldsymbol{\omega} + \frac{1}{2}\boldsymbol{\phi}\times\boldsymbol{\omega} + \frac{1}{12}\boldsymbol{\phi}\times(\boldsymbol{\phi}\times\boldsymbol{\omega}) + \cdots
$$

忽略三阶以上小量，积分后得到**双子样圆锥补偿精确公式**：

$$
\Delta\boldsymbol{\phi} = \Delta\boldsymbol{\theta}_1 + \Delta\boldsymbol{\theta}_2 + \frac{2}{3}\Delta\boldsymbol{\theta}_1 \times \Delta\boldsymbol{\theta}_2
$$

其中：
- $\Delta\boldsymbol{\theta}_1 + \Delta\boldsymbol{\theta}_2$：直接求和的"名义"旋转矢量，单位 rad
- $\frac{2}{3}\Delta\boldsymbol{\theta}_1 \times \Delta\boldsymbol{\theta}_2$：**圆锥补偿量**（coning compensation）$\Delta\boldsymbol{\phi}_{\text{cone}}$，单位 rad，由旋转不可交换性引起
- 系数 $\frac{2}{3}$ 是 $n=2$ 时在圆锥运动假设下使误差四阶小量的最优值，对应 `glv.cs(1,:) = [2/3, 0, 0, 0, 0]`

推广到 $n$ 子样最优补偿：

$$
\Delta\boldsymbol{\phi}_{\text{cone}} = \left(\sum_{i=1}^{n-1} c_i(n) \Delta\boldsymbol{\theta}_i\right) \times \Delta\boldsymbol{\theta}_n
$$

其中系数向量 $[c_1(n), c_2(n), \dots, c_{n-1}(n)]$ 即为 `glv.cs(n-1,:)`，它使补偿后残余圆锥误差阶次最高（$2n$ 阶）。

---

### 3. 划桨补偿（Sculling Compensation）

**划桨运动**定义为载体角振动和线振动在两个正交轴上同频耦合：

$$
\boldsymbol{\omega}_{ib}^b(t) = \begin{bmatrix} \Omega a \cos(\Omega t) \\ 0 \\ 0 \end{bmatrix}, \quad
\boldsymbol{f}_{sf}^b(t) = \begin{bmatrix} 0 \\ \Omega b \sin(\Omega t) \\ 0 \end{bmatrix}
$$

其中 $a$（rad）、$b$（m/s）分别为角/线划桨振幅，$\Omega$ 为角频率（rad/s）。

比力积分得到子样速度增量：

$$
\Delta\boldsymbol{v}_i = \int_{t_{k,i-1}}^{t_{k,i}} \boldsymbol{f}_{sf}^b(\tau) d\tau \quad \text{单位：m/s}
$$

**划桨误差的物理来源**：在机体系 $b$ 中积分比力时，坐标系本身同时在旋转，导致"速度增量的坐标系不一致"。

双子样下划桨补偿公式：

$$
\Delta\boldsymbol{v}_{\text{scull}} = \frac{2}{3}\left(\Delta\boldsymbol{\theta}_1 \times \Delta\boldsymbol{v}_2 + \Delta\boldsymbol{v}_1 \times \Delta\boldsymbol{\theta}_2\right)
$$

对应代码 L66 中两项叉乘之和。推广到 $n$ 子样最优形式：

$$
\Delta\boldsymbol{v}_{\text{scull}} = \left(\sum_{i=1}^{n-1} c_i(n) \Delta\boldsymbol{\theta}_i\right) \times \Delta\boldsymbol{v}_n
+ \left(\sum_{i=1}^{n-1} c_i(n) \Delta\boldsymbol{v}_i\right) \times \Delta\boldsymbol{\theta}_n
$$

与圆锥补偿共用同一套系数表 `glv.cs(n-1,:)`——这就是"圆锥-划桨对偶原理"。

---

### 4. 旋转补偿（Rotation Compensation）

即使**完全没有圆锥/划桨振动**，单纯"刚体有角速度 + 有加速度"，由于子样积分区间内机体系已经转过一个角度，前后子样的速度增量方向也不一致。这一补偿称为**旋转补偿**或**速度转动补偿**：

$$
\Delta\boldsymbol{v}_{\text{rot}} = \frac{1}{2}\Delta\boldsymbol{\phi} \times \Delta\boldsymbol{v}
= \frac{1}{2}(\sum_i \Delta\boldsymbol{\theta}_i) \times (\sum_j \Delta\boldsymbol{v}_j)
$$

对应代码 L71 `rotm = 1/2*cros(wmm,vmm)`。物理含义：将速度增量从"平均机体系"旋转到"更新周期末机体系"所需的一半转角近似（中点积分思想）。

---

### 5. 补偿系数表 glv.cs 详解

`glv.cs` 是 $(n_s-1) \times (n_s-1)$ 下三角矩阵，其中 $n_s$ 最大支持子样数（这里最大6子样）。第 $i$ 行对应 $(i+1)$ 子样补偿多项式系数：

| 行索引 | 子样数 | 系数向量（前若干项非零） | 含义 |
|--------|--------|--------------------------|------|
| `glv.cs(1,:)` | 2子样 | $[\frac{2}{3}, 0, 0, 0, 0]$ | $\frac{2}{3}\Delta\boldsymbol{\theta}_1 \times \Delta\boldsymbol{\theta}_2$ |
| `glv.cs(2,:)` | 3子样 | $[\frac{9}{20}, \frac{27}{20}, 0, 0, 0]$ | $(\frac{9}{20}\Delta\boldsymbol{\theta}_1 + \frac{27}{20}\Delta\boldsymbol{\theta}_2) \times \Delta\boldsymbol{\theta}_3$ |
| `glv.cs(3,:)` | 4子样 | $[\frac{54}{105}, \frac{92}{105}, \frac{214}{105}, 0, 0]$ | 4子样最优 |
| `glv.cs(4,:)` | 5子样 | $[\frac{250}{504}, \frac{525}{504}, \frac{650}{504}, \frac{1375}{504}, 0]$ | 5子样最优 |
| `glv.cs(5,:)` | 6子样 | $[\frac{2315}{4620}, \frac{4558}{4620}, \frac{7296}{4620}, \frac{7834}{4620}, \frac{15797}{4620}]$ | 6子样最优 |

---

## 📝 逐行注释

### 主函数 L1-L73

| 行号 | 原代码 | 中文注释 | 公式/备注 |
|------|--------|----------|-----------|
| 1 | `function [phim, dvbm, dphim, rotm, scullm] = cnscl(imu, coneoptimal)` | 函数定义：圆锥与划桨补偿。输入IMU增量数据与补偿模式开关；输出补偿后的旋转矢量、速度增量以及三种补偿分项 | 5个输出：phim补偿后旋转矢量(3×1,rad)；dvbm补偿后速度增量(3×1,m/s)；dphim圆锥误差；rotm旋转误差；scullm划桨误差 |
| 2 | `% Coning & sculling compensation.` | 函数摘要：圆锥与划桨补偿 |  |
| 3 | 空行 | 空行分隔 |  |
| 4 | `% Prototype: [phim, dvbm, dphim, rotm, scullm] = cnscl(imu, coneoptimal)` | 函数原型说明 |  |
| 5 | `% Inputs:  imu(:,1:3) - gyro angular increments` | 输入说明：imu的1-3列为陀螺角增量 | 每个子样一行，$\Delta\boldsymbol{\theta}_i$，单位rad |
| 6 | `%          imu(:,4:6) - acc velocity increments (may not exist)` | 输入说明：4-6列为加速度计速度增量（可选） | $\Delta\boldsymbol{v}_i$，单位m/s；若仅3列则只做姿态补偿，速度输出为0 |
| 7 | `%          coneoptimal - 0 for optimal coning compensation method,` | 输入说明：coneoptimal=0使用最优圆锥补偿（默认推荐） | 即利用glv.cs系数表的Miller最优算法 |
| 8 | `%                        1 for polinomial compensation method.` | coneoptimal=1使用多项式拟合补偿 | 调用conepolyn/scullpolyn函数 |
| 9 | `%                        2 single sample+previous sample` | coneoptimal=2单子样+前一样本模式 | 即"当前样本+上一周期末样本"拼成双子样，需glv.wm_1/vm_1缓存 |
| 10 | `%                        3 high order coning compensation` | coneoptimal=3高阶圆锥补偿 | 调用conehighorder |
| 11 | `% Outputs: phim - rotation vector after coning compensation` | 输出说明：phim为补偿后旋转矢量 | $\Delta\boldsymbol{\phi} = \sum\Delta\boldsymbol{\theta}_i + \Delta\boldsymbol{\phi}_{\text{cone}}$ |
| 12 | `%          dvbm - velocity increment after rotation & sculling compensation` | 输出说明：dvbm为补偿后速度增量 | $\Delta\boldsymbol{v} = \sum\Delta\boldsymbol{v}_i + \Delta\boldsymbol{v}_{\text{rot}} + \Delta\boldsymbol{v}_{\text{scull}}$ |
| 13 | `%          dphim - attitude coning error` | 输出说明：dphim为圆锥误差补偿量本身 | 即 $\Delta\boldsymbol{\phi}_{\text{cone}}$，用于误差分析 |
| 14 | `%          rotm - velocity rotation error` | 输出说明：rotm为速度旋转误差补偿量 | 即 $\Delta\boldsymbol{v}_{\text{rot}} = \frac{1}{2}\boldsymbol{\phi}\times\boldsymbol{v}$ |
| 15 | `%          scullm - velocity sculling error` | 输出说明：scullm为划桨误差补偿量 | 即 $\Delta\boldsymbol{v}_{\text{scull}}$ |
| 16 | 空行 | 空行分隔 |  |
| 17 | `% See also  cnscl0, conepolyn, scullpolyn, conetwospeed, conecoef,` | 相关函数交叉引用（上一行） |  |
| 18 | `%           insupdate, DR, imuadderr.` | 相关函数交叉引用（下一行） | 最重要的调用者：insupdate |
| 19 | 空行 | 空行分隔 |  |
| 20 | `% Copyright(c) 2009-2014, by Gongmin Yan, All rights reserved.` | 版权声明，西工大严恭敏老师 |  |
| 21 | `% Northwestern Polytechnical University, Xi An, P.R.China` | 作者单位：西北工业大学，西安，中国 |  |
| 22 | `% 07/12/2012, 04/12/2016` | 版本日期：2012.12.07初版，2016.12.04修订 |  |
| 23 | `global glv` | 声明全局变量glv，含圆锥补偿系数表glv.cs、历史样本wm_1/vm_1等 | 必须在glvf.m中已初始化 |
| 24 | `    if nargin<2,  coneoptimal=0;  end` | 默认参数：若未传coneoptimal，则默认=0（最优补偿） |  |
| 25 | `    [n, m] = size(imu);` | 获取IMU矩阵维度：n=子样数，m=列数（3或6） | n个子样，m列：3=仅陀螺，6=陀螺+加计 |
| 26 | `    if n>glv.csmax  % the maximun subsample number is glv.csmax, if n exceeds, then reshape imu` | 若子样数n超过最大允许值glv.csmax（=6），则重采样压缩 | glv.csmax=size(glv.cs,1)+1=6子样 |
| 27 | `        [imu, n] = imureshape(imu, n, m);` | 调用子函数imureshape：将n个小子样合并为n'个大子样，n'是≤6且能整除n的最大整数 | 例：n=10→压缩为n=5子样（每2个求和合并） |
| 28 | `    end` | if结束 |  |
| 29 | `    %% coning compensation` | 分节注释：开始圆锥补偿部分 | %%是Matlab代码节（cell）分隔符 |
| 30 | `    wm = imu(:,1:3);` | 提取陀螺角增量矩阵wm：n行×3列，每行为一个子样的$\Delta\boldsymbol{\theta}_i$ | $\mathbf{wm} = [\Delta\boldsymbol{\theta}_1; \Delta\boldsymbol{\theta}_2; \dots; \Delta\boldsymbol{\theta}_n]$，单位rad |
| 31 | `	if n==1` | **单子样分支**：若当前更新周期内只有1个IMU子样 | n=1意味着IMU采样频率=SINS更新频率 |
| 32 | `        wmm = wm;` | 单子样下角增量之和就是它本身 | $\boldsymbol{\omega}_{mm} = \Delta\boldsymbol{\theta}_1$（1×3行向量） |
| 33 | `        if coneoptimal==2` | 在单子样+coneoptimal=2模式下，启用"当前样+上周期样"拼接双子样 | 需配合glv.wm_1全局缓存 |
| 34 | `            dphim = 1/12*cros(glv.wm_1,wm);  if m<6, glv.wm_1 = wm; end` | ⚠️ 单子样+前一样模式的圆锥补偿：用上一个采样点wm_1与当前wm做叉乘，系数1/12；若无加计(m<6)则更新缓存 | 公式：$\Delta\boldsymbol{\phi}_{\text{cone}} = \frac{1}{12}\Delta\boldsymbol{\theta}_{\text{prev}} \times \Delta\boldsymbol{\theta}_{\text{curr}}$。系数1/12是将"跨更新周期双子样"代入最优公式得到的 |
| 35 | `        else` | coneoptimal≠2的单子样情况（0、1、3） |  |
| 36 | `            dphim = [0, 0, 0];` | 单子样下无圆锥补偿，直接置零 | n=1时无足够样本估计不可交换误差，补偿量=0 |
| 37 | `        end` | if结束 |  |
| 38 | `    else` | **多子样分支**：n≥2时进入圆锥补偿核心算法 |  |
| 39 | `        wmm = sum(wm,1);` | 所有子样角增量求和（按列求和得到1×3行向量） | $\boldsymbol{\omega}_{mm} = \sum_{i=1}^{n} \Delta\boldsymbol{\theta}_i$，名义旋转矢量（未补偿） |
| 40 | `        if coneoptimal==0` | coneoptimal=0最优圆锥补偿（默认，推荐使用） | 利用glv.cs系数表的Miller算法 |
| 41 | `            cm = glv.cs(n-1,1:n-1)*wm(1:n-1,:);` | ★ 关键行1：取系数表第(n-1)行（对应n子样）的前(n-1)个系数，与前(n-1)个子样的wm做矩阵乘法，得到加权和向量cm(1×3) | 公式：$\mathbf{c}_m = \sum_{i=1}^{n-1} c_i(n) \cdot \Delta\boldsymbol{\theta}_i$；c_i(n)即glv.cs(n-1,i)。cm是1×3行向量，代表前n-1样本的加权角增量 |
| 42 | `            dphim = cros(cm,wm(n,:));` | ★ 关键行2：将加权和cm与最后一个子样wm(n,:)做叉乘，得到圆锥补偿量dphim（1×3） | 公式：$\Delta\boldsymbol{\phi}_{\text{cone}} = \mathbf{c}_m \times \Delta\boldsymbol{\theta}_n$。这是n子样最优圆锥补偿的标准形式，对应L71系数表结构 |
| 43 | `        elseif coneoptimal==1 % else: using polynomial fitting coning compensation method` | coneoptimal=1：使用多项式拟合方法 | 注释"else"笔误，实际是elseif分支 |
| 44 | `            dphim = conepolyn(wm);` | 调用conepolyn函数：基于时间多项式拟合的圆锥补偿 | 对高动态非圆锥型运动可能更优 |
| 45 | `        elseif coneoptimal==2` | coneoptimal=2多子样情况 | 单子样分支已在L33处理 |
| 46 | `            dphim = coneuncomp(wm);` | 调用coneuncomp函数：单子样+前一样模式的多子样版本 |  |
| 47 | `        elseif coneoptimal==3` | coneoptimal=3：高阶圆锥补偿 |  |
| 48 | `            dphim = conehighorder(wm);` | 调用conehighorder函数：更高阶精度的圆锥补偿 |  |
| 49 | `        end` | if-elseif多分支结束 |  |
| 50 | `	end` | 外层n==1/n≥2分支结束 | 注意缩进使用tab（Matlab允许） |
| 51 | `    phim = (wmm+dphim*glv.csCompensate)';  dvbm = [0; 0; 0];` | ★ 补偿后旋转矢量：名义旋转wmm加圆锥补偿dphim，乘开关量csCompensate（=1启用，=0关闭便于对比实验），再转置为列向量；速度增量先置零列向量 | 公式：$\boldsymbol{\phi}_m = \left(\sum\Delta\boldsymbol{\theta}_i + \text{csCompensate} \cdot \Delta\boldsymbol{\phi}_{\text{cone}}\right)^T$。dvbm先初始化零，后续L72若有加计再覆盖 |
| 52 | `    %% sculling compensation` | 分节注释：开始速度补偿部分（划桨+旋转） |  |
| 53 | `    if m>=6` | 只有IMU含6列（陀螺+加计）时才做速度补偿 | m=3时直接跳过，dvbm保持L51的零向量 |
| 54 | `        vm = imu(:,4:6); ` | 提取加计速度增量矩阵vm：n行×3列 | $\mathbf{vm} = [\Delta\boldsymbol{v}_1; \Delta\boldsymbol{v}_2; \dots; \Delta\boldsymbol{v}_n]$，单位m/s |
| 55 | `        if n==1` | 单子样分支 | 与圆锥补偿L31对称 |
| 56 | `            vmm = vm;` | 单子样下速度增量之和即本身 | $\boldsymbol{v}_{mm} = \Delta\boldsymbol{v}_1$（1×3行向量） |
| 57 | `            if coneoptimal==0` | coneoptimal=0的单子样情况 |  |
| 58 | `                scullm = [0, 0, 0];` | 单子样无划桨补偿，置零 |  |
| 59 | `            else` | coneoptimal≠2以外的非0情况？ | 实际这里coneoptimal=1/2/3都走这里 |
| 60 | `                scullm = 1/12*(cros(glv.wm_1,vm)+cros(glv.vm_1,wm));  glv.wm_1 = wm; glv.vm_1 = vm;` | ⚠️ 单子样划桨补偿：跨周期拼接。用上周期wm_1×当前vm + 上周期vm_1×当前wm，系数1/12；更新全局缓存 | 公式：$\Delta\boldsymbol{v}_{\text{scull}} = \frac{1}{12}(\Delta\boldsymbol{\theta}_{\text{prev}} \times \Delta\boldsymbol{v}_{\text{curr}} + \Delta\boldsymbol{v}_{\text{prev}} \times \Delta\boldsymbol{\theta}_{\text{curr}})$ |
| 61 | `            end` | if结束 |  |
| 62 | `        else` | 多子样分支n≥2 | 与圆锥补偿L38对称 |
| 63 | `            vmm = sum(vm,1);` | 所有子样速度增量求和（1×3行向量） | $\boldsymbol{v}_{mm} = \sum_{i=1}^{n} \Delta\boldsymbol{v}_i$，名义速度增量（未补偿） |
| 64 | `            if coneoptimal==0` | coneoptimal=0最优划桨补偿（默认） | 与圆锥补偿L40对称 |
| 65 | `                sm = glv.cs(n-1,1:n-1)*vm(1:n-1,:);` | ★ 划桨加权和：用同一套系数表glv.cs对前n-1个vm子样加权求和 | 公式：$\mathbf{s}_m = \sum_{i=1}^{n-1} c_i(n) \cdot \Delta\boldsymbol{v}_i$；sm是1×3行向量 |
| 66 | `                scullm = (cros(cm,vm(n,:))+cros(sm,wm(n,:)));` | ★ 划桨补偿量=两项叉乘之和：①加权角增量cm×末样速度vm(n)；②加权速度增量sm×末样角速度wm(n) | 公式：$\Delta\boldsymbol{v}_{\text{scull}} = \mathbf{c}_m \times \Delta\boldsymbol{v}_n + \mathbf{s}_m \times \Delta\boldsymbol{\theta}_n$。两项分别对应"角旋引起的速度投影误差"和"线动引起的角度投影误差"，体现圆锥-划桨对偶 |
| 67 | `            else  % else: using polynomial fitting sculling compensation method` | coneoptimal≠0：多项式拟合划桨补偿 |  |
| 68 | `                scullm = scullpolyn(wm, vm);` | 调用scullpolyn函数：时间多项式拟合的划桨补偿 | 需同时传入wm和vm |
| 69 | `            end` | if-coneoptimal分支结束 |  |
| 70 | `        end` | if-n分支结束 |  |
| 71 | `        rotm = 1.0/2*cros(wmm,vmm);` | ★ 旋转补偿：总角增量×总速度增量×1/2。来源：将子样速度增量从"区间中段平均坐标系"旋转到"区间末端坐标系"，中点积分近似 | 公式：$\Delta\boldsymbol{v}_{\text{rot}} = \frac{1}{2}\Delta\boldsymbol{\phi} \times \Delta\boldsymbol{v}$，其中$\Delta\boldsymbol{\phi}=\boldsymbol{w}_{mm}$，$\Delta\boldsymbol{v}=\boldsymbol{v}_{mm}$。物理意义：积分区间内机体系转动导致的速度投影方向修正 |
| 72 | `        dvbm = (vmm+(rotm+scullm)*glv.csCompensate)';` | ★ 补偿后速度增量：名义速度vmm + 旋转补偿rotm + 划桨补偿scullm，经csCompensate开关控制，再转置为3×1列向量 | 公式：$\Delta\boldsymbol{v}_{bm} = \left(\sum\Delta\boldsymbol{v}_i + \text{csCompensate} \cdot (\Delta\boldsymbol{v}_{\text{rot}} + \Delta\boldsymbol{v}_{\text{scull}})\right)^T$。三项之和是PSINS速度补偿完整公式 |
| 73 | `    end` | if-m≥6分支结束 | 若m=3无加计数据，则dvbm保持L51零向量 |
| 74 | 空行 | 空行分隔 |  |

### 子函数 imureshape L75-L87

| 行号 | 原代码 | 中文注释 | 公式/备注 |
|------|--------|----------|-----------|
| 75 | `function [imu, n] = imureshape(imu0, n0, m0)` | 子函数：IMU重采样压缩。输入原始IMU(imu0，n0行m0列)；输出压缩后的IMU(imu，n行m0列)及新子样数n | 目的：把超过glv.csmax的子样合并，使n≤6且n0能被n整除 |
| 76 | `% Copyright(c) 2009-2014, by Gongmin Yan, All rights reserved.` | 版权声明，西工大严恭敏老师 |  |
| 77 | `% Northwestern Polytechnical University, Xi An, P.R.China` | 作者单位 |  |
| 78 | `% 09/03/2014` | 版本日期 |  |
| 79 | `global glv` | 声明全局变量以访问glv.csmax |  |
| 80 | `    for n=glv.csmax:-1:1` | 从最大允许子样数(=6)倒序遍历到1 | 倒序目的：优先取最大的可用n，压缩损失最小 |
| 81 | `        if mod(n0,n)==0,  break;  end` | 找到第一个能整除n0的n，跳出循环。此时n为≤csmax且能整除n0的最大值 | 例：n0=100，6不行→5可以→n=5（每个合并20个原始样本） |
| 82 | `    end` | for循环结束 | 最坏情况n=1（退化为单子样） |
| 83 | `    nn = n0/n;` | 计算每个新子样包含多少个原始子样 | nn=压缩比（整数） |
| 84 | `    imu = zeros(n, m0);` | 预分配压缩后的IMU矩阵 | n行m0列，初始化为零 |
| 85 | `    for k=1:n` | 对每一个新子样循环 |  |
| 86 | `        imu(k,:) = sum(imu0((k-1)*nn+1:k*nn,:),1);` | 第k个新子样=第(k-1)·nn+1 到 k·nn 个原始子样**按列求和**（即角/速度增量直接相加，这是增量数据合并的唯一正确方式） | 角增量叠加$\Delta\boldsymbol{\theta}_{\text{merge}} = \sum \Delta\boldsymbol{\theta}_i$，速度增量同理。注意：这一步**不做圆锥补偿**，补偿在后续主函数统一处理 |
| 87 | `    end` | for循环结束，子函数隐式返回imu和n |  |

---

## 🔍 断点调试建议

### 调试1：圆锥运动定量验证（验证圆锥补偿公式）

构造**理想圆锥运动**角增量：设周期 $h=0.01\,\text{s}$，圆锥半角 $a=0.01\,\text{rad}$，角频率 $\Omega=2\pi\,\text{rad/s}$。双子样下，两个子样角增量为：

$$
\boldsymbol{\omega}_{m1} = \int_0^{h/2} \boldsymbol{\omega}(t) dt = \begin{bmatrix}
0.01 \cdot \sin(\pi \cdot 0.005) \\
0.01 \cdot (1-\cos(\pi \cdot 0.005)) \\
0
\end{bmatrix}, \quad
\boldsymbol{\omega}_{m2} = \int_{h/2}^{h} \boldsymbol{\omega}(t) dt = \begin{bmatrix}
0.01 \cdot (\sin(2\pi \cdot 0.005)-\sin(\pi \cdot 0.005)) \\
0.01 \cdot (\cos(\pi \cdot 0.005)-\cos(2\pi \cdot 0.005)) \\
0
\end{bmatrix}
$$

**调试步骤**：
1. 在 `cnscl.m` 第 L41 行设断点（`cm = glv.cs(n-1,1:n-1)*wm(1:n-1,:)`）
2. 构造 `wm = [wm1; wm2]`（n=2），调用 `[phim, ~, dphim] = cnscl(wm, 0)`
3. 命中断点后：
   - 观察 `glv.cs(1,1)` = 2/3（双子样系数）
   - 观察 `cm` = 2/3 × wm1（第1子样加权）
   - 单步跳过L42：`dphim` = cross(cm, wm2) = (2/3)·wm1 × wm2，验证其第三分量≈$(2/3)\omega_{m1,x}\omega_{m2,y} - (2/3)\omega_{m1,y}\omega_{m2,x}$
   - 继续：`phim(3)` 应等于 `wm1(3)+wm2(3)+dphim(3)`（圆锥补偿主要沿z轴）
4. 对比 `sum(wm,1)(3)` 与 `phim(3)`，**两者之差就是圆锥补偿误差的直接数值体现**——在高动态下差异可达10^-8 rad量级，长期积累会显著漂移

### 调试2：单子样+前一样模式（coneoptimal=2）

**调试步骤**：
1. 在 `cnscl.m` 第 L34 行设断点
2. 先调用一次 `glv.wm_1 = [0;0;0];` 初始化缓存
3. 第一次调用 `[~,~,dphim1] = cnscl(wm_a, 2)`：因wm_1初值全零，dphim1=0；执行后glv.wm_1被设为wm_a
4. 第二次调用 `[~,~,dphim2] = cnscl(wm_b, 2)`：命中断点，查看 `1/12*cross(glv.wm_1,wm)` 应为 `(1/12)·wm_a × wm_b`，验证与手算一致
5. 若忘记重置 `glv.wm_1`，第三次调用会使用wm_b作为前一样，导致补偿量"串了"——此即"坑②"的调试重现

### 调试3：旋转补偿项验证

**调试步骤**：
1. 在 `cnscl.m` 第 L71 行设断点
2. 构造双子样：`wm=[1e-4,0,0; 1e-4,0,0]`（x轴纯转动），`vm=[0,1e-3,0; 0,1e-3,0]`（y轴纯加速）
3. 命中断点：wmm=[2e-4,0,0]，vmm=[0,2e-3,0]
4. 手算 `rotm = (1/2)*cross(wmm,vmm)` = `[0, 0, (1/2)(2e-4·2e-3)]` = `[0,0,2e-7]`，与运行结果对比
5. 物理理解：x轴旋转2e-4 rad ≈ 0.0115°，会把y方向速度增量"投影"一小部分到z方向，量级正好是2e-7 m/s

---

## ❌ 初学者最容易踩的坑

### 坑①：以为wm直接sum就够，高动态下误差爆炸

**表现**：跳过cnscl直接用sum(wm)做姿态更新，在有角振动（圆锥运动）时姿态z轴漂移远大于理论值。

**为什么错**：旋转不可交换性是**二阶固有误差**，不补偿时每步误差量级为 $O(\|\Delta\boldsymbol{\theta}_1\| \cdot \|\Delta\boldsymbol{\theta}_2\|)$。对100Hz IMU做10Hz更新（n=10子样），每子样1e-3 rad，每步圆锥误差≈(2/3)·1e-3·1e-3≈7e-7 rad，1小时累计=36000步×7e-7≈0.025 rad≈1.4°——这是**不能接受的**。

**正确做法**：永远通过cnscl处理多子样IMU数据，不要自己sum。

---

### 坑②：coneoptimal=2时忘记初始化/重置glv.wm_1，初期结果不对

**表现**：仿真前几步姿态误差突然跳变，之后又慢慢收敛，或跑完后重启仿真但glv全局变量没清，结果第二次跑一开始就有补偿量。

**为什么错**：coneoptimal=2依赖**上一个SINS更新周期**的glv.wm_1/vm_1做跨周期拼接。若第一次运行前wm_1=[0,0,0]，则第一步补偿量为0（正确）；但若中途重启而不清空wm_1，第一步就会携带上一次运行的最后一个样本做叉乘，产生虚假补偿。

**正确做法**：每次仿真开始前调用一次 `glvf` 重置全局变量，或手动 `glv.wm_1=[0;0;0]; glv.vm_1=[0;0,0];`。

---

### 坑③：输入imu只有3列（仅wm）时，dvbm输出全零，误以为函数坏了

**表现**：只传入 `imu = [wx, wy, wz]` 调用cnscl，发现dvbm=[0;0;0]，以为"划桨补偿没生效"。

**为什么错**：L53 `if m>=6` 决定了只有列数≥6（含加计dv列）时才进入速度补偿分支。3列输入时函数只做姿态圆锥补偿，dvbm被L51初始化为零且永远不会被覆盖。

**正确做法**：如果需要速度补偿，IMU数据必须是6列格式 `[wm1,wm2,wm3, vm1,vm2,vm3]`；若只有陀螺数据，则dvbm=0是正确行为。

---

### 坑④（补充）：n>6不报错但结果不同，因为imureshape自动压缩

**表现**：传入n=12子样，预期用12子样系数，但实际输出=6子样结果。

**为什么错**：L26-L28的imureshape会把n从12压缩到6（因为glv.csmax=6且12能被6整除）。补偿公式用的是6子样系数，不是12子样。

**正确做法**：SINS更新频率和IMU采样频率配合，保证一个更新周期内子样数n≤6；如果IMU频率极高，先在前端硬件/预处理器中做累加压缩。

---

## 🎯 配套练习

### 练习题：双子样圆锥补偿手算 vs cnscl对比

**题目**：手工构造两个连续角增量子样：

$$
\boldsymbol{\omega}_{m1} = [1\times10^{-4},\; 0,\; 0]^T \quad (\text{rad}), \qquad
\boldsymbol{\omega}_{m2} = [0,\; 1\times10^{-4},\; 0]^T \quad (\text{rad})
$$

**手算步骤要求**：
1. 直接求和得名义旋转矢量：$\boldsymbol{\phi}_{\text{sum}} = \boldsymbol{\omega}_{m1} + \boldsymbol{\omega}_{m2}$
2. 计算叉乘：$\boldsymbol{\omega}_{m1} \times \boldsymbol{\omega}_{m2} = \begin{vmatrix}
\mathbf{i} & \mathbf{j} & \mathbf{k} \\
1e-4 & 0 & 0 \\
0 & 1e-4 & 0
\end{vmatrix} = [0, 0, 1e-8]^T$
3. 双子样补偿公式：$\Delta\boldsymbol{\phi} = \boldsymbol{\phi}_{\text{sum}} + \frac{2}{3}(\boldsymbol{\omega}_{m1} \times \boldsymbol{\omega}_{m2})$
4. 得到第三分量：$\Delta\phi_z = 0 + \frac{2}{3} \times 1e-8 = 6.666666666666667\text{e-9}\,\text{rad}$

**Matlab验证代码**：
```matlab
glvf;  % 初始化glv全局变量，尤其是glv.cs和glv.csCompensate
wm1 = [1e-4, 0, 0];
wm2 = [0, 1e-4, 0];
imu_input = [wm1; wm2];  % n=2子样，m=3列（无加计）
[phim_cnscl, ~, dphim] = cnscl(imu_input, 0);

% 手算对比
phi_sum  = (wm1 + wm2)';
phi_man  = phi_sum + (2/3) * cross(wm1, wm2)';

% 验证1：cnscl输出phim与手算phi_man之差应<1e-15
diff1 = norm(phim_cnscl - phi_man);
fprintf('手算phim与cnscl输出差 = %.2e (应<1e-15)\n', diff1);
assert(diff1 < 1e-15, '圆锥补偿公式手算验证失败！');

% 验证2：dphim（圆锥补偿分项）应等于 (2/3)*cross(wm1,wm2)
diff2 = norm(dphim' - (2/3)*cross(wm1,wm2)');
fprintf('圆锥补偿分项dphim误差 = %.2e (应<1e-15)\n', diff2);
assert(diff2 < 1e-15, '圆锥补偿分项dphim验证失败！');

disp('✅ 双子样圆锥补偿验证全部通过！');
```

**预期结果**：两个差值均在1e-16量级（Matlab双精度舍入误差），验证cnscl核心公式实现完全正确。
