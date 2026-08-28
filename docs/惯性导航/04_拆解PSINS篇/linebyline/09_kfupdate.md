# 09_kfupdate 逐行注释 Wiki (PSINS)

> 配套源码: [kfupdate.m](file:///workspace/psins/base/kf/kfupdate.m)
> 所属层级: L3组合导航
> 前置依赖: 00_glvf / 01_earth / 03_insupdate / 08_kffk + 卡尔曼滤波五公式
> 学习目标: 读完能独立回答3个问题

---

## 🧩 函数作用一句话

标准离散KF：时间/量测/双更新三合一

---

## 📐 数学原理 / 物理意义

### 标准离散KF五公式（编号对照源码）

考虑线性离散随机系统：
```
x_k = Φ_{k,k-1}·x_{k-1} + w_{k-1}        状态方程
y_k = H_k·x_k + v_k                       量测方程
E[w]=0, E[w·wᵀ]=Q;  E[v]=0, E[v·vᵀ]=R;  E[w·vᵀ]=0
```

卡尔曼滤波的**标准五公式**，对应本函数实现如下：

| 编号 | 公式名称 | 数学公式 | 源码位置 |
|:----:|:---------|:---------|:---------|
| ① | 状态预测（时间更新） | x̂ₖ⁻ = Φ·x̂ₖ₋₁⁺ | [L37](file:///workspace/psins/base/kf/kfupdate.m#L37) 或 [L46](file:///workspace/psins/base/kf/kfupdate.m#L46) |
| ② | 协方差预测 | Pₖ⁻ = Φ·Pₖ₋₁⁺·Φᵀ + Γ·Q·Γᵀ | [L38](file:///workspace/psins/base/kf/kfupdate.m#L38) 或 [L47](file:///workspace/psins/base/kf/kfupdate.m#L47) |
| ③ | 量测残差 | rₖ = yₖ − H·x̂ₖ⁻ | [L55](file:///workspace/psins/base/kf/kfupdate.m#L55) |
| ④ | 卡尔曼增益 | Kₖ = Pₖ⁻·Hᵀ·(H·Pₖ⁻·Hᵀ + R)⁻¹ | [L52-L53](file:///workspace/psins/base/kf/kfupdate.m#L52)+[L69](file:///workspace/psins/base/kf/kfupdate.m#L69) |
| ⑤a | 状态校正 | x̂ₖ⁺ = x̂ₖ⁻ + Kₖ·rₖ | [L74](file:///workspace/psins/base/kf/kfupdate.m#L74) |
| ⑤b | 协方差校正 | Pₖ⁺ = Pₖ⁻ − Kₖ·(H·Pₖ⁻·Hᵀ + R)·Kₖᵀ | [L75](file:///workspace/psins/base/kf/kfupdate.m#L75) |

注意：协方差校正 PSINS 用的是**Joseph稳定形式**的等价写法 `P⁺ = P⁻ − K·S·Kᵀ`（其中 S=HP⁻Hᵀ+R），而非常规 `(I−KH)P⁻`。前者数值更稳定，保证 P⁺ 半正定。

### Sage-Husa 自适应 Rₖ 估计（L57-L67）的直觉

标准KF假设量测噪声R是固定的先验值，但实际中：
- GPS信号遮挡时R会变大（多径效应）
- 不同时段卫星几何分布变化，R应动态调整

**Sage-Husa时变噪声统计估计器**（PSINS只对R做自适应，Q固定）：

```
b = kf.beta     （遗忘因子，指数衰减权重，初始≈0.9~0.99）
R̂ₖ = b·R̂ₖ₋₁ + (1−b)·(rₖ·rₖᵀ − H·Pₖ⁻·Hᵀ)
```

**直觉理解**：
- `rₖ·rₖᵀ`：实际残差的外积（真实量测波动大小的"观测"）
- `H·Pₖ⁻·Hᵀ`：KF模型预测的残差理论方差
- 两者之差 = "实际噪声比模型假设的大多少"
- 若真实残差 r² ≫ HP⁻Hᵀ → 说明R设小了，应该调大
- 若真实残差 r² ≪ HP⁻Hᵀ → 说明R设大了，应该调小
- 指数平滑 b·旧R + (1−b)·新观测 → 避免跳变，形成滑动平均

再加上 **[Rmin, Rmax]硬截断**：
- R < Rmin → 锁死在Rmin，防止过度自信导致KF"相信"错误量测
- R > Rmax → 锁死在Rmax，防止某次异常残差把R推到无穷大KF等效失效

最后 **β衰减公式（L66）**：
```
kf.beta = kf.beta / (kf.beta + kf.b)
```
这是**变遗忘因子Sage-Husa**：初期beta大→相信新残差，快速收敛；beta逐步减小→逐渐稳定到固定R。b参数控制衰减速度（b越小衰减越慢）。

### Pconstrain 防止P阵坍缩/爆炸的重要性

长期运行的KF常出现两种数值病态：
1. **P阵坍缩（Pk(k,k)→0）**：KF过度自信，认为状态"完全知道"，后续量测被K=PHᵀS⁻¹完全忽略（因为P→0→K→0），估计进入死锁再也不更新
2. **P阵爆炸（Pk(k,k)→∞）**：模型Q或Φ有误差，P无界增长，增益K→∞导致状态"过度跟随"量测噪声，估计抖动剧烈

Pconstrain的处理策略不对称：
- **Pmin**：硬截断 `Pk(k,k)=Pmin`，简单直接——不允许低于此下限
- **Pmax**：**等比例缩放整行整列**而非硬截断！因为直接截断对角线会破坏P的半正定性。设 ratio=√(Pmax/Pkk)，对第k行和第k列同乘ratio，相当于对状态向量第k维做尺度变换后的相似变换，保持P对称半正定

---

## 📝 逐行注释

### 第一段：函数头与参数解析 (L1-L34)

| 行号 | 源码 | 注释 | 重点标记 |
|------|------|------|----------|
| 1 | `function kf = kfupdate(kf, yk, TimeMeasBoth)` | 函数入口，输入输出都是kf结构体（in-place风格修改）；yk量测向量；TimeMeasBoth模式开关 | |
| 2-11 | `% Discrete-time Kalman filter...` | 注释：原型说明，**关键**——TimeMeasBoth='T'(只传kf)时间更新；'M'仅量测更新；'B'(传kf+yk)两步都做 | |
| 12-23 | `% Notes: (1) the Kalman filter stochastic models is...` | 注释：①写出状态/量测方程+Q/R定义；②**Sage-Husa自适应R公式** R=bR₋₁+(1−b)(rrᵀ−HP⁻Hᵀ) 写在注释里！配Rmin/Rmax约束；③fading遗忘因子；④Pmax/Pmin约束 | |
| 24-25 | `% See also kfinit, kfinit0, kfupdatesq, kffk, kfhk, kfc2d, kffeedback, kfplot, RLS, ekf, ukf.` | 参考函数族：初始化→状态转移→量测矩阵→离散化→反馈→绘图→RLS/EKF/UKF对比 | |
| 26-29 | `% Copyright(c) 2009-2015...` | 版权：严恭敏，西工大，2012/12/08初版，2013/08/29→2015/04/16→2017/06/01→2018/03/11多轮修订 | |
| 30-31 | `if nargin==1, TimeMeasBoth = 'T'; end` | ★参数默认值：只传1个参数(kf)→默认'T'纯时间更新。对应 [test_SINS_GPS_153.m:28](file:///workspace/psins/demos/test_SINS_GPS_153.m#L28) 的调用 `kfupdate(kf)` | ★ |
| 32-34 | `elseif nargin==2, TimeMeasBoth = 'B'; end` | 传2个参数(kf+yk)→默认'B'即 Time+Meas 都做。传3个参数就是显式指定了。 | |

### 第二段①：时间更新 'T' 分支 (L36-L40)

| 行号 | 源码 | 注释 | 重点标记 |
|------|------|------|----------|
| 35 | `（空行）` | | |
| 36 | `if TimeMeasBoth=='T'            % Time Updating` | 分支①：仅时间更新（预测步）。高频SINS每步都走这个！ | |
| 37 | `kf.xkk_1 = kf.Phikk_1*kf.xk;` | ★KF公式①：状态预测 x̂ₖ⁻ = Φ·x̂ₖ₋₁⁺。xkk_1 命名含义 = x(k|k-1) 即k时刻基于k-1时刻信息的预测 | ★ |
| 38 | `kf.Pxkk_1 = kf.Phikk_1*kf.Pxk*kf.Phikk_1' + kf.Gammak*kf.Qk*kf.Gammak';` | ★KF公式②：协方差预测 Pₖ⁻ = ΦPΦᵀ + ΓQΓᵀ。Gammak是过程噪声驱动阵（把白噪声w从6维陀螺/加计噪声空间映射到15维状态空间） | ★★ |
| 39 | `kf.xk = kf.xkk_1;  kf.Pxk = kf.Pxkk_1;` | 无测量时，预测值就是校正值：x̂ₖ⁺ ≡ x̂ₖ⁻，P̂ₖ⁺ ≡ P̂ₖ⁻。xk/Pxk始终存的是"当前最新校正后"的值 | |
| 40 | `kf.measstop = kf.measstop - kf.nts;  kf.measlost = kf.measlost + kf.nts;` | ★工程化计时器：measstop>0表示"停用量测更新的剩余时间"（手动屏蔽量测），倒计时递减；measlost表示"距离上次成功量测已过多久"（丢包监控），累加计时 | ★ |

### 第二段②：量测更新的K增益+校正 'M'/'B'分支 (L42-L81)

| 行号 | 源码 | 注释 | 重点标记 |
|------|------|------|----------|
| 41 | `else` | 进入非'T'分支：即'M'或'B' | |
| 42-44 | `if TimeMeasBoth=='M'`<br>`kf.xkk_1 = kf.xk;`<br>`kf.Pxkk_1 = kf.Pxk;` | 分支②：仅量测更新。假设时间更新在外部已做过，直接取xk/Pxk作为预测值（k|k-1 ≡ k|k，等价Φ=I）。对应 [test_SINS_GPS_153.m:31](file:///workspace/psins/demos/test_SINS_GPS_153.m#L31) `kfupdate(kf, ins.pos-posGPS, 'M')` | |
| 45-48 | `elseif TimeMeasBoth=='B'`<br>`kf.xkk_1=Φ*xk; Pxkk_1=ΦPxkΦ'+ΓQΓ';`<br>`measstop--; measlost++;` | 分支③：先时间更新再量测更新，把L37-L40压缩在此。代码与L37-L40完全一致 | |
| 49-51 | `else, error('TimeMeasBoth input error!');` | 参数合法性校验，非T/M/B直接报错终止 | |
| 52 | `kf.Pxykk_1 = kf.Pxkk_1*kf.Hk';` | ★预计算互协方差 P_{xy,k|k-1} = Pₖ⁻·Hᵀ，后面K增益和S都要用，缓存省一次乘法 | ★ |
| 53 | `kf.Py0 = kf.Hk*kf.Pxykk_1;` | ★预计算量测预测协方差（不含R）：Py0 = H·Pₖ⁻·Hᵀ。后面自适应R、残差χ²检验、S=Py0+R都要用 | ★ |
| 54 | `kf.ykk_1 = kf.Hk*kf.xkk_1;` | 量测预测 ŷ = H·x̂ₖ⁻，即"根据当前状态预测应该观测到什么" | |
| 55 | `kf.rk = yk-kf.ykk_1;` | ★★★KF公式③：残差 r = 真实观测 − 预测观测。**符号绝对不能写反**！写反就变预测-真实=-r，后面x校正变 x⁺=x⁻+K(-r) 方向全错 | ★★★ |
| 56 | `idxbad = [];  % bad measurement index` | 初始化坏量测标记索引数组，后面自适应/野值检测用 | |
| 57-58 | `if kf.adaptive==1`<br>`for k=1:kf.m` | ★★Sage-Husa自适应R开关。kf.m是量测维度。逐标量独立估计R的对角元（PSINS假设R为对角阵——各量测通道独立） | ★★ |
| 59 | `if yk(k)>1e10, idxbad=[idxbad;k]; continue; end` | 野值检测1：观测值>1e10判为无效（通常NaN/Inf或传感器掉线会返回超大值），标记idxbad并跳过R更新 | |
| 60 | `ry = kf.rk(k)^2-kf.Py0(k,k);` | ★★核心量："实际噪声功率 - 模型预测残差功率"之差。ry>0→R应该调大；ry<0→R应该调小。ry = r² − HP⁻Hᵀ | ★★ |
| 61 | `if ry<kf.Rmin(k,k), ry = kf.Rmin(k,k); end` | 软下限：ry（即潜在新R候选）不能低于Rmin，低于则抬到Rmin（防止R→0导致K过大） | |
| 62-63 | `if ry>kf.Rmax(k,k), kf.Rk(k,k)=Rmax;`<br>`else Rk(k,k)=(1-beta)*Rk + beta*ry;` | ★★Sage-Husa指数平滑公式：<br>• ry超上限→硬截断Rmax<br>• 否则 Rₖ = (1−β)·Rₖ₋₁ + β·ry<br>β∈(0,1)，通常β≈0.01~0.1，新息权重小、平滑更稳 | ★★★ |
| 64-65 | `end  % for循环结束`<br>`end  % adaptive结束` | 关闭k=1:m循环和adaptive==1分支 | |
| 66 | `kf.beta = kf.beta/(kf.beta+kf.b);` | ★★★变遗忘因子β衰减公式：β_new = β_old / (β_old + b)。数学上等价 β_t ≈ β₀/(1+t·b·β₀) 渐近递减。初期β大→快学新息；后期β→0→R固定不再更新，防止发散 | ★★★ |
| 67 | `（空行）` | | |
| 68 | `kf.Pykk_1 = kf.Py0 + kf.Rk;` | ★残差协方差（新息协方差）S = HP⁻Hᵀ + R。正定阵，后面求逆 | ★ |
| 69 | `kf.Kk = kf.Pxykk_1*invbc(kf.Pykk_1);` | ★★KF公式④：卡尔曼增益 K = Pₓᵧ · S⁻¹ = P⁻Hᵀ(HP⁻Hᵀ+R)⁻¹。invbc是PSINS自定义矩阵求逆函数（内部优先用mldivide，数值更稳） | ★★ |
| 70 | `nomeas = union(find(kf.measstop>0),[kf.measmask;idxbad]);` | ★★工程化量测屏蔽：nomeas = 禁止更新的量测通道索引。三类来源取并集：<br>① measstop>0：手动临时屏蔽通道<br>② measmask：用户配置的永久屏蔽位<br>③ idxbad：本次野值检测出的坏通道<br>2022/11/20修订版合并方式 | ★★ |
| 71-72 | `hasmeas = (1:kf.m)';`<br>`if ~isempty(nomeas), Kk(:,nomeas)=0; hasmeas(nomeas)=[]; end` | ★**禁用通道的K增益清零**！K是(n×m)阵，对应禁用量测的整列设0→这些量测对状态校正毫无贡献。同时hasmeas保留"本次有效量测"列表 | ★ |
| 73 | `if ~isempty(hasmeas), kf.measlog=bitor(...); kf.measlost(hasmeas)=0; end` | ★两个工程计数器：<br>① measlog：位掩码日志，sum(2.^(ch-1))把哪些通道更新过编码成整数（事后回放用）<br>② measlost：成功更新的通道"丢包计时"清零，重新从0开始计 | ★ |
| 74 | `kf.xk = kf.xkk_1 + kf.Kk*kf.rk;` | ★★KF公式⑤a：状态校正 x̂ₖ⁺ = x̂ₖ⁻ + K·r。把量测残差按增益权重"回灌"到状态上 | ★★ |
| 75 | `kf.Pxk = kf.Pxkk_1 - kf.Kk*kf.Pykk_1*kf.Kk';` | ★★KF公式⑤b：协方差校正 Joseph形式 P⁺ = P⁻ − K·S·Kᵀ。比(I−KH)P⁻多一次乘法但**数值更稳定，天然保证P半正定** | ★★ |
| 76-78 | `if length(kf.fading)>1`<br>`s = diag(sqrt(kf.fading/2));`<br>`kf.Pxk = s*(Pxk+Pxk')*s;` | 分情况遗忘因子：若fading是向量（每个状态独立遗忘因子），则用对角阵s做缩放：P ← s·(P+Pᵀ)·s = ½·√α · (P+Pᵀ) · √α，等价P ← α·½·(P+Pᵀ) | |
| 79-81 | `else`<br>`kf.Pxk = (kf.Pxk+kf.Pxk')*(kf.fading/2);` | ★★★**单遗忘因子+对称化！**这一行做了三件事：<br>① `(P+P')/2`：强制对称化——浮点误差让P不对称累计几千步会非正定，每步对称化是保正定最便宜的手段<br>② 乘`fading`：遗忘因子α∈[1,1.02]。P←αP，人为"吹大"协方差，让KF对旧模型的信任度衰减，跟踪时变系统<br>③ /2：因为P+P'已经双倍了，除2还原幅值 | ★★★ |

### 第二段③：状态约束+P约束收尾 (L82-L103)

| 行号 | 源码 | 注释 | 重点标记 |
|------|------|------|----------|
| 82 | `if kf.xconstrain==1  % 16/3/2018` | 状态硬约束开关（2018/3/16新增功能）。物理上不可能超范围的状态直接钳位 | |
| 83-89 | `for k=1:kf.n`<br>`if xk(k)<xmin(k), xk(k)=xmin(k);`<br>`elseif xk(k)>xmax(k), xk(k)=xmax(k); end`<br>`end` | 逐维状态钳位：陀螺/加计零偏不可能超过±10°/h或±10mg，硬截断防止KF偶尔迭代出物理不可信值 | |
| 90 | `（空行）` | | |
| 91 | `if kf.pconstrain==1  % 1/6/2017` | ★★★P阵协方差约束开关（2017/6/1新增，工程救星！） | ★★ |
| 92 | `for k=1:kf.n` | 逐对角线元素遍历（注意：只遍历对角，非对角通过行列缩放联动） | |
| 93-95 | `if Pxk(k,k)<Pmin(k)`<br>`Pxk(k,k)=Pmin(k);`<br>`kf.Pmini(k)=kf.Pmini(k)+1;` | ★Pmin处理：**直接硬截断**对角线元素。P(k,k)过低→KF过度自信→锁死。Pmini(k)计数器（2026/6/28新增）：监控触发了多少次Pmin，事后分析KF健康度 | ★★ |
| 96 | `elseif Pxk(k,k)>kf.Pmax(k)` | ★Pmax处理：**不能直接截断对角线**！那样会破坏P的半正定性（对角截断后其他元没改，可能出现负特征值）。所以用"行列等比例缩放" | ★★★ |
| 97 | `ratio = sqrt(kf.Pmax(k)/kf.Pxk(k,k));` | ★★★求缩放系数：目标 P(k,k) → Pmax，所以对角值要乘以 r² = Pmax/Pkk，即 r = √(Pmax/Pkk)。对整行×r、整列×r → 对角P(k,k)就变成了 r²·Pkk = Pmax | ★★★ |
| 98 | `kf.Pxk(:,k) = Pxk(:,k)*ratio;  Pxk(k,:) = Pxk(k,:)*ratio;` | ★★整列×r + 整行×r = 对P做相似变换 D·P·Dᵀ，其中D=diag(1,..,r,..,1)。相似变换保持对称半正定性，P(k,k)刚好缩放到Pmax，其他元素P(i,k)与P(k,j)也被合理联动 | ★★★ |
| 99 | `kf.Pmaxi(k)=kf.Pmaxi(k)+1;` | Pmax触发计数器，同理Pmini，用于离线分析某状态P阵是否经常爆炸 | |
| 100-101 | `end  % elseif Pmax 结束`<br>`end  % for k=1:n 结束` | 关闭分支与循环 | |
| 102 | `end  % if pconstrain==1 结束` | 关闭P约束块 | |
| 103 | `end  % else (非T分支结束)` | 最外层else关闭——量测更新整体结束。函数隐式return修改后的kf | |

---

## 🔍 断点调试建议

**目标脚本**: [test_SINS_GPS_153.m](file:///workspace/psins/demos/test_SINS_GPS_153.m)

### 调试1：观察第一次'T'更新后的P阵累积
1. 在 `kfupdate.m` **L39**（`kf.xk = kf.xkk_1;` 即'T'分支最后一行）设条件断点：
   ```
   条件: mod(ins.t, 1) < 0.02 && mod(ins.t, 1) > 0      (即t≈整秒前)
   ```
   或者简单设普通断点，一直Continue直到第一次GNSS量测到达前（t≈1.0s前最后一步，t=0.98s或0.99s处）
2. 命中后观察：
   ```matlab
   diag(kf.Pxk)     % 15个对角元素
   % 观察现象：
   %  φ(1:3)  ≈ P0_phi + t * Q_phi   姿态误差方差随时间线性增长
   %  δv(4:6) ≈ P0_dv + t * Q_dv     速度误差方差随时间增长
   %  δp(7:9) ≈ P0_dp + t² * ...     位置误差方差近似二次增长（因P=ΦPΦ'+Q, Φ含积分项）
   %  eb/db(10:15) ≈ 初始P0          零偏方差增长较慢（随机游走）
   ```

### 调试2：观察第一次'M'更新——KF真正"起作用"的瞬间
1. 在 `kfupdate.m` **L75**（`kf.Pxk = ...` 协方差校正后）设断点，继续运行
2. 第一次命中就是第一次GPS位置量测到达（mod(t,1)==0触发），立即观察：
   ```matlab
   % 量测更新前看一下（需要回到L55断或用L48之后的值）
   % 量测更新后（当前断点）：
   diag_before = [某种方式看Pxkk_1对角] % 或者直接看L52断点
   diag_after  = diag(kf.Pxk);
   
   % 重点看位置块(7:9)：
   diag_before(7:9)  % 应该是累积到比较大的值，比如≈100² m²量级
   diag_after(7:9)   % ★骤减！应该≈Rk量级，比如(10m)²=100 m²
   % 这就是卡尔曼滤波的本质：量测到达瞬间，P被"压缩"到接近R，说明吸收了观测信息
   
   % 再看增益K对应的位置列
   kf.Kk(7:9, :)     % 位置状态对量测的增益应该≈0.5~0.9之间，说明信息吸收充分
   ```

3. 继续跑2~3次'M'更新，看：
   - 每次更新后P位置对角↓，更新之间('T'更新)P位置对角↑
   - 形成"锯齿状"——这就是典型的KF"预测膨胀+校正压缩"循环
   - Sage-Husa：观察 kf.Rk 的对角元，如果残差持续大，Rk应该逐渐从初始值往上爬

---

## ❌ 初学者最容易踩的坑

### 坑①：忘记'T'/'M'/'B'三字含义，调用参数错配
```
常见错误1：以为 kfupdate(kf) 是"什么都不做初始化"
          实际 kfupdate(kf) = 只做'T'时间更新！xk已经被Φ乘过了！
常见错误2：量测更新写成 kfupdate(kf, yk) 不写第三个参数
          → 实际默认'B' = 先Time再Meas
          → 如果之前循环里已经单独做过kfupdate(kf)（Time），
             就会重复做一次Time，等效于"多走了一步"
             → Φ被多乘一次 → P比正常情况下大很多 → 估计发散
正确写法2选1，不要混用：
  A) 高频: kf=kfupdate(kf); 低频: kf=kfupdate(kf,yk,'M');  （test_SINS_GPS_153写法）
  B) 高频: kffk求Φ存好;   低频: kf=kfupdate(kf,yk,'B');    （"一步到位"写法）
```

### 坑②：残差 r = y−Hx⁻ 符号写反→估计直接反向飘
```
有人在自定义量测时手动套公式写成：
  r = H*xkk_1 - yk;    % ❌ 预测减实际=负残差
然后 xk = xkk_1 + K*r  → 等效 xk = xkk_1 - K*(正确残差)
校正方向完全反了！状态误差越"校正"越大。

诊断方法：断L56，看rk符号——如果某通道真实误差应该是正的（位置偏东GPS显示偏东），
        rk应该是正的但你看到是负的→99%是残差写反了
牢记：残差 = "实际看到什么" 减 "我们预测该看到什么"
      即   r = 观测 减 预测观测   （y − Hx）
```

### 坑③：不做P阵对称化→数值累积→chol报错→KF崩
```
场景：有人把L78-80改成 kf.Pxk = kf.Pxkk_1 - kf.Kk*kf.Hk*kf.Pxkk_1;
     （即所谓"标准形式" (I-KH)P⁻，并去掉了(P+P')/2）
     跑了1000多步仿真一切正常，突然在第1835步报错：
       Error using chol
       Matrix must be positive definite.
     
原因：浮点加减不满足严格分配律
     (I-KH)P⁻ = P⁻ - KHP⁻ 数学上= P⁻ - KSKᵀ，但数值上有1e-15级差异
     每步积累一点点不对称(P-P'≈1e-14)，累积几千步后P出现微小负特征值≈-1e-12
     下一步求S=HP⁻Hᵀ+R，S也非正定，invbc/chol直接崩
     
PSINS作者的保险三件套（缺一不可）：
  ① L75用Joseph形式 P ← P⁻ − K·S·Kᵀ （对称保持性最好）
  ② L80强制 (P+P')/2 每步对称化 （1e-15级误差被抹除）
  ③ L91-102 Pconstrain 防坍防炸 （数值病态兜底）
```

### 坑④：Pconstrain 开了但 Pmin/Pmax 设得差几个数量级
```
典型翻车：Pmin=[1e-20, ...] 设太小
         → P坍缩到1e-18时还没触发Pmin
         → K=P⁻HᵀS⁻¹ → K→0 → 状态死锁，再准的量测也"吸收不动"
反向翻车：Pmax=[1e20, ...] 设太大
         → P爆炸到1e15还没触发Pmax
         → K→∞ → x⁺=x⁻+K·r 对量测噪声过敏，估计抖成筛子
经验值（15状态SINS/GPS）：
  Pmin(φ) ≈ (0.001°)² = (1e-5 rad)² ≈ 1e-10
  Pmin(dv)≈ (0.001m/s)² = 1e-6
  Pmin(dp)≈ (0.1m)² = 1e-2
  Pmax ≈ 1e6 × Pmin 比较稳妥
```

---

## 🎯 配套练习

### 练习题目1：关闭Pconstrain看P阵坍缩死锁

修改 `/workspace/psins/demos/test_SINS_GPS_153.m`，找到kfinit后设置pconstrain的位置（或在kfinit行之后加一行）：

```matlab
% 在 test_SINS_GPS_153.m 中 kfinit 之后添加/修改：
kf.pconstrain = 0;   % 关闭P约束（默认应该是1，注释掉就是0或手动写0）
kf.adaptive   = 0;   % 顺便关掉自适应R，观察更纯粹的坍缩

% 同时修改仿真时间拉长点：
% 找到NN/totalTime参数，改成1000秒（原默认可能是短时间）
```

然后运行仿真，结束后画P阵对角线：
```matlab
% 在仿真结束后的kfplot调用之前，手动画：
figure;
subplot(3,1,1);
plot(kf.Pxk_log(:,1:3));  title('姿态误差P对角 (rad^2)'); grid on;
subplot(3,1,2);
plot(kf.Pxk_log(:,4:6));  title('速度误差P对角 (m^2/s^2)'); grid on;
subplot(3,1,3);
plot(kf.Pxk_log(:,7:9));  title('位置误差P对角 (m^2)'); grid on;
xlabel('仿真步数');
% 观察现象：
% 某些对角元素会单调下降到 1e-25 ~ 1e-30 之间的极小值并卡住
% 对应状态的 K(k,:) 增益也变成≈0——KF对该状态已经"死锁"，不再相信任何量测
```

**进阶思考题**：把pconstrain重新开回=1，画Pmini/Pmaxi计数器 vs 时间：
```matlab
% 假设你把kf.Pmini/kf.Pmaxi也记录到log里了
figure; bar([kf.Pmini; kf.Pmaxi]'); 
legend('Pmin触发次数','Pmax触发次数');
xlabel('状态编号(1~15)'); 
% 看看哪个状态最容易坍缩（一般是零偏10~15维，因为Q最小）、哪个最容易炸
```

### 练习题目2：Sage-Husa β衰减可视化

写一个小脚本纯数学验证β衰减公式：
```matlab
%% 参数
b = 0.001;       % PSINS默认b，查kfinit.m（通常很小）
beta_init = 0.99;% 初始beta
N = 2000;        % 迭代步数（模拟2000次量测更新≈2000s仿真）

%% 迭代
beta_hist = zeros(N,1);
beta = beta_init;
for k = 1:N
    beta_hist(k) = beta;
    beta = beta / (beta + b);   % 对应 L66
end

%% 绘图
figure; 
semilogy(1:N, beta_hist, 'b-', 'LineWidth', 1.5);
xlabel('量测更新步数 k'); ylabel('beta'); grid on;
title('Sage-Husa变遗忘因子beta衰减曲线');

%% 验证渐近公式: beta ≈ beta0 / (1 + k*b*beta0)  近似解
hold on;
k_vec = 1:N;
beta_approx = beta_init ./ (1 + k_vec * b * beta_init);
semilogy(k_vec, beta_approx, 'r--', 'LineWidth', 1.5);
legend('精确迭代值', '近似公式 beta0/(1+k*b*beta0)');
% 结论：b越小，beta衰减越慢，自适应R的"学习时间"越长但越稳
%       b越大，beta衰减越快，初期R剧烈变化，后期迅速冻结

%% 再看 R 的实际变化：假设ry恒定=1，R从10开始
b = 0.001; beta = 0.99;
R_hist = zeros(N,1); R = 10; ry = 1;  % 真实R应该=1，初始R误设为10（太保守）
for k = 1:N
    R_hist(k) = R;
    R = (1-beta)*R + beta*ry;
    beta = beta / (beta + b);
end
figure; plot(1:N, R_hist, 'LineWidth',1.5); grid on;
xlabel('步数'); ylabel('自适应R估计值'); title('Sage-Husa从R=10收敛到真R=1的过程');
% 观察：初期因beta大→R快速下降；后期beta→0→R停在接近1处，不再变
```
