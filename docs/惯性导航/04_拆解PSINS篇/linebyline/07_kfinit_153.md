# 07_kfinit_153 逐行注释 Wiki (PSINS)

> 配套源码: [kfinit.m](file:///workspace/psins/base/kf/kfinit.m)
> 关联源码: [kfhk.m](file:///workspace/psins/base/kf/kfhk.m) / [kfinit0.m](file:///workspace/psins/base/kf/kfinit0.m) / [kfsetting.m](file:///workspace/psins/base/kf/kfsetting.m) / [etm.m](file:///workspace/psins/base/base2/etm.m)
> 所属层级: L3 组合导航 SINS/GPS松组合
> 前置依赖: 00_glvf / 03_insupdate / 08_kffk / 09_kfupdate
> 学习目标: 读完回答3个问题
>
> 1. 15状态向量 $\boldsymbol{X}=[\phi^T,\delta v_n^T,\delta p^T,\varepsilon_b^T,\nabla_b^T]^T$ 的**索引编号1~15**分别对应什么？etm.m 的F阵分块与此顺序如何对应？
> 2. P0对角线上 `10″²`、`(0.1m/s)²`、`(0.01°/h)²` 这些量级的工程依据是什么？单位如何从 deg/arcsec/°/h 换算到 SI 单位 rad/(rad/s)/(m/s²)？
> 3. 对于 case 153，kf.Hk 为什么是 `[zeros(3,6), eye(3), zeros(3,6)]`？如果把第7~9列与第1~3列写反了，会出现什么现象？

---

## 🧩 函数作用一句话

根据 psinsdef.kfinit 标志位（153=15状态+3位置观测）对 SINS/GPS 松组合卡尔曼滤波器进行初始化：设定系统噪声协方差 Qt、观测噪声协方差 Rk、初始均方误差阵 Pxk、观测矩阵 Hk，并调用 kfinit0 填充所有其余 KF 结构字段（Pmin/Pmax、adaptive、pconstrain等开关）。

---

## 📐 数学原理 / 物理意义

### 1. 15状态定义（状态顺序编号表）

PSINS 中 SINS/GPS 松组合 15 维误差状态向量严格定义为：

| 编号 | 符号 | 物理量 | 单位（SI） | 典型初值σ(P0对角线开平方) | etm.m F阵分块行/列 |
|------|------|--------|------------|---------------------------|-------------------|
| 1 | $\phi_E$ | 东向姿态误差角（俯仰绕E轴） | rad | $10″ \approx 4.85\times10^{-5}$ rad | 第1行：Maa块（φ→φ） |
| 2 | $\phi_N$ | 北向姿态误差角（滚转绕N轴） | rad | $10″ \approx 4.85\times10^{-5}$ rad | 第2行：Maa块 |
| 3 | $\phi_U$ | 天向（方位）姿态误差角 | rad | $30″ \approx 1.45\times10^{-4}$ rad（航向通常较松） | 第3行：Maa块 |
| 4 | $\delta v_E$ | 东向速度误差 | m/s | 0.1 m/s | 第4行：Mva块（φ→δv） |
| 5 | $\delta v_N$ | 北向速度误差 | m/s | 0.1 m/s | 第5行：Mva块 |
| 6 | $\delta v_U$ | 天向速度误差 | m/s | 0.1 m/s | 第6行：Mva块 |
| 7 | $\delta L$ | 纬度误差 | rad | $10m/R_M \approx 1.57\times10^{-6}$ rad | 第7行：O33+Mpv块（δv→δp） |
| 8 | $\delta \lambda$ | 经度误差 | rad | $10m/(R_N\cos L) \approx 1.57\times10^{-6}$ rad | 第8行：Mpv块 |
| 9 | $\delta h$ | 高度误差 | m | 10 m（直接米） | 第9行：Mpv块(3,3)=1 |
| 10 | $\varepsilon_{b,x}$ | 陀螺x轴零偏（b系） | rad/s | $0.01°/h \approx 4.85\times10^{-8}$ rad/s | 第10行：zeros + diag(-1/τG) |
| 11 | $\varepsilon_{b,y}$ | 陀螺y轴零偏 | rad/s | $0.01°/h \approx 4.85\times10^{-8}$ rad/s | 第11行 |
| 12 | $\varepsilon_{b,z}$ | 陀螺z轴零偏 | rad/s | $0.01°/h \approx 4.85\times10^{-8}$ rad/s | 第12行 |
| 13 | $\nabla_{b,x}$ | 加计x轴零偏（b系） | m/s² | $10\mu g \approx 9.8\times10^{-5}$ m/s² | 第13行：diag(-1/τA) |
| 14 | $\nabla_{b,y}$ | 加计y轴零偏 | m/s² | $10\mu g \approx 9.8\times10^{-5}$ m/s² | 第14行 |
| 15 | $\nabla_{b,z}$ | 加计z轴零偏 | m/s² | $10\mu g \approx 9.8\times10^{-5}$ m/s² | 第15行 |

**etm.m 分块对应**（见 etm.m:67-70）：

$$
F_t = \begin{bmatrix}
Maa_{3×3} & Mav_{3×3} & Map_{3×3} & -Cnb_{3×3} & O_{3×3} \\
Mva_{3×3} & Mvv_{3×3} & Mvp_{3×3} & O_{3×3} & +Cnb_{3×3} \\
O_{3×3} & Mpv_{3×3} & Mpp_{3×3} & O_{3×3} & O_{3×3} \\
O_{6×9} & & & diag(-1/\tau_G)_{3×3} & \\
& & & & diag(-1/\tau_A)_{3×3}
\end{bmatrix}_{15×15}
$$

行/列的大顺序：**姿态φ(3) → 速度δv(3) → 位置δp(3) → 陀螺零偏εb(3) → 加计零偏∇b(3)**。顺序错任何一个都会导致 F×P、P×Fᵀ、H×P、K×残差 全部维度对不上。

### 2. P0 初值为什么是这些量级？

初始协方差阵 $P_0 = diag(\sigma_1^2, \sigma_2^2, \dots, \sigma_{15}^2)$ 的每条对角线工程含义：

| 状态组 | 典型σ | 工程依据 |
|--------|--------|----------|
| φ (1-3) | $10″ \sim 30″$ | SINS初始对准精度：惯导精对准后水平姿态≈10″，方位≈30″；粗对准更差 |
| δv (4-6) | 0.1 m/s | 初始速度来自 DVL/GPS 测速或静基座清零，量级约 0.05~0.2 m/s |
| δp (7-9) | 10 m | GPS单点定位（C/A码）典型水平精度 ~10m (CEP)，高度~15m |
| εb (10-12) | $0.01°/h$ | 光纤/激光陀螺中等精度：战术级 0.01~1°/h；导航级 0.001~0.01°/h |
| ∇b (13-15) | $10\mu g$ | 石英加计典型零偏：战术级 10~1000μg；导航级 1~50μg |

### 3. Q 阵驱动噪声：ARW/VRW 的量级换算

SINS 的连续系统噪声 $w(t)$ 来自陀螺角度随机游走（ARW）和加计速度随机游走（VRW）：

**常用单位换算表**（使用 glv 常量）：

| 随机游走类型 | 工程常用单位 | glv常量 | 换算到SI单位 | 公式 $Q = \sigma^2 \cdot \Delta t$ |
|--------------|-------------|---------|-------------|-----------------------------------|
| ARW（角度随机游走） | $°/\sqrt{h}$ | glv.dpsh | rad/√s | $Q_{\phi\phi} = \left(\frac{0.1°/\sqrt{h} \times glv.dpsh}{1°/\sqrt{h}}\right)^2 \times \Delta t$ |
| VRW（速度随机游走） | $m/s/\sqrt{h}$ 或 $\mu g/\sqrt{Hz}$ | glv.ugpsHz, glv.mpspsh | m/s²/√Hz → (m/s²)²·s | $Q_{\delta v \delta v} = (10\mu g/\sqrt{Hz} \times glv.ugpsHz)^2 \times \Delta t$ |
| 陀螺零偏激励 | $(°/h)/\sqrt{h}$ | glv.dphpsh | (rad/s)/√s | Gauss-Markov 模型 $\dot{\varepsilon}_b = -\varepsilon_b/\tau_G + w_G$，$Q_{GG} = \sigma_G^2 / \tau_G$ 或 PSINS 中直接写在 Qt 对角线上 |
| 加计零偏激励 | $\mu g/\sqrt{h}$ | glv.ugpsh | (m/s²)/√s | 同上，$\dot{\nabla}_b = -\nabla_b/\tau_A + w_A$ |

**PSINS kfinit(153)中具体写法**：
```
kf.Qt = diag([imuerr.web; imuerr.wdb; zeros(9,1)])^2;
```
即只在**前6个驱动噪声口**（φ的3个ARW + δv的3个VRW）输入非零白噪声，后9个状态（δp, εb, ∇b）在连续系统模型里由F阵耦合，不在Qt上直接加驱动。

### 4. Rk 观测噪声：GPS位置各向不同

松组合位置观测模型 $\boldsymbol{Z}_k = \boldsymbol{p}_{SINS} - \boldsymbol{p}_{GPS}$，其协方差：

$$
R_k = diag\left([3m,\; 3m,\; 5m]^2\right) = \begin{bmatrix} 9 & 0 & 0 \\ 0 & 9 & 0 \\ 0 & 0 & 25 \end{bmatrix} \; m^2
$$

工程依据：
- 水平方向 GPS C/A 码单点定位 ≈ 3~5m (1σ)；DGPS/SBAS ≈ 0.5~1m；RTK ≈ 1~5cm
- 高度方向 GDOP 放大 ≈ 1.5~2×，所以 5m 对应水平 3m
- 如果第7~8状态（δL, δλ）用 rad，而 GPS 观测给的是米，需要先通过 `poserrset` 把米转成 rad（除 RMh/RNhcosL），kfsetting.m 第51行 `Rk(4:5) = Rk(4:5)/glv.Re` 就是这个处理。

---

## 📝 逐行注释 (4列: 行号 / 原代码 / 中文注释 / 公式备注)

| 行号 | 原代码 | 中文注释 | 公式备注 |
|------|--------|----------|----------|
| 1 | `function kf = kfinit(ins, varargin)` | KF初始化函数入口，输入SINS结构ins+可变参数 | ins可以是struct或标量nts；varargin按kfinit标志不同解析 |
| 2 | `% Kalman filter initializes for structure array 'kf', this precedure` | 说明：KF结构初始化，通常设置Qt、Rk、Pxk、Hk | — |
| 3 | `% usually includs the setting of structure fields: Qt, Rk, Pxk, Hk.` | 四个核心字段 | 连续噪声强度Qt→离散Qk=Qt×nts；Rk直接是离散观测协方差 |
| 4 | `%` | 空 | — |
| 5 | `% Prototype: kf = kfinit(ins, varargin)` | 原型 | — |
| 6 | `% Inputs: ins - SINS structure array, if not struct then nts=ins;` | ins=结构体取ins.nts，否则ins直接当作nts（采样总时间） | — |
| 7 | `%         varargin - if any other parameters` | 可变参数：按分支解析davp/imuerr/rk/lever/dT等 | — |
| 8 | `% Output: kf - Kalman filter structure array` | 输出完成初始化的KF结构 | — |
| 9 | `%` | 空 | — |
| 10 | `% See also  kfinit0, kfsetting, kffk, kfkk, kfupdate, kffeedback, psinstypedef.` | 相关函数：kfinit0=补齐剩余字段，kfsetting=直接设定P0/Q0/R0 | psinstypedef 设置 psinsdef.kfinit=153等标志 |
| 11 |  |  |  |
| 12 | `% Copyright(c) 2009-2014, by Gongmin Yan, All rights reserved.` | 版权 | — |
| 13 | `% Northwestern Polytechnical University, Xi An, P.R.China` | 单位 | — |
| 14 | `% 09/10/2013` | 日期 | — |
| 15 | `global glv psinsdef` | 声明全局变量：glv单位常量；psinsdef模式标志 | psinsdef.kfinit=153/156/183/...；psinsdef.kffk=状态维度；psinsdef.kfhk=观测模式 |
| 16 | `[Re,deg,dph,ug,mg] = ... % just for short` | 提取常用单位简写 | 原代码只取了前5，后续ug=glv.ug |
| 17 | `    setvals(glv.Re,glv.deg,glv.dph,glv.ug,glv.mg);` | 按顺序赋值 Re,deg,dph,ug,mg | Re≈6378137m; deg=π/180; dph=deg/3600≈4.848e-6 rad/s; ug=1e-6×g0≈9.81e-6 m/s²; mg=1e-3g0 |
| 18 | `o33 = zeros(3); I33 = eye(3);` | 预分配常用3×3零/单位阵（虽然本函数未直接用） | etm.m和kffk中大量用到 |
| 19 | `kf = [];` | 先置空结构体，避免上次残留值 | — |
| 20 | `if isstruct(ins),    nts = ins.nts;` | 若ins是SINS结构体→取其累积时间nts=ins.nts | 153组合通常ins是struct，kffk需要ins做F阵 |
| 21 | `else                 nts = ins;` | 否则ins是标量，直接作为nts | 常用于纯仿真无SINS结构的场景 |
| 22 | `end` | if结束 | — |
| 23 | `switch(psinsdef.kfinit)` | 按psinsdef.kfinit标志分发到不同分支 | psinstypedef(153) 会把 psinsdef.kfinit 设为 kfinit153 |
| 24 | `    case psinsdef.kfinit153` | ★分支：15状态 + 3位置观测（SINS/GPS松组合位置-only） | kffk=15, kfhk=153 |
| 25 | `        psinsdef.kffk = 15;  psinsdef.kfhk = 153;  psinsdef.kfplot = 15;` | 设置3个配套标志：状态数15、观测153、画图维度15 | kffk=15→kffk.m里F阵出15×15；kfhk=153→kfhk出3×15的H；kfplot=15→kfplot按15组分图 |
| 26 | `        [davp, imuerr, rk] = setvals(varargin);` | 解析varargin 3个入参：davp=avp初误差；imuerr=IMU误差参数；rk=观测噪声 | 顺序必须对：调用方式 `kf = kfinit(ins, davp0, imuerr, rk)` |
| 27 | `        kf.Qt = diag([imuerr.web; imuerr.wdb; zeros(9,1)])^2;` | ★连续系统噪声强度矩阵Qt(15×15)对角：前3=ARW(φ驱动)，4-6=VRW(δv驱动)，后9状态不直接驱动 | imuerr.web=3×1 陀螺白噪声σ(°/√h→SI)；imuerr.wdb=3×1加计白噪声σ(μg/√Hz→SI)；平方是因为Qt=diag(σ)²；后9项靠F阵传递噪声 |
| 28 | `        kf.Rk = diag(rk)^2;` | ★观测噪声Rk(3×3)对角：rk是各观测量σ，平方后成方差 | rk通常=`rk = poserrset([3;3;5])`→先把米转rad/m，Rk对应 δL², δλ², δh² 的协方差 |
| 29 | `        kf.Pxk = diag([davp; imuerr.eb; imuerr.db]*1.0)^2;` | ★初始协方差P0(15×15)对角：davp=[φ;δv;δp]9个 + imuerr.eb陀螺零偏σ3个 + imuerr.db加计零偏σ3个 = 正好15个 | 乘以1.0确保double类型；开平方=σ矢量；davp常由`avperrset([10;10;30]glv.sec, 0.1, 10)`生成；eb常由`gabias(0.01glv.dph, 10*glv.ug)`生成 |
| 30 | `        kf.Hk = kfhk(0);` | ★观测矩阵Hk(3×15)：调用kfhk(153分支) | kfhk.m第16-17行：case153 → Hk = [zeros(3,6), eye(3), zeros(3,6)]。含义：观测值Zk只对7-9号位置状态敏感，H=[0¦0¦I3¦0¦0] |
| 31 | `    case psinsdef.kfinit156` | 分支：15状态+6观测（位置+速度），见test_SINS_GPS_156 | 非本wiki重点，略 |
| 32 | `        psinsdef.kffk = 15;  psinsdef.kfhk = 156;  psinsdef.kfplot = 15;` | 同上，Hk是6×15（取4-9号状态δv+δp） | — |
| 33 | `        [davp, imuerr, rk] = setvals(varargin);` | 同153 | — |
| 34 | `        kf.Qt = diag([imuerr.web; imuerr.wdb; zeros(9,1)])^2;` | 同153 | — |
| 35 | `        kf.Rk = diag(rk)^2;` | 观测6维Rk | — |
| 36 | `        kf.Pxk = diag([davp; imuerr.eb; imuerr.db]*1.0)^2;` | 同153 | — |
| 37 | `        kf.Hk = kfhk(0);` | Hk= [zeros(6,3), eye(6), zeros(6,6)] (kfhk:18-19行) | — |
| 38 | `    case psinsdef.kfinit183` | 分支：15+3杠杆臂=18状态，3位置观测（SINS/GPS杆臂补偿） | 非重点 |
| 39-67 | `(183,186,193,196,246分支...)` | 含杆臂(18)、杆臂+钟差(19)、安装矩阵(24)等组合 | 非153重点，快速跳过 |
| 68 | `    case psinsdef.kfinit246` | 24状态=15+9安装误差矩阵dKga(9) | 246=24状态+6观测 |
| 69-82 | `(303, 331, 333分支...)` | 30+状态（高阶误差模型：Ka2二次项等） | — |
| 83-131 | `(343, 346, 373, 376分支...)` | 34=15+3+1+15（杠杆+钟差+Kg）；37=34+3速度额外状态 | — |
| 132 | `    otherwise` | 以上都不匹配→通过feval扩展 | — |
| 133 | `        kf = feval(psinsdef.typestr, psinsdef.kfinittag, [{ins},varargin]);` | 用户自定义kfinit回调：在自定义typestr类型文件中实现kfinittag方法 | 扩展接口 |
| 134 | `end` | switch分支结束 | — |
| 135 | `kf = kfinit0(kf, nts);` | ★★★调用kfinit0：补齐KF结构中所有默认值，这是最容易漏看的一行 | 见下方kfinit0关键作用：Qk=Qt×nts离散化；Pmax/Pmin默认值；adaptive/pconstrain开关；xk初值0；Kk/Hk尺寸；fading/xtau/coef_fb反馈系数等 |

### 附：kfinit0.m 中的关键字段（由第135行自动设置）

| 字段 | 来源行 | 默认值/公式 | 含义 |
|------|--------|------------|------|
| `kf.nts` | kfinit0:5 | 输入nts | 离散KF时间步长，Qk=Qt×nts |
| `kf.xk` | kfinit0:13 | zeros(n,1) | 初始状态误差估计全部为0（误差状态定义下，初始估计为"无误差"） |
| `kf.Qk` | kfinit0:14 | `kf.Qt*kf.nts` | ★离散化系统噪声：$Q_k = Q_c \cdot \Delta t$（白噪声Euler积分近似） |
| `kf.Pmax` | kfinit0:34 | `(diag(Pxk)+1)×1e10` | P上界：默认极大≈1e10倍P0，等价于无约束；若在kfsetting中显式设则覆盖 |
| `kf.Pmin` | kfinit0:35 | 全0 | P下界：默认不收缩；kfsetting会重写为`P0×1e-3`左右，防止P太小时KF不信观测 |
| `kf.adaptive` | kfinit0:20 | 0（关）；kfsetting:60设1 | Sage-Husa自适应：adaptive=1时，在线调整Q/R阵；b=0.5遗忘因子，beta=1偏置 |
| `kf.pconstrain` | kfinit0:33 | 0（关）；kfsetting:61设1 | P协方差约束：pconstrain=1时，每次更新后将Pxk夹在[Pmin, Pmax]之间，防止数值发散 |
| `kf.fading` | kfinit0:19 | 1（无遗忘） | 渐消因子：fading>1时旧数据权重降低 |
| `kf.xconstrain` | kfinit0:32 | 0 | 状态硬约束开关 |
| `kf.T_fb / coef_fb` | kfinit0:30,42 | T_fb=1秒 | 状态反馈时间常数：kffeedback不是一步全反馈，而是 coef_fb = T_fb / max(xtau, T_fb) 渐进反馈（防超调） |

---

## 🔍 断点调试建议

### 调试1：初始化后P对角线单位是否正确

1. 在 `/workspace/psins/demos/test_SINS_GPS_153_kfstat.m` 第18行 `kf = kfinit(...)` 后立即打断点；
2. 命令窗口执行：
   ```matlab
   format shortE
   diag_sigma = sqrt(diag(kf.Pxk))
   % 换算成人类可读单位：
   phi_sigma_deg = diag_sigma(1:3)/glv.deg * 3600  % rad → arcsec
   eb_sigma_dph = diag_sigma(10:12)/glv.dph        % rad/s → deg/h
   db_sigma_ug  = diag_sigma(13:15)/glv.ug         % m/s² → ug
   ```
3. **预期结果**：
   - phi_sigma ≈ 10 arcsec，即约 4.848e-5 rad；
   - eb_sigma ≈ 0.01 deg/h，即约 4.848e-8 rad/s；
   - db_sigma ≈ 10 ug；
   - 若差一个 3600、180/π、或 1e6 的倍数，说明 avperrset / gabias 调用时单位没乘 glv.sec / glv.dph / glv.ug。

### 调试2：第一次时间更新后 P(1,1) 增量量级验证

1. 在第30行 `kf = kfupdate(kf);` 第1次执行完后断点；
2. 比较 `kf.Pxk(1,1)` 前后差值 ΔP11；
3. **预期量级**：

$$
\Delta P_{11} \approx Q_{11} = Q_{t,11} \times nts
$$

   若 ARW=0.1°/√h = 0.1×glv.dpsh rad/√s，则 Qt(1,1)=(0.1dpsh)²≈(4.85e-8)²≈2.35e-15 rad²/s；乘以nts=0.02s得 ΔP≈4.7e-17，所以 P(1,1) 从 (10″)²=2.35e-9 增加约 4.7e-17，增量是P0的~5e-8倍，几乎不变。
4. 如果发现 P(1,1) 一跳变几倍，那就是 Qt 里 ARW 单位换算错了（比如写成 0.1 dph 而非 0.1 dpsh，差 √3600≈60 倍 → 平方差3600倍）。

### 调试3：Hk矩阵的位置列是否真在第7~9列

断点下执行 `spy(kf.Hk)` 看稀疏图：3行×15列矩阵的第(1,7)(2,8)(3,9)位置必须是1，其余为0。如果发现1出现在(1,1)(2,2)(3,3)，说明状态顺序与Hk错位了（比如误以为φ是第7~9），那观测残差会直接把姿态当位置观测，**KF会完全失效**。

---

## ❌ 初学者最容易踩的坑

### 坑1：15状态顺序搞混（φ/εb混序 或 δp与δv颠倒）
**现象**：kfupdate运行不报错，但kf.xk(1:3)姿态估计极大（几十度），位置误差几十km不收敛，残差 `Z-Hk*xk` 一开始就是巨大值。
**典型错误顺序**：
- ❌ 错误：[φ(3); εb(3); δv(3); δp(3); ∇b(3)] → 后12号状态全错位
- ✅ 正确：[φ(3); δv(3); δp(3); εb(3); ∇b(3)] → etm.m分块顺序严格对应
**验证方式**：第1次kffk后，`size(kf.Phikk_1)=15×15`，且 `sum(diag(kf.Phikk_1)) ≈15`（F阵对角≈I，短Δt下离散化Φ≈I+FΔt对角≈15+trace(F)Δt）。

### 坑2：Pmin 设置太高（≥P0）导致 P 永远缩不下去
**现象**：KF跑很久后 `sqrt(diag(kf.Pxk))` 基本不变，和P0一样大，状态估计xk虽然小但不是靠观测收的，而是"盲猜"。
**原因**：kfsetting里Pmin默认值如果写得和P0同量级（或者pconstrain=1时设置错），每次更新完 `Pxk = max(Pxk, Pmin)` 会把刚被观测缩小的P又"顶回去"。
**正确范围**：通常 Pmin ≈ P0 × 1e-3 ~ 1e-2。比如P0(φ)=10″，则Pmin(φ)=0.01″~0.1″，是物理上能收敛到的极限。

### 坑3：KF状态维度15与etm.m的F阵维度不一致
**现象**：kffk返回时直接报错 `Inner matrix dimensions must agree`，或者 `Matrix dimensions must agree`。
**排查步骤**：
1. 检查 psinsdef.kffk 是否=15（kfinit:25设了，但之前如果跑过别的demo可能还留18/19等）；
2. etm.m 第16行默认 n=15，但kffk如果显式传n=18等就不对；
3. kf.Hk 维度：3×15对，但 Hk×Pxk×Hk' 报错说明 Pxk 不是15×15 → 往回找 Pxk 初始化错在哪。

### 坑4：观测噪声Rk单位没把"米"换成"rad"对经纬度
**现象**：纬度/经度误差收敛极慢（比预期慢1e6倍），高度正常。
**原因**：δL和δλ的单位是rad，而rk输入是米，需要 `rk(1:2) = rk(1:2)/Re` 预处理。kfsetting.m第51行 `Rk(4:5) = Rk(4:5)/glv.Re` 就是干这个。而 `poserrset` 函数也会自动转。如果手动写 `rk=[3;3;5]` 忘了除Re，Rk(1,1)=9 rad²≈(1000km)²，GPS观测几乎被KF"完全不信"。

### 坑5：adaptive=1开启但初始Q/R数量级差太远
**现象**：KF前几十秒Q阵或R阵被Sage-Husa自适应"跑飞"，变成0或Inf。
**原因**：Sage-Husa自适应需要初始Q、R是**同一量纲体系下大致正确**的，否则Q太小→自适应补Q但一步调太大；R太大→自适应把R调0→残差=0→增益无穷大。
**稳妥使用**：前100秒 `kf.adaptive=0` 让P先自然收敛到合理值，之后再 `kf.adaptive=1` 开启自适应。

---

## 🎯 配套练习

### 练习1：把P0(1:3)从10″改到10°，观察收敛速度变慢多少

1. 打开 `/workspace/psins/demos/test_SINS_GPS_153_kfstat.m`；
2. 第14行改为：
   ```matlab
   davp0 = avperrset([10;-10;10]*glv.deg, 0.1, [1;1;3]);  % 姿态初误差10°（×10000倍）
   ```
3. 第17-18行保持rk不变，跑完整仿真；
4. **对比原版（10″初误差）和修改版（10°初误差）**：
   - 画出 φ_x(1号状态) vs t 两条曲线同一图上；
   - 原版可能在前10秒φ就被观测拉到<1′；
   - 修改版因为P0的φ分量大10⁸倍，KF前几秒几乎完全相信模型而非观测（因为 K=PHᵀ(HPHᵀ+R)⁻¹，H对应φ的部分=0，只能通过F阵耦合到δp才能被位置观测修正），可能要 **300~1000秒** 才能把10°误差逐步"传"到位置再收回来。
5. **思考题**：如果把GPS位置观测换成156速度+位置双观测，收敛速度会加快多少倍？（提示：Hk的δv对应位置非零，F中φ→δv是直接耦合Mva，比φ→δp快一个积分阶次）。

### 练习2：改变Rk量级观测权值，画出位置误差 vs Rk的曲线

1. 固定P0和Qt，分别设 `rk = poserrset([1;1;2])`、`[3;3;5]`、`[10;10;20]`、`[30;30;50]` 共4组；
2. 每组跑完取最后60s内位置RMSE平均 `mean(sqrt(sum(xkpk(end-600:end,7:9).^2,2)))`（注意xkpk里是xk还是diag(Pxk)，看列索引）；
3. **理论预期**：当Rk≥P0×(HPHᵀ)量级后，KF"不信观测"→误差趋近纯SINS发散值；当Rk→0时，误差≈纯GPS精度+系统不可观部分（姿态/零偏由耦合定），不会随Rk减小继续下降。把4个(Rk_水平, RMSE_水平)点画在loglog图上，看是否存在一个"拐点"对应 Rk≈1~3m 正好是GPS单点精度区间。
