# 10_kffeedback.m 逐行注释 Wiki (PSINS)
> 配套源码: [kffeedback.m](file:///workspace/psins/base/kf/kffeedback.m)
> 所属层级: L3组合导航
> 前置依赖: 07_kfinit_153 / 08_kffk / 09_kfupdate
> 学习目标: ①为什么ESKF需要反馈而EKF不用 ②xk里的φδvδp怎么对ins结构体做校正 ③反馈后xk为什么要清零

---

## 🧩 函数作用一句话
ESKF把KF估计的误差状态反馈回SINS主状态ins，并重置误差状态。

---

## 📐 数学原理 / 物理意义
这是理解ESKF和传统直接法EKF区别的最关键一环！详细讲:

1. **传统直接法EKF**: `xk=[att;vn;pos]`是**全状态**，KF估计完xk就是真值，不用反馈。
2. **PSINS用ESKF(误差状态卡尔曼滤波)**: `xk=[φ;δvn;δp;εb;∇b]`是**误差状态**，KF估计的是"主状态ins和真值之间差多少"，所以估计完必须把`x_nom`校正回`x_true≈x_nom+δx`，然后再把`δx`的估计清零，因为"差"已经被消除了。
3. **逐项校正公式**（最关键，注意PSINS符号约定：φ/v/p用减号，eb/db/lever用加号）：

$$
   \begin{cases}
   \hat{\mathbf{q}}_{nb}^{+} = \mathbf{q}(\hat{\boldsymbol{\phi}}) \otimes \mathbf{q}_{nb}^{-},  &\text{四元数左乘姿态误差（qdelphi内部实现）} \\
   \hat{\mathbf{v}}_n^{+} = \mathbf{v}_n^{-} - \delta\hat{\mathbf{v}}_n, &\text{速度 **减** 速度误差（PSINS的δvn = v_nom - v_true）} \\
   \hat{\mathbf{p}}^{+} = \mathbf{p}^{-} - \delta\hat{\mathbf{p}}, &\text{位置 **减** 位置误差（δp=[δL;δλ;δh]单位 rad/rad/m）} \\
   \hat{\boldsymbol{\varepsilon}}_b^{+} = \hat{\boldsymbol{\varepsilon}}_b^{-} + \Delta\hat{\boldsymbol{\varepsilon}}_b,  &\text{陀螺零偏 **加**} \\
   \hat{\nabla}_b^{+} = \hat{\nabla}_b^{-} + \Delta\hat{\nabla}_b, &\text{加计零偏 **加**} \\
   \mathbf{x}_k(\text{idx}) \leftarrow \mathbf{x}_k(\text{idx}) - \mathbf{x}_{fb\_tmp}(\text{idx}),  &\text{部分清零（按反馈字符串），保证ESKF始终估计小误差} \\
   \mathbf{x}_{fb}(\text{idx}) \leftarrow \mathbf{x}_{fb}(\text{idx}) + \mathbf{x}_{fb\_tmp}(\text{idx}),  &\text{累计记录总反馈量，供离线分析}
   \end{cases}
$$

4. **为什么xk清零后P阵不跟着清零？** 因为P阵是"当前误差状态的方差"，xk是均值——均值归零了，但方差还保留着"不确定度"，下次KF继续用。
5. **xk状态顺序（15状态标准kfinit153）**：严格对齐 kfinit.m:29 的 Pxk 定义顺序
   ```
   idx:   1 2 3   4 5 6    7 8 9     10 11 12    13 14 15
   xk:   [φx φy φz, δvn δve δvd, δL δλ δh, ebx eby ebz, dbx dby dbz]
   unit: [rad rad rad, m/s m/s m/s, rad rad m, rad/s rad/s rad/s, m/s² m/s² m/s²]
   ```
   test_SINS_GPS_153.m:32 调用方式为 `kffeedback(kf, ins, 1, 'avp')`，即每1秒对 a姿态+v速度+p位置 三项做闭环反馈，eb/db暂不反馈（'avp'未包含'e''d'），零偏靠P阵和Q阵慢慢积累收敛。

---

## 📝 逐行注释 (行号严格对齐原 kffeedback.m)

| 行号 | 原代码 | 中文注释 | 公式/备注 |
|---|---|---|---|
| 1 | `function [kf, ins, xfb] = kffeedback(kf, ins, T_fb, fbstr)` | 函数入口：输入 kf/ins 结构体 + 反馈间隔 T_fb + 反馈字符 fbstr；输出校正后的 kf/ins + 本次反馈的状态值 xfb | 返回值顺序 kf→ins→xfb，与 kfupdate 一致 |
| 2~3 | `% Kalman filter state estimation feedback to SINS.` | 函数总注释 | — |
| 4 | `% Prototype: [kf, ins] = kffeedback(kf, ins, T_fb)` | 最简调用原型（省略 fbstr 时取 kf.fbstr 默认值） | — |
| 5~9 | `% Inputs: ... Outputs: ...` | 输入输出说明；T_fb=0 不反馈；>xtau 全反馈 | T_fb 单位秒 |
| 10 | `%          xfb - feedback state value` | xfb 是**本次实际反馈**的状态向量（按 coef_fb 缩放后的） | 不是全部 kf.xk |
| 12 | `% See also  kfinit, kfinit0, kffk, kfhk, kfplot, psinstypedef.` | 关联函数 | — |
| 14~16 | 版权声明 | 严恭敏老师 2013/10/05 初版，2021/02/06 修订 | — |
| 17 | `if nargin<4, fbstr=kf.fbstr; end` | ★参数补齐1：如果没传第4参 fbstr，就用 kf 结构体里默认的 fbstr | kfinit0.m:31 默认 `fbstr='avped'` |
| 18 | `if nargin<3, T_fb=1; end` | ★参数补齐2：如果没传第3参 T_fb，默认 1 秒反馈一次 | — |
| 19 | `if kf.T_fb~=T_fb` | 如果传入的 T_fb 和 kf 里缓存的不一样，重新计算反馈系数 coef_fb | 缓存机制：只在 T_fb 变化时重算，否则跳过 20~29 |
| 20 | `kf.T_fb = T_fb;` | 更新缓存的 T_fb | — |
| 21~25 | 注释掉的多种 coef_fb 历史版本 | 严老师迭代过 4 种计算方式，2022-6-25 版本当前生效 | 见下一行 |
| 26 | `idx = kf.T_fb>kf.xtau;  % scale<vector` | 找到**反馈间隔 T_fb > 状态相关时间 xtau** 的那些状态索引 | AR(1)模型：时间常数 xtau 大的状态收敛慢 |
| 27 | `kf.coef_fb(idx) = 1;  kf.coef_fb(~idx) = kf.T_fb./kf.xtau(~idx);   %2022-6-25` | ★比例反馈系数计算：<br>① idx（T_fb>xtau）：coef_fb=1 → **全额立即反馈**（收敛快的状态）<br>② ~idx（T_fb<xtau）：coef_fb=T_fb/xtau → **比例渐进反馈**，避免零偏等慢状态过冲 | `coef_fb ∈ [0,1]`；这是PSINS ESKF避免过冲的关键技巧，不是简单全量清零 |
| 28 | `kf.coef_fb(kf.xtau<0.001 & kf.T_fb~=inf) = 1;` | 保护：xtau 极小（<1ms，数值异常）且 T_fb≠inf 的状态强制 coef_fb=1 | 防除零 |
| 29 | `end` | 结束 coef_fb 重算分支 | — |
| 30 | `xfb_tmp = kf.coef_fb.*kf.xk;  xfb = xfb_tmp*0;` | ★核心中间量：`xfb_tmp = coef_fb ⊙ xk`（逐元素乘），即本次要实际反馈的比例量；xfb 先初始化为全零，后面按 fbstr 逐个填 | 比例反馈≠100%反馈，慢状态用小系数 |
| 31 | `for k=1:length(fbstr)` | ★按反馈字符串 fbstr 的每个字符循环，逐个状态组反馈 | 例如 `fbstr='avp'` 会循环 3 次：'a'→'v'→'p' |
| 32 | `switch fbstr(k)` | 多分支选择反馈类型 | 共支持 a/v/p/e/d/A/V/P/E/D/L/T/G/C/h/H 15+种 |
| 33 | `case 'a',` | ★字符 'a' = 全部 3 轴姿态角误差反馈（attitude） | — |
| 34 | `idx = 1:3; ins.qnb = qdelphi(ins.qnb, xfb_tmp(idx));` | ★★★姿态反馈核心：取 xk(1:3)=[φx;φy;φz]（单位 rad），调用 `qdelphi(qnb, φ)` = `rv2q(φ)⊗qnb` 把失准角反向抵消 | 对应公式：q⁺ = q(φ̂)⊗q⁻；**绝对不能直接加欧拉角！** qdelphi 见 qdelphi.m:18 |
| 35 | `case 'v',` | ★字符 'v' = 全部 3 轴速度误差反馈（velocity） | — |
| 36 | `idx = 4:6; ins.vn = ins.vn - xfb_tmp(idx);` | ★★速度反馈：xk(4:6)=[δvn;δve;δvd]（m/s），PSINS约定 δvn = v_nom - v_true，所以 **v_true = v_nom - δvn**，用减号！ | ❌常见错：写加号 |
| 37 | `case 'p',` | ★字符 'p' = 全部 3 维位置误差反馈（position） | — |
| 38 | `idx = 7:9; ins.pos = ins.pos - xfb_tmp(idx);` | ★★位置反馈：xk(7:9)=[δL;δλ;δh]，单位 **rad / rad / m**；同样约定 δp = p_nom - p_true，所以用**减号**！ | ❌常见坑：把 δL/δλ 当成度，单位错误导致收敛极慢；kfsetting.m:51 / 65 里 Rk(4:5)÷Re、Pk(7:8)÷Re，说明 kf 内部前两维是 rad，m 直接加 |
| 39 | `case 'e',` | ★字符 'e' = 陀螺零偏 εb 反馈（epsilon bias） | — |
| 40 | `idx = 10:12; ins.eb = ins.eb + xfb_tmp(idx);` | ★陀螺零偏反馈：xk(10:12)=[εbx;εby;εbz]（rad/s），PSINS里eb是**累加型**，所以直接加 | insupdate 里 wm 先减 eb 再积分，见 insupdate.m |
| 41 | `case 'd',` | ★字符 'd' = 加计零偏 ∇b 反馈（delta bias） | — |
| 42 | `idx = 13:15; ins.db = ins.db + xfb_tmp(idx);` | ★加计零偏反馈：xk(13:15)=[∇bx;∇by;∇bz]（m/s²），同样累加型直接加 | vm 先减 db 再比力积分 |
| 43 | `case 'A',` | 字符 'A' = **仅水平两轴**姿态反馈（方位 φz 强制=0不反馈） | 大方位失准粗对准阶段用 |
| 44 | `idx = 1:2; ins.qnb = qdelphi(ins.qnb, [xfb_tmp(idx);0]);` | φx,φy 参与，φz 补零 | — |
| 45 | `case 'V',` | 字符 'V' = 仅天向速度反馈（δvd） | 水平速度不可靠场景 |
| 46 | `idx = 6; ins.vn(3) = ins.vn(3) - xfb_tmp(idx);` | vn(3)=天向向下，只减一项 | — |
| 47 | `case 'P',` | 字符 'P' = 仅高度反馈（δh） | 高度表/气压计辅助 |
| 48 | `idx = 9; ins.pos(3) = ins.pos(3) - xfb_tmp(idx);` | pos(3)=高度，只减一项 | — |
| 49 | `case 'E',` | 字符 'E' = 仅水平两轴陀螺零偏反馈 | — |
| 50 | `idx = 10:11; ins.eb(1:2) = ins.eb(1:2) + xfb_tmp(idx);` | ebx,eby，方位零偏 ebz 不反馈 | — |
| 51 | `case 'D',` | 字符 'D' = 仅天向加计零偏反馈 | 高度通道弱可观，单独反馈 dbz 收敛更稳 |
| 52 | `idx = 15; ins.db(3) = ins.db(3) + xfb_tmp(idx);` | db(3)=dbz 单轴 | — |
| 53 | `case 'L',` | 字符 'L' = 杆臂 lever 误差反馈（18/19/34 状态 kfinit 才有 xk(16:18)） | kfinit183/186/193/196/343/346/373/376 |
| 54 | `idx = 16:18; ins.lever = ins.lever + xfb_tmp(idx);` | 杆臂校正直接加 | — |
| 55 | `case 'T',` | 字符 'T' = 时间延迟 dT 反馈（19 状态以上） | — |
| 56 | `idx = 19; ins.tDelay = ins.tDelay + xfb_tmp(idx);` | tDelay 直接加 | — |
| 57 | `case 'G',` | 字符 'G' = 陀螺刻度因子矩阵 dKg 反馈（24/30/33/34/37 状态） | xk(20:28) 共9项 = reshape(Kg,9,1) |
| 58 | `idx = 20:28; dKg = xfb_tmp(idx);  dKg = [dKg(1:3),dKg(4:6),dKg(7:9)];` | 9维向量 → 3×3矩阵 | — |
| 59 | `ins.Kg = (eye(3)-dKg)*ins.Kg;` | 增量型左乘刻度校正：K_new = (I - ΔK)·K_old | — |
| 60 | `case 'C',` | 字符 'C' = 加计刻度因子 dKa 反馈（30/33/34/37 状态） | xk(29:34) 共6项（下三角） |
| 61 | `idx = 29:34; dKa = xfb_tmp(idx);  dKa = [dKa(1:3),[0;dKa(4:5)],[0;0;dKa(6)]];` | 6维 → 3×3**下三角**矩阵（加计只估计下三角6个参数） | 约定见 kfinit343/373 |
| 62 | `ins.Ka = (eye(3)-dKa)*ins.Ka;` | 加计刻度校正，形式同 Kg | — |
| 63 | `case 'h',` | 字符 'h' = 高度快捷反馈（同'P'，只是字符别名） | — |
| 64 | `idx = 9;  ins.pos(3) = ins.pos(3) - xfb_tmp(9);` | 同 'P' 完全等价 | — |
| 65 | `case 'H',` | 字符 'H' = 高度通道三件套联合反馈：v天向 + 高度 + dbz | — |
| 66 | `idx = [6,9,15];                         ins.vn(3) = ins.vn(3) - xfb_tmp(6);` | 组合 3 项：6=vd / 9=h / 15=dbz，先减 vd | — |
| 67 | `ins.pos(3) = ins.pos(3) - xfb_tmp(9);	ins.db(3) = ins.db(3) + xfb_tmp(15);` | 再减高度，最后加 dbz | — |
| 68 | `otherwise,` | 非法字符兜底 | — |
| 69 | `error('feedback string mismatch in kf_feedback');` | 报错终止 | — |
| 70 | `end` | 结束 switch 分支 | — |
| 71 | `kf.xk(idx) = kf.xk(idx) - xfb_tmp(idx);    %` | ★★★★ESKF 灵魂行！对应反馈的那部分 idx 状态**部分清零**：减去刚才反馈的 xfb_tmp（=coef_fb·xk），而不是粗暴全部清0。 | 这样比例反馈后的剩余残差留到下一次继续收敛；如果 coef_fb=1，等价于这几项 xk 完全归零 |
| 72 | `kf.xfb(idx) = kf.xfb(idx) + xfb_tmp(idx);  % record total feedback` | 累计总反馈量：kf.xfb 是从 t=0 以来**所有反馈的总和**，离线画收敛曲线用 | kfinit0.m:38 初始化为全 0 |
| 73 | `xfb(idx) = xfb_tmp(idx);` | 输出参数 xfb 记录**本次**反馈的状态值（返回给调用方） | — |
| 74 | `end` | 结束 for 循环（遍历完 fbstr 每个字符） | — |
| 75 | `[ins.qnb, ins.att, ins.Cnb] = attsyn(ins.qnb);` | ★同步 ins 的三个姿态表示：用校正后的 qnb 重新生成 [qnb, att欧拉角, Cnb方向余弦阵]，保持三者一致 | 防三者不同步导致后续 update 出错；attsyn 内部会把 qnb 归一化 |
| 76 | `ins.avp = [ins.att; ins.vn; ins.pos];  % 2015-2-22` | ★最后把 [att(3); vn(3); pos(3)] 打包写回 `ins.avp`（9×1列向量），方便调用方直接用 ins.avp 画图/存盘 | avp = attitude + velocity + position |

---

## 🔍 断点调试建议
在 [test_SINS_GPS_153.m](file:///workspace/psins/demos/test_SINS_GPS_153.m) **第32行**（`[kf, ins] = kffeedback(kf, ins, 1, 'avp');`）前后分别断点，第一次 GNSS 观测到来（t=1s 附近）抓变量：

| 变量 | Before kffeedback 预期量级 | After kffeedback 预期量级 | 判读结论 |
|---|---|---|---|
| `ins.pos(1:2) - trj.avp(k1,7:8)` | ~(1~10) m / ~(10~50) m | 骤降到 ~0.1~1 m | ✅位置反馈起作用 |
| `ins.vn - trj.avp(k1,4:6)` | ~0.1~0.5 m/s | ~0.005~0.02 m/s | ✅速度反馈起作用 |
| `kf.xk(1:9)` | φ~0.01~0.1°，δv~0.1m/s，δp~几米 | **对应 idx(1:9) 几乎全为 0**（因为 fbstr='avp' 只清1:9；10:15 eb/db 还留着） | ✅xk 部分清零 |
| `kf.xk(10:15)` | eb~0.01°/h，db~几十μg | **不变**（'avp'不含'ed'） | ✅零偏没反馈，下次KF继续估计 |
| `kf.Pxk` 对角 | 变化不大 | 变化不大 | ✅P 阵**不**清零，保留不确定度 |
| `ins.qnb` 归一化 | ‖qnb‖≈1 但微偏 | attsyn 后严格 =1 | ✅归一化成功 |

> **异常判断**：如果第一次反馈后 eb/db 跳 ≥ 几百 °/h → 单位错（kf里是弧度被当成度加了）；如果误差没下降反而振荡翻倍 → 第36/38行减号写成加号、或者 xk 顺序错。

---

## ❌ 初学者最容易踩的坑

1. **忘了清零 kf.xk（第71行）**：连续两次反馈相当于"同一误差被加两次"，解算结果剧烈震荡，新手最容易犯！——ESKF 不是 EKF，xk 是误差估计，必须消掉。
2. **φ 校正写成 `ins.att = ins.att + xk(1:3)`（直接加欧拉角）**，而不是 `qdelphi` 的四元数乘法。大角度姿态失准（>5°）时直接错；小角度仿真勉强过，实车直接崩。
3. **pos 单位搞错**：kf 里 `xk(7:9)=δp=[δL(rad); δλ(rad); δh(m)]`，有人误以为 δL/δλ 是度，加进去误差就只 ~π/180 ≈ 1/57 大小，飘得又小又慢，半天不收敛。
4. **只反馈 φ/δv/δp 三个（fbstr='avp'），不反馈 εb/∇b（缺 'e''d'）**：eb/db 一直卡在初始值不更新，SINS 的零偏导致纯惯导发散速度没变，KF 必须花几十分钟靠 φ/δv 反推零偏，收敛极慢。
5. **把速度/位置的减号写成加号（36/38/64/66/67行）**：PSINS 误差约定是 `δx = x_nom - x_true`，所以 `x_true = x_nom - δx`。写加号会把误差**翻倍放大**，第一次反馈就发散。

---

## 🎯 配套练习

在 [test_SINS_GPS_153.m](file:///workspace/psins/demos/test_SINS_GPS_153.m) **第32行**把 `kffeedback(kf, ins, 1, 'avp')` 注释掉（但保留前后的 kfupdate），然后：

1. **跑 300s 仿真**：
   - 子图1画 `avp(:,7:8) - trj.avp(:,7:8)` 经纬度误差曲线
   - 子图2画 `xkpk(:,1:9)`（KF 估计的 xk 前9项）
   - 子图3画 `xkpk(:,19:24)`（kf.Pxk 对角 φ/δv/δp 的方差）

2. **现象**：
   - 子图3 的方差会**正常下降**（因为 KF 时间/量测更新都在跑）
   - 子图2 的 xk 也会从大往小**正常收敛**
   - **但是子图1 的 SINS 位置误差却完全没修正，和纯惯导一样发散**

3. **理解**：这就是"没有反馈的 ESKF 等于什么都没做"——KF 自己知道差多少，但没把差值写回 ins，主状态照样发散。然后取消注释再跑一次，前后对比两张误差图的差距，就能直观体会 kffeedback 为什么是 ESKF 的灵魂。
