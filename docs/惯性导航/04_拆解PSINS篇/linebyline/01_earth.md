# earth.m 逐行注释 Wiki (PSINS)

> 配套源码: [earth.m](../../assets/psins260314/base/base1/earth.m)
> 所属层级: L0基础 / L1纯惯导
> 前置依赖: [glvf.m](00_glvf.md)（必须先读glvf，因为earth依赖glv全局变量）
> 学习目标: 读完后你应能回答哪3个问题
>
> 1. n系下的三个角速度 wnie、wnen、wnin 各是什么物理意义？方向怎么判断？
> 2. 子午圈曲率半径 RM 和 卯酉圈曲率半径 RN 的公式是什么？它们和位置(lat,h)的关系？
> 3. 惯导速度微分方程里的 gcc 项，为什么是重力减离心减科里奥利？它和 gn 差在哪里？

***

<br />

<br />

## 🧩 函数作用一句话

给定位置和速度，计算n系下的地球参数：曲率半径、地转角速度、运载体角速度、重力、科里奥利项。

***

## 📐 数学原理 / 物理意义

earth() 是纯惯导解算的"地心参数计算器"。SINS 的机械编排（Mechanization）每一步都需要地球相关参数，它们都 **随着纬度和高度动态变化**。earth() 就是把这些变化打包好，输出到 `eth` 结构体里。

### 1. 导航坐标系约定（n系 = 东-北-天 坐标系，ENU）

PSINS 统一使用：

- n系轴顺序：**东(E)、北(N)、天(U)**，即 `[vn_E; vn_N; vn_U]`
- 所以位置 pos = \[纬度 lat; 经度 lon; 高度 hgt]，**注意第一个分量是纬度(北方向)不是经度！**
- 速度 vn = \[东向速度 vE; 北向速度 vN; 天向速度 vU]

### 2. 两个曲率半径 RM、RN

地球不是球，沿 **子午线（南北切）** 的曲率叫 **子午圈曲率半径** **$R_M$**，沿 **卯酉圈（东西切）** 的叫 **卯酉圈曲率半径** **$R_N$**：

$$
R_M = \frac{R_e(1-e^2)}{(1-e^2\sin^2 L)^{3/2}}, \quad R_N = \frac{R_e}{\sqrt{1-e^2\sin^2 L}}
$$

其中 $L$ = 纬度 lat，$e^2$ = 第一偏心率平方。加上海拔高度 h 就得到：

$$
R_{Mh} = R_M + h, \quad R_{Nh} = R_N + h
$$

直觉：在两极，sinL=±1，RM=RN（椭球极点附近像球）；在赤道，sinL=0，RN 最大（=Re），RM 最小。永远满足 **RN ≥ RM**，差别 \~21 km（赤道处最大）。

### 3. 三个关键角速度（SINS机械编排的灵魂）

捷联惯导姿态/速度/位置微分方程都和"坐标系旋转角速度"有关。三个核心角速度层层递进。

> 📌 **前置概念**：如果"相对于"和"投影到"还不清楚，请先读 [00a\_INSBasics.md §8](00a_INSBasics.md) 的"角速度符号约定"。核心记忆：$\omega_{AB}$ = **B 系相对于 A 系**的角速度，上标 = 投影到哪个系。

#### (1) $\omega_{ie}^n$ —— 地球自转角速度（e系相对于i系，投影到n系）

$$
\omega_{ie}^n = \begin{bmatrix} 0 \\ \omega_{ie}\cos L \\ \omega_{ie}\sin L \end{bmatrix}
$$

物理直觉：地球自转轴是 **南北极连线**。在 n 系分解：

- 东向(1) = 0（转轴垂直东方向，永远没有东向分量）
- 北向(2) = ωᵢₑ·cosL（在赤道 cosL=1，全部朝北；在北极 cosL=0，为0）
- 天向(3) = ωᵢₑ·sinL（在北极 sinL=1，全部朝天向上）

#### (2) $\omega_{en}^n$ —— n系相对于e系的旋转角速度（载体移动引起）

当你在地球表面移动时，"当地水平坐标系（n系）"的方向也在跟着改变：

$$
\omega_{en}^n = \begin{bmatrix} -\frac{v_N}{R_{Mh}} \\ \frac{v_E}{R_{Nh}} \\ \frac{v_E}{R_{Nh}} \tan L \end{bmatrix}
$$

物理直觉（重点！）：

- **东向分量 ω\_en\_E = -vN / R\_Mh**：你 **向北走 vN**，n系的东轴会向西旋转（绕东轴本身转0，但绕的是"东轴为转轴"——你向北翻山时，当地水平面的俯仰变化对应角速度方向向东（右手定则：头北脚南向前倾，角速度指向东），但北向速度引起的是 **n系绕东轴** 的旋转，符号为负是因为速度向北时，原来的北方向下弯，角速度分量为 -vN/R。
- **北向分量 ω\_en\_N = vE / R\_Nh**：你 **向东走 vE**，n系的北轴方向绕北向轴本身不变，但是"绕北向轴"——你向东走相当于转经度，当地水平面的偏航变化，角速度指向北。
- **天向分量 ω\_en\_U = vE·tanL / R\_Nh**：你 **向东走 vE**，除了北向轴转，还有一个 **绕天轴（竖直轴）** 的转动！这叫"测地线进动"，在南北极附近 tanL→∞ 会爆炸，所以高纬度不能用普通 n 系，要切换成格网坐标系或ECEF系。

#### (3) $\omega_{in}^n = \omega_{ie}^n + \omega_{en}^n$ —— n系相对于i系的总角速度

简单的 **角速度叠加原理**：e系相对i系以 ω\_ie 转，而n系相对e系又以 ω\_en 转，故 n系相对i系的总角速度就是两者之和。SINS 的姿态四元数更新方程用的就是这个：

$$
\dot{\mathbf{q}}_b^n = \frac{1}{2}\mathbf{q}_b^n \otimes \begin{bmatrix}0 \\ \omega_{ib}^b - (\omega_{ie}^n + \omega_{en}^n)\end{bmatrix}
$$

### 4. 重力、引力、离心力、科里奥利力的区别

导航里最容易混的四个概念：

- **引力（Gravitation）**：纯万有引力，方向指向地心附近
- **重力（Gravity）g**：引力 减去 **离心力**（地球自转甩出去的力），g 才是我们站在地面上秤出来的 9.78\~9.83 m/s²。重力方向垂直当地水平面（即 -天方向）。
- **比力（Specific Force）f**：加速度计测的东西 = 载体相对惯性系加速度 减 引力。即：**加速度计量测 = 运动加速度 + 重力**（注意符号！静止时比力朝上 = 重力大小）。
- **科里奥利力（Coriolis）**：由于参考系（n系）本身在旋转，对运动物体产生的虚拟力 $a_{\text{cor}} = -2\omega_{ie}^n \times \mathbf{v}^n$。

SINS 速度微分方程：

$$
\dot{\mathbf{v}}^n = \mathbf{C}_b^n \mathbf{f}^b - (2\omega_{ie}^n + \omega_{en}^n) \times \mathbf{v}^n + \mathbf{g}^n
$$

右边第2项同时含 **科里奥利（2ω\_ie×v）** 和 **离心（ω\_en×v 包含部分）** 效应，整个这一大项（含重力 g^n）在 earth() 里被组合成 `gcc` 向量，直接在 `insupdate.m` 里调用：

$$
\text{gcc} = \mathbf{g}^n - \omega_{ie+in}^n \times \mathbf{v}^n
$$

这样写的好处是比单独算叉乘更快（代码L33-35展开了叉乘公式，避免调用 `cros()` 函数开销）。

***

## 📝 逐行注释（36行，一行不落）

|   行号   | 原代码                                                                                                       | 中文注释                                                                     | 公式/备注                                                                                                                                                                                                   |
| :----: | :-------------------------------------------------------------------------------------------------------- | :----------------------------------------------------------------------- | :------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
|    1   | `function eth = earth(pos, vn)`                                                                           | 函数声明。输入位置pos=\[lat;lon;h]、速度vn=\[vE;vN;vU]；返回地球参数结构体eth                  | 注意顺序：**先lat后lon**，**先E后N后U**                                                                                                                                                                            |
|  2-10  | `% Calculate the Earth related parameters...`                                                             | 函数说明注释。相关函数还有 ethinit、ethupdate、insupdate、trjsimu                        | 原型: eth = earth(pos, vn)                                                                                                                                                                                |
|  11-13 | `% Copyright(c) 2009-2014...`                                                                             | 版权信息：严恭敏，西工大，2009/06/02                                                  | <br />                                                                                                                                                                                                  |
|   14   | `global glv`                                                                                              | 引入全局glv结构体，earth依赖 glv.Re、glv.e2、glv.wie、glv.g0、glv.beta等                | 所以 glvf() 必须先调用过                                                                                                                                                                                        |
|   15   | `if nargin==1, vn = [0; 0; 0]; end`                                                                       | 如果只传了位置没传速度，默认vn = \[0;0;0] 三零速度                                         | 静态时（静止基座）直接 earth(pos) 即可                                                                                                                                                                               |
|   16   | `eth = glv.eth;`                                                                                          | **内存分配技巧**：直接把 glv 里存的上一次 eth 拷过来。MATLAB是动态数组语言，先分配好字段再逐个赋值比一行行新建字段快得多   | 注意：glv.eth 在 glvf.m L103 已被初始化过，所以这里一定有东西                                                                                                                                                               |
|   17   | `eth.pos = pos; eth.vn = vn;`                                                                             | 把输入的位置和速度存回eth结构体，供外部查阅                                                  | <br />                                                                                                                                                                                                  |
|   18   | `eth.sl = sin(pos(1)); eth.cl = cos(pos(1)); eth.tl = eth.sl/eth.cl;`                                     | 一次算出 **纬度** L=pos(1) 的 sinL、cosL、tanL                                    | **存成 sl/cl/tl 后面反复用，避免每次重算 sin/cos！** 这是严老师代码的风格                                                                                                                                                        |
|   19   | `eth.sl2 = eth.sl*eth.sl; sl4 = eth.sl2*eth.sl2;`                                                         | 继续派生出 sin²L 和 sin⁴L，后面正常重力公式用到                                           | sl4 = sin⁴L 是局部变量，不存eth                                                                                                                                                                                 |
|   20   | `sq = 1-glv.e2*eth.sl2; sq2 = sqrt(sq);`                                                                  | 计算两个辅助量：sq = 1-e²sin²L，sq2 = √sq = (1-e²sin²L)^0.5                       | 这是 RM、RN 分母的公共项，先算好避免重复                                                                                                                                                                                 |
|   21   | `eth.RMh = glv.Re*(1-glv.e2)/sq/sq2+pos(3);`                                                              | **子午圈曲率半径 + 高度**                                                         | $R_{Mh} = \frac{R_e(1-e^2)}{(1-e^2\sin^2L)^{3/2}} + h$，注意分母是 sq^1.5 = sq·sq2                                                                                                                            |
|   22   | `eth.RNh = glv.Re/sq2+pos(3); eth.clRNh = eth.cl*eth.RNh;`                                                | **卯酉圈曲率半径 + 高度**，再额外缓存一份 cosL·RNh                                        | $R_{Nh} = \frac{R_e}{\sqrt{1-e^2\sin^2L}} + h$。clRNh = cosL·R\_Nh，后面位置更新要除以它                                                                                                                            |
| **23** | **`eth.wnie = [0; glv.wie*eth.cl; glv.wie*eth.sl];`**                                                     | **ω\_ie^n：地球自转角速度（e系相对于i系，投影到n系）**                                       | $\begin{bmatrix} 0 \\ \omega_{ie}\cos L \\ \omega_{ie}\sin L \end{bmatrix}$，单位 rad/s分量：E向=0（永远！），N向=ωcosL，U向=ωsinL                                                                                      |
|   24   | `vE_RNh = vn(1)/eth.RNh;`                                                                                 | 先算 vE/RNh，省得 L25 重复写两次                                                   | vn(1) = 东向速度 vE                                                                                                                                                                                         |
| **25** | **`eth.wnen = [-vn(2)/eth.RMh; vE_RNh; vE_RNh*eth.tl];`**                                                 | **ω\_en^n：运载体运动引起的n系相对e系的旋转角速度**                                         | $\begin{bmatrix} -v_N/R_{Mh} \\ v_E/R_{Nh} \\ v_E\tan L/R_{Nh} \end{bmatrix}$(1) **东向** = -vN/RMh：北向速度→n系绕东轴旋转（俯仰角速度）(2) **北向** = vE/RNh：东向速度→n系绕北轴旋转（翻滚角速度）(3) **天向** = vE·tanL/RNh：东向速度引起的方位旋转（测地线进动） |
| **26** | **`eth.wnin = eth.wnie + eth.wnen;`**                                                                     | **ω\_in^n：n系相对i系的总角速度 = ω\_ie + ω\_en**                                  | 角速度叠加原理。SINS四元数更新时，要从陀螺角增量里减去这个（补偿旋转）                                                                                                                                                                   |
| **27** | **`eth.wnien = eth.wnie + eth.wnin;`**                                                                    | **ω\_ie + ω\_in = 2ω\_ie + ω\_en**                                       | 这就是速度微分方程里叉乘 v^n 的那个系数！后面 gcc 会用到                                                                                                                                                                       |
|   28   | `% eth.g = ...GJB6304-2008,Eq.(B.5)`                                                                      | 【注释保留】国军标正常重力公式，严老师换了更精确的 Somigliana 闭式                                  | GJB公式：g = g₀(1+5.279e-3sin²L+2.327e-5sin⁴L) - 3.086e-6·h                                                                                                                                                |
|   29   | `gL = glv.g0*(1+glv.beta*eth.sl2-glv.beta1*(2*eth.sl*eth.cl)^2); hR = pos(3)/(glv.Re*(1-glv.f*eth.sl2));` | 两步计算重力：先算 **海平面** 正常重力gL（Somigliana公式近似），再算 **高度比** hR = h / 平均半径        | gL 是 h=0 时的重力，随纬度增加而增大（赤道9.78 → 两极9.83）                                                                                                                                                                 |
|   30   | `eth.g = gL*(1-2*hR-5*hR^2);`                                                                             | 海平面重力 gL 乘以高度衰减因子 (1-2hR-5hR²)                                           | 直觉：高度越高，离地心越远，重力越小。h=10km时，hR≈0.0016，g≈gL×0.9968，约减 0.03 m/s²                                                                                                                                           |
|   31   | `eth.gn = [0;0;-eth.g];`                                                                                  | **n系下的重力向量 g^n**                                                         | 重力方向沿 **-天方向**（朝下），所以只有U向分量是 -g，E/N=0。单位 m/s²                                                                                                                                                           |
|   32   | `% eth.gcc = eth.gn - cros(eth.wnien,vn);`                                                                | 【注释保留】gcc = 重力 - (ω\_ie+ω\_in) × v。原来写的是调用 `cros()` 叉乘函数，但函数调用开销大，所以直接展开 | cros(a,b)=a×b                                                                                                                                                                                           |
| **33** | **`eth.gcc = [ eth.wnien(3)*vn(2) - eth.wnien(2)*vn(3);`**                                                | **叉乘展开第1行（东向分量）**                                                        | $(\omega \times \mathbf{v})_E = \omega_N v_U - \omega_U v_N$所以 gcc\_E = 0 - (ω\_Nv\_U - ω\_Uv\_N) = ω\_Uv\_N - ω\_Nv\_U                                                                                 |
| **34** | **`eth.wnien(1)*vn(3) - eth.wnien(3)*vn(1);`**                                                            | **叉乘展开第2行（北向分量）**                                                        | $(\omega \times \mathbf{v})_N = \omega_U v_E - \omega_E v_U$gcc\_N = 0 - (ω\_Uv\_E - ω\_Ev\_U) = ω\_Ev\_U - ω\_Uv\_E                                                                                    |
| **35** | **`eth.wnien(2)*vn(1) - eth.wnien(1)*vn(2) + eth.gn(3) ];`**                                              | **叉乘展开第3行（天向分量） + 重力**                                                   | $(\omega \times \mathbf{v})_U = \omega_E v_N - \omega_N v_E$gcc\_U = g\_U(=-g) - (ω\_Ev\_N - ω\_Nv\_E) = ω\_Nv\_E - ω\_Ev\_N + (-g)这一行多了 +eth.gn(3) 是因为重力只有天向分量                                         |
|   36   | `（空行）`                                                                                                    | 结束空行，MATLAB 函数一般最后留一个空行                                                  | <br />                                                                                                                                                                                                  |

***

## 🔍 断点调试建议

**推荐断点设置和观察：**

1. **第23行（wnie计算后）**
   设定 lat = 34°（西工大≈34°N），h=0，vn=0。
   - wnie(1) 必须 = **0**（东向永远没分量，这是检查bug的好指标！）
   - wnie(2) = 7.292e-5 × cos(34°) ≈ 7.292e-5 × 0.8290 ≈ **6.046e-5 rad/s**（北向）
   - wnie(3) = 7.292e-5 × sin(34°) ≈ 7.292e-5 × 0.5592 ≈ **4.078e-5 rad/s**（天向）
   - 验证：wnie(2)² + wnie(3)² 应该 ≈ glv.wie² = (7.292e-5)² ≈ 5.317e-9
2. **第25行（wnen计算后）**
   继续上面位置，现在给 vn = \[100; 200; 0] m/s（vE=100东, vN=200北, vU=0）
   先估算 RM ≈ RN ≈ 6.37e6 m（34°时 RM≈6.36e6, RN≈6.38e6）
   - wnen(1) = -200 / 6.36e6 ≈ **-3.14e-5 rad/s**（东向角速度，符号负）
   - wnen(2) = 100 / 6.38e6 ≈ **+1.57e-5 rad/s**（北向角速度，正）
   - wnen(3) = 100 × tan(34°) / 6.38e6 ≈ 100 × 0.6745 / 6.38e6 ≈ **1.057e-5 rad/s**（天向，正）
     和实际值相对误差 < 1% 就算过。
3. **第26、27行（wnin / wnien）**
   wnin = wnie + wnen，直接相加核对。wnien = wnie + wnin = 2wnie + wnen。
   - 特别关注：wnien(1) = wnie(1) + wnin(1) = 0 + wnen(1) = wnen(1)
4. **第30、31行（g 和 gn）**
   在 lat=34°，h=0：
   - eth.g 应该在 **9.797 m/s² 左右**（赤道9.780，两极9.832，34°N约9.797）
   - gn = \[0; 0; -9.797]，对的，只有U向负分量。
   - 再试 lat=90°（北极），h=0：g≈9.832；lat=0°（赤道），g≈9.780。
5. **第35行（gcc计算后）**
   vn=0 时，**gcc 应该完全等于 gn**（因为 ω×v 全是0）。这是最容易的检查。
   vn≠0 时，手算 (ω×v) 展开和代码对。

***

## ❌ 初学者最容易踩的坑

### 坑1：位置 pos 的顺序！\[lat; lon; h] 不是 \[lon; lat; h]

`pos(1) = 纬度 lat（北南）`，`pos(2) = 经度 lon（东西）`。很多地图软件先写经度，把顺序搞反。比如西工大长安校区 lat≈34°N，lon≈109°E，如果你写成 \[108.77°; 34.03°; 450]，相当于把经纬度互换，sinL=sin(108.77°)还是正的，但纬度已经 108° 超过 90° 物理不可能，后面 tanL 变号、wnie 都会错得离谱。

### 坑2：速度 vn 的顺序！\[vE; vN; vU] 不是 \[vN; vE; vU]

`vn(1) = 东向速度 v_E`，`vn(2) = 北向速度 v_N`。wnen 的公式里这两个差一个负号和一个 tanL，顺序反了 wnen(1)(2)(3) 全错，后面姿态、速度更新全乱。

### 坑3：重力方向是 -U 方向！`gn = [0;0;-g]` 不是 +g

很多初学者以为重力"把东西往下拉"，向量应该朝下=+U（天向上）。错！**天向 U 是朝上的正方向**，重力向下，所以 gn(3) = -g 是 **负数**。如果你写成 +g，静止时比力（+g）加重力（+g）=2g ，速度直接往天上冲。

### 坑4：wnen 的 3 号分量 tanL 在南北极爆炸

lat=±90°（南北极）时，tanL → ∞，wnen(3) 无穷大。所以 **极区（|lat|>80°左右）不能用普通n系导航**，必须切换成"格网坐标系"或直接用 ECEF。PSINS 的 polar/ 目录就是专门解决这个问题的。

### 坑5：`wnien` 是 `2ω_ie + ω_en`，不是 `ω_ie + 2ω_en`

SINS速度方程是 $\dot{\mathbf{v}}^n = \mathbf{C}_b^n\mathbf{f}^b - (2\omega_{ie}^n + \omega_{en}^n)\times\mathbf{v}^n + \mathbf{g}^n$。那个叉乘前的系数是 **2 倍 wnie + 1 倍 wnen**，所以 `wnien = wnie + wnin = wnie + (wnie+wnen) = 2wnie + wnen`。如果你写成 wnie + 2\*wnen，科里奥利少了一半，偏东速度vE会导致位置误差量级不对。

***

## 🎯 配套练习

### 练习1：手算 earth.m 输出，MATLAB 校验（误差<1e-12）

**题目**：给定

- 位置 pos = \[30°; 120°; 1000m]（北纬30°，东经120°，海拔1000米）
- 速度 vn = \[50 m/s东; -100 m/s南; +10 m/s升] = \[50; -100; 10]

**任务**：

1. 手算（或用计算器按公式）：
   - sinL、cosL、tanL
   - sq = 1 - e²sin²L （e² = 0.00669437999014132）
   - RMh = Re(1-e²)/sq^1.5 + 1000
   - RNh = Re/√sq + 1000
   - wnie = \[0; wie·cosL; wie·sinL] （wie = 7.2921151467e-5）
   - wnen = \[-vN/RMh; vE/RNh; vE·tanL/RNh] （注意 vN 这里是 -100，负号套进去！）
   - wnin = wnie + wnen
   - wnien = wnie + wnin
   - 任选重力公式算 g，然后 gn = \[0;0;-g]
   - gcc = gn - wnien×vn（叉乘公式展开）
2. MATLAB 跑：

```matlab
glvf();
pos = [30*glv.deg; 120*glv.deg; 1000];
vn  = [50; -100; 10];
eth = earth(pos, vn);
```

1. 把你手算的和 eth.wnie(2)、eth.wnen(1)、eth.wnen(3)、eth.RMh、eth.RNh、eth.g 逐一对比，**相对误差 < 1e-12** 算通过。

### 练习2（思考题）：vn = \[0;0;0] 时，gcc 和 gn 是否相等？为什么？

用 MATLAB 试一下 `eth = earth([34*glv.deg;108*glv.deg;400])` （不传vn），然后 `norm(eth.gcc - eth.gn)`，看结果是否为 0。解释为什么。
