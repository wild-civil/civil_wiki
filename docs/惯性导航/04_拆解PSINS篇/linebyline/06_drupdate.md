# 06_drupdate 逐行注释 Wiki (PSINS)

> 配套源码: [drupdate.m](file:///workspace/psins/base/base1/drupdate.m)
> 所属层级: L2 DR 航位推算
> 前置依赖: 00_glvf / 01_earth / 03_insupdate / 08_kffk / 09_kfupdate
> 学习目标: 读完回答3个问题
>
> 1. DR的3个核心误差状态是什么？为什么位置误差是线性发散（无舒勒振荡）？
> 2. `pos = pos + Mpv·Cnb·[0;0;s]` 这一行中，b系前向为什么是z轴而不是x轴？
> 3. 为什么SINS/DR组合中通常SINS做参考（给姿态），DR做观测，而不是反过来？

---

## 🧩 函数作用一句话

基于陀螺角增量积分更新姿态四元数，结合里程计距离增量 dS，通过方向余弦矩阵将 b 系前向里程增量投影到 n 系，再经 Mpv 位置变换矩阵累加得到纬度/经度/高度，完成一次 Dead Reckoning（航位推算）更新。

---

## 📐 数学原理 / 物理意义

### 1. DR = 纯陀螺方位 + 里程计距离增量

航位推算（Dead Reckoning）的核心思想是：**已知上一时刻位置和航向，通过测量航向变化和行进距离，递推当前时刻位置**。

离散时间更新方程（二维平面简化版）：

$$
\begin{cases}
\psi(k+1) = \psi(k) + \Delta\theta_z^{(陀螺)} \\
S(k+1) = S(k) + \Delta S^{(里程计)} \\
x(k+1) = x(k) + S \cdot \sin\psi \\
y(k+1) = y(k) + S \cdot \cos\psi
\end{cases}
$$

其中 $\psi$ 为方位航向角，$S$ 为累计行驶距离，$(x,y)$ 为平面位置。

在 PSINS 中，完整的三维更新为：

$$
d\boldsymbol{r}^n = \boldsymbol{M}_{pv} \cdot \boldsymbol{C}_b^n \cdot d\boldsymbol{s}^b
$$

其中 $d\boldsymbol{s}^b = [0;0;\Delta S]$ 表示里程计增量沿 b 系前向（z 轴方向约定）。

### 2. DR的误差方程（3状态）与线性发散特性

DR误差状态向量取为 $\boldsymbol{X}_{DR} = [\varepsilon_\psi, \delta x, \delta y]^T$，即方位角误差、北向位置误差、东向位置误差。

误差传播方程：

$$
\dot{\boldsymbol{X}}_{DR} = \begin{bmatrix} 0 & 0 & 0 \\ V\cos\psi & 0 & 0 \\ -V\sin\psi & 0 & 0 \end{bmatrix} \boldsymbol{X}_{DR} + \boldsymbol{w}
$$

该系统的关键特征：
- **F 阵特征值全为 0**：系统是临界稳定的，没有振荡模态；
- **无舒勒振荡**：SINS 中位置误差通过比力反馈到姿态形成 84.4 分钟舒勒周期，但 DR 中没有重力/比力观测，位置误差和姿态误差之间不存在闭环反馈；
- **位置误差线性发散**：$\delta x(t) \approx V \cdot \varepsilon_\psi \cdot t$，随时间 $t$ 线性增长，而非 SINS 中的振荡。直观理解：恒定航向偏差 $\varepsilon_\psi$ 导致每米行驶产生 $V\varepsilon_\psi$ 的横向偏移，总偏移随路程线性累积。

### 3. 为什么通常 SINS 做观测源给 DR，而不是反过来

| 维度 | SINS | DR（纯陀螺+ODO） |
|------|------|------------------|
| 姿态 | 有舒勒约束，俯仰/滚转短期稳定 | 只有陀螺积分，俯仰/滚转无参考长期漂移 |
| 位置 | 双积分，舒勒振荡+随 $t^2$ 发散 | 单积分，随 $t$ 线性发散，短期精度优于SINS |
| 速度 | 有（积分加速度） | 无（只能用 $dS/\Delta t$ 近似） |
| 独立性 | 不依赖外部传感器 | 依赖车辆运动（静止时odo=0不可观） |

组合策略：
- **SINS → DR**：SINS 提供完整的俯仰/滚转姿态（`dr.qnb = ins.qnb`，见 test_SINS_DR.m 第27行），DR只负责用里程计补位置短期精度；
- **DR → SINS**：DR位置作为观测输入到KF，修正SINS的位置/速度/姿态误差（松组合位置观测）。

如果反过来用DR给SINS姿态，车辆加减速时DR没有独立的俯仰参考，姿态会严重发散。

---

## 📝 逐行注释 (4列: 行号 / 原代码 / 中文注释 / 公式备注)

| 行号 | 原代码 | 中文注释 | 公式备注 |
|------|--------|----------|----------|
| 1 | `function dr = drupdate(dr, imu, dS)` | DR更新函数入口，输入DR结构、IMU陀螺数据、里程计距离增量 | 输入 `dr` 由 `drinit` 初始化；`imu` 通常只取前3列陀螺角增量 |
| 2 | `% Dead Reckoning(DR) attitude and position updating.` | 函数说明：DR姿态与位置更新 | — |
| 3 | `%` | 空注释行 | — |
| 4 | `% Prototype: dr = drupdate(dr, imu, dS)` | 函数原型声明 | — |
| 5 | `% Inputs: dr - DR structure array, created by 'drinit'` | 输入1：DR结构数组，由drinit创建 | dr字段包含 qnb, vn, pos, kod, ts, Cbo, prj, aos, eth, Mpv, distance 等 |
| 6 | `%         imu - SIMU gyro/acc sampling data` | 输入2：SIMU陀螺/加计采样数据，列=[wx,wy,wz,ax,ay,az,t] | 本函数只用前3列陀螺wm做姿态更新，未用加计 |
| 7 | `%         dS - odometer distance increment` | 输入3：里程计距离增量（米），可为标量或3维向量 | 标量=沿b系前向；向量=3维ODO增量（如双轮差速） |
| 8 | `% Output: dr - DR structure array after DR updating` | 输出：更新后的DR结构 | — |
| 9 | `%` | 空注释行 | — |
| 10 | `% See also  drinit, drpure, dratt, drcalibrate, nhcpure, insupdate.` | 相关函数交叉引用 | drinit=初始化; drpure=纯DR仿真; dratt=只更新姿态; drcalibrate=标定; insupdate=SINS对应更新 |
| 11 |  |  |  |
| 12 | `% Copyright(c) 2009-2014, by Gongmin Yan, All rights reserved.` | 版权声明 | 作者：严恭敏，西工大 |
| 13 | `% Northwestern Polytechnical University, Xi An, P.R.China` | 单位：西北工业大学，西安 | — |
| 14 | `% 17/12/2008, 8/04/2014` | 创建/修改日期 | 2008-12-17初版，2014-04-08修订 |
| 15 | `    nts = dr.ts*size(imu,1);` | 计算本批次IMU数据累计时间：采样周期 × 样本数 | 若一次传入 $nn$ 个子样，$\Delta t_{总}=ts \times nn$。用于后续 dSn/nts 求平均速度 |
| 16 | `    dr.distance = dr.distance + dr.kod*norm(dS);` | 累计总行驶距离（标量，ODO标度因子kod修正后） | `kod`=米/脉冲，若dS已是脉冲数则乘kod转米；norm=模长（标量时即绝对值） |
| 17 | `    dr.distance1 = dr.distance1 + dr.kod*dS;` | 累计ODO增量（保留原始dS维度，如向量则逐分量累加） | 与distance区别：distance1保留方向信息，用于双轮差速等场景 |
| 18 | `    [phim, dvbm] = cnscl(imu);  qnb12 = qupdt(dr.qnb, phim/2);` | ①IMU圆锥/划船补偿得到等效旋转矢量phim；②用一半旋转更新得到中间时刻四元数qnb12 | `phim`=圆锥补偿后的等效旋转矢量；`qupdt(q, rv/2)`=取增量中点估计n系到b系的过渡姿态，用于后续dS投影（速度居中原理） |
| 19 | `    if length(dS)>1,` | 判断里程计增量是否为多维（如双轮差速或3轴ODO） | — |
| 20 | `        dSn = qmulv(qnb12, dr.Cbo*dS);` | 多维ODO：先乘安装误差矩阵Cbo（b系→SIMU系+标度），再用qnb12转到n系 | $\Delta s^n = qnb12 \otimes C_{bo} \cdot \Delta s^{odo} \otimes qnb12^*$ |
| 21 | `    else` | 否则dS是标量（普通单里程计） | — |
| 22 | `        dSn = qmulv(qnb12, dr.prj*dS);` | 标量ODO：乘投影向量prj=[b系前向单位向量]×kod，再转n系 | `dr.prj` 在drinit第28行预先算出 = Cbo·[0;1;0]，即把b系前向轴预旋转到SIMU坐标系，这里直接点乘距离增量即可 |
| 23 | `    end` | if分支结束 | — |
| 24 | `%     dSn = rotv([0;0;-dr.aos*norm(dS)/nts*phim(3)/nts], dSn);` | 注释掉的旧代码：侧滑角AOS修正（旧版时间归一化有问题） | `aos`=Angle Of Slide侧滑系数；车辆转弯时航向速率×速度=侧滑速度分量 |
| 25 | `    dSn = rotv([0;0;-dr.aos*phim(3)/nts], dSn);` | 侧滑角在线修正：绕n系z轴（天向）旋转一个小角度补偿侧滑 | 修正角 $\Delta\psi_{aos} = -aos \cdot \frac{\Delta\theta_z^{陀螺}}{\Delta t}$，即陀螺测得的偏航速率乘以aos系数，方向相反抵消侧飘 |
| 26 | `    dr.vn = dSn/nts;` | 由位移增量÷时间间隔=平均n系速度 | $v^n = \Delta s^n / \Delta t$，注意这是DR推算速度，不是独立测量 |
| 27 | `    dr.eth = earth(dr.pos, dr.vn);` | 根据当前pos、vn重新计算地球参数结构（RMh, RNh, wnie, wnin, clRNh等） | `earth`=地球运动学参数计算，含曲率半径、地球自转角、有害加速度补偿所需量 |
| 28 | `    dr.web = phim/nts-dr.Cnb'*dr.eth.wnie;` | 计算陀螺等效输出：b系角速率 - Cnb转置后的地球自转 | $ω_{eb}^b = ω_{ib}^b - C_b^{nT} ω_{ie}^n$，即从惯性角增量中扣除地球自转得到机体系相对地球的角速率；可用于后续标度因子/零偏在线标定 |
| 29 | `    dr.Mpv = [0, 1/dr.eth.RMh, 0; 1/dr.eth.clRNh, 0, 0; 0, 0, 1];` | 构建位置变换矩阵Mpv：n系速度→经纬高变化率 | $\begin{bmatrix}\delta L \\ \delta \lambda \\ \delta h\end{bmatrix} = M_{pv} \begin{bmatrix}\delta v_E \\ \delta v_N \\ \delta v_U\end{bmatrix}$，对应 $\dot{L}=v_N/R_{Mh}$，$\dot{\lambda}=v_E/(R_{Nh}\cos L)$，$\dot{h}=v_U$ |
| 30 | `    dr.pos = dr.pos + dr.Mpv*dSn;` | ★核心：位置增量累加 = Mpv × n系位移增量 | $\boldsymbol{p}_{k+1} = \boldsymbol{p}_k + M_{pv} \cdot \Delta s^n$，即严恭敏博士论文式(4.1.1)。注意Mpv第1列=0、第2行第1列对应东向速度→经度，与直觉"行=纬度,列=北向"对应关系不要搞反 |
| 31 | `    dr.qnb = qupdt(dr.qnb, phim-dr.Cnb'*dr.eth.wnin*nts);` | ★完整姿态更新：用总旋转矢量phim扣除地球转动+牵连运动修正（wnin） | $q_{k+1}=q_k \otimes \exp\left(\frac{1}{2}(\Delta\theta_{ib}^b - C_b^{nT}\omega_{in}^n\Delta t)\right)$；即姿态更新时扣除地球自转（wnie）+有害角速度（wnen）= wnin，保持n系导航系 |
| 32 | `    [dr.qnb, dr.att, dr.Cnb] = attsyn(dr.qnb);` | 姿态四元数归一化，并同步输出欧拉角att=[pitch;roll;yaw]和方向余弦矩阵Cnb | `attsyn`=姿态综合，保证四元数模长=1（数值稳定性），Cnb从qnb重新计算 |
| 33 | `    dr.avp = [dr.att; dr.vn; dr.pos];` | 打包输出avp=[att(3); vn(3); pos(3)]统一格式 | 与SINS的ins.avp完全兼容，便于后续avpcmpplot对比 |
| 34 | `    if dr.Td>0.01  % leveling` | 如果配置了 leveling 时间常数Td（>10ms），则启动低速水平阻尼调平 | 这部分是针对低精度IMU（MEMS）的额外处理，传统高精度DR不需要 |
| 35 | `		fn=qmulv(dr.qnb, dvbm/nts);` | 把b系比力增量dvbm转到n系除以时间→n系比力 | $f^n = C_b^n \cdot (\Delta v^b / \Delta t)$，即加计测量值转n系 |
| 36 | `        dVE = dr.vni(1) - dr.vn(1);` | 东向速度差：惯性推算速度vni - DR速度vn | DR的vn是里程计+姿态积分的"参考"速度，vni是由加计积分出的纯惯性速度 |
| 37 | `        dr.vni(1) = dr.vni(1) + (fn(1)-dr.gck(1)*dVE)*nts;` | 二阶阻尼校正vni：比力积分 + 校正项gck(1)×速度差 | 经典二阶振荡阻尼器（类似舒勒阻尼），gck是Td和阻尼比ξ预计算的系数（见drinit第37-39行） |
| 38 | `        dr.dpos(1) = dr.dpos(1) + dVE*dr.gck(3)*nts;` | 位置积分项（阻尼网络中间状态）：dVE×gck(3)积分 | 二阶系统中间状态 |
| 39 | `        dr.wnc(2) = dVE*(1+dr.gck(2))/6378137 + dr.dpos(1);` | 姿态校正角速率wnc（北向分量）：速度差/地球半径 与位置积分项合成 | 对应"速度→姿态"反馈，通过虚拟旋转修正四元数，等效于调平 |
| 40 | `        dVN = dr.vni(2) - dr.vn(2);` | 北向速度差（同上，处理南北通道） | — |
| 41 | `        dr.vni(2) = dr.vni(2) + (fn(2)-dr.gck(1)*dVN)*nts;` | 北向vni阻尼校正（与东向对称） | — |
| 42 | `        dr.dpos(2) = dr.dpos(2) + dVN*dr.gck(3)*nts;` | 北向dpos积分 | — |
| 43 | `        dr.wnc(1) = -dVN*(1+dr.gck(2))/6378137 - dr.dpos(2);` | 姿态校正角速率wnc（东向分量），注意符号为负 | 东/北通道符号不同（右手定则） |
| 44 | `        dr.qnb = qmul(rv2q(-dr.wnc*nts),dr.qnb);` | 左乘修正旋转：用wnc积分的等效旋转矢量校正qnb | $q \leftarrow \exp\left(-\frac{1}{2}\omega_{nc}\Delta t\right) \otimes q$，左乘表示在n系施加小角度校正 |
| 45 | `        dr.avp = [q2att(dr.qnb); dr.vni; dr.pos];` | 调平模式下重新打包avp，注意vn改用vni（阻尼后的惯性速度） | — |
| 46 | `    end` | if Td 分支结束 | — |

---

## 🔍 断点调试建议

### 调试1：纯DR位置线性发散验证

在 `/workspace/psins/demos/test_SINS_DR.m` 中操作：

1. **运行前修改**：第18行 DR初始化处，将 `dkod = 0.01`（ODO标度+1%误差）保持不变，把第17行 `dinst = [15;0;10]*glv.min` 中的方位安装误差改为 `dinst(3)=0` 只保留标度误差；
2. **断点设置**：在第28行 `dr = drupdate(dr, wvm(:,1:3), dS);` 后打断点；
3. **观察变量**：记录 `dr.pos`（DR位置）与 `trj.avp(k1,7:9)`（真值），每 10 秒打印一次差值 `dr.pos - trj.avp(k1,7:9)` 转米；
4. **预期量级**：设车速 $V\approx20m/s$，跑 $T=300s$，纯ODO标度误差 $\delta k=1\%$，则位置误差应约为 $\delta k \cdot V \cdot T = 0.01×20×300=60m$，**随时间线性增长**。若实际误差偏离该量级，检查 kod 单位或 Mpv 矩阵方向是否搞反。

### 调试2：AOS侧滑修正效果

1. 修改 `drinit` 第18行输入中的 `inst(2)=aos`，比如设 `aos=0.3`；
2. 在drupdate第25行前后各断点，比较 `dSn` 修正前后的差异：转弯运动时（phim(3)≠0），修正后的东向位移应比修正前多出一个横向分量，量级约 `aos×|Δs|`。

---

## ❌ 初学者最容易踩的坑

### 坑1：里程计od单位搞错（脉冲没转米）
**现象**：DR跑完后位置误差正好差一个固定倍数 k（如100倍、1000倍），或者位置几乎不动。
**原因**：`dr.kod`（米/脉冲）没乘对。ODO通常输出是脉冲数，需要 `kod=轮周长/每圈脉冲数` 换算。比如轮胎周长2m，每圈2000脉冲，则 kod=0.001m/pulse。如果把脉冲当米直接用，结果差3个数量级。
**验证**：看 `dr.distance` 是否与 `trj.distance` 量级一致，前者应该≈后者。

### 坑2：DR航向与b系前向方向不匹配
**现象**：车辆直行但DR位置轨迹方向偏90°或180°，或者横纵向误差耦合。
**原因**：`dr.prj` 的b系前向轴默认是y轴（见drinit第28行 `dr.prj = dr.Cbo*[0;1;0]`），如果实际车辆ODO前向是x轴或z轴，投影方向完全错。车辆侧滑严重时AOS系数不匹配也会放大此问题。
**验证**：静止+IMU只给绕z轴正方向旋转，看yaw是否正确增加。然后直行时看n系位移是否沿yaw指向的方向。

### 坑3：位置更新时Mpv矩阵行列方向弄反
**现象**：向北运动但经度（λ）在变、纬度（L）不变，完全和直觉相反。
**原因**：Mpv的定义是 `[δL; δλ; δh] = Mpv · [δvE; δvN; δvU]`，即第1列对应东向速度（产出纬度变化=0），第2列对应北向速度（产出纬度变化），第1行第2列是1/RMh，第2行第1列才是东向→经度的系数。不要按"行1=北对应列1=北"的直觉来套。
**验证**：手动构造纯向北vN=20m/s，Δt=1s代入，看Mpv×[0;20;0]的第1项（纬度）是否=20/RM≈3.14e-4度，对的再继续。

---

## 🎯 配套练习

### 练习：NED下匀速直线运动的DR误差累积

**步骤**：
1. 在 `/workspace/psins/demos/` 新建脚本，手动造轨迹：
   - L0=34°N, λ0=108°E, h0=0m, 航向 yaw0=90°（正东）
   - 匀速 vn=[0;20;0]m/s（北向速度？不！正东对应 vE=20,vN=0，即 `vn=[20;0;0]`）
   - T=600s（10分钟），ts=0.01s
2. 陀螺数据造零均值噪声：`wm = randn(N,3) * 0.01°/h × ts`，即 $\sigma_{ARW}=0.01°/\sqrt{h}$ 换算成 rad/√s × √ts
3. ODO增量造 `od = 20*ts * (1 + 0.01*randn)`（1%高斯标度误差+白噪声）
4. 用 `drinit` 初始化，循环调用 `drupdate` 跑 10 次 Monte Carlo
5. **理论公式验证**：最终东向位置误差的 STD 应约为：

$$
\sigma_{\delta East} \approx V \cdot \sigma_{\varepsilon_\psi} \cdot \sqrt{T / 3}
$$

   其中航向随机游走 $\sigma_{\varepsilon_\psi}(t)=\sigma_{ARW}\cdot\sqrt{t}$，积分后时间指数从 1/2 变 3/2，开平方后是 √(T³/3) 量级。
6. 实际跑出来10次的终位误差STD是否与理论公式在同一数量级？如果差太多，检查ARW单位换算（deg/√h → rad/√s 要除以 `√3600 × 180/π`）。
