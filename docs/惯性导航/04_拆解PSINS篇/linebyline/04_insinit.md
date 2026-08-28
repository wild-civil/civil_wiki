# insinit.m 逐行注释 Wiki (PSINS)

> 配套源码: [insinit.m](file:///workspace/psins/base/base1/insinit.m)
> 所属层级: L1纯惯导
> 前置依赖: 00_glvf / 01_earth / 03_insupdate
> 学习目标: 读完能回答3个问题

---

## 🧩 函数作用一句话

初始化SINS结构体，装配初值与默认参数。

---

## 📐 数学原理 / 物理意义

### ① ins结构体字段总览

| 字段 | 维度 | 含义 | 初始化值来源 |
|------|------|------|-------------|
| `ts` | 1×1 | SIMU采样间隔(原始双样周期) | 输入参数ts |
| `nts` | 1×1 | 子步更新周期=2×ts | 由ts推导 |
| `qnb` | 4×1 | 姿态四元数 b系→n系 | a2qua(att0) |
| `att` | 3×1 | 欧拉角[俯仰;横滚;航向] rad | attsyn同步 |
| `Cnb` | 3×3 | 方向余弦矩阵 C_n^b | attsyn同步 |
| `Cnb0` | 3×3 | 初始方向余弦矩阵备份 | 同上 |
| `vn` | 3×1 | 速度[V_E;V_N;V_U] m/s | 输入vn0 |
| `vn0` | 3×1 | 初始速度备份 | 同上 |
| `pos` | 3×1 | 位置[纬度;经度;高度] rad/m | 输入pos0 |
| `pos0` | 3×1 | 初始位置备份 | 同上 |
| `avp` | 9×1 | [att;vn;pos]拼接向量 | 由以上三者 |
| `eth` | struct | 地球参数结构体 | ethinit()生成 |
| `wib` | 3×1 | 机体系下角速度 ω_ib^b | Cnb'·eth.wnin |
| `fn` | 3×1 | 导航系下比力 f^n | -eth.gn(初始静基座) |
| `fb` | 3×1 | 机体系下比力 f^b | Cnb'·fn |
| `wnb` | 3×1 | ω_nb^b 角增量积分 | zeros(3,1) |
| `web` | 3×1 | ω_eb^b | zeros(3,1) |
| `an` | 3×1 | n系下加速度 a^n | zeros(3,1) |
| `wbar` | 3×1 | 角速度均值备份 | zeros(3,1) |
| `Mpv` | 3×3 | 位置→速度映射矩阵 M_pv | 由RMh/RNh/clRNh |
| `MpvCnb` | 3×3 | Mpv·Cnb 组合矩阵 | 计算得到 |
| `Mpvvn` | 3×1 | Mpv·vn 组合项 | 计算得到 |
| `Kg` | 3×3 | 陀螺仪标度因子矩阵 | eye(3) 单位阵 |
| `Ka` | 3×3 | 加速度计标度因子矩阵 | eye(3) 单位阵 |
| `eb` | 3×1 | 陀螺仪零偏 rad/s | zeros(3,1) |
| `db` | 3×1 | 加速度计零偏 m/s² | zeros(3,1) |
| `tauG` | 3×1 | 陀螺相关时间常数 | inf(3,1) |
| `tauA` | 3×1 | 加计相关时间常数 | inf(3,1) |
| `lever` | 3×1 | 杆臂向量 m | zeros(3,1) |
| `tDelay` | 1×1 | 时间延迟 s | 0 |
| `openloop` | 1×1 | 开环标志位 | 0 |
| `an0` | 3×1 | 加速度备份 | zeros(3,1) |
| `anbar` | 3×1 | 加速度均值备份 | zeros(3,1) |

### ② avp2qvp / vpverify 的数据一致性检查

在组合导航中，avp(attitude-velocity-position)是核心9维状态向量。PSINS约定：

```
avp = [ att(3); vn(3); pos(3) ]
    = [ pitch; roll; yaw;  V_E; V_N; V_U;  lat; lon; hgt ]
```

- **顺序严格**: att→vn→pos，共9维；pos是[lat;lon;hgt]而不是[x;y;z]地心地固坐标
- **单位统一**: att用rad(非deg)，lat/lon用rad(非deg)，hgt用m
- `vpverify()` 函数会检查 vn 的量级(≈0~1000 m/s)、pos的lat∈[-π/2,π/2]、lon∈[-π,π]等

### ③ att → quaternion 的转换 (a2qua → qnb)

姿态角→四元数使用 a2qua() 函数，采用 ZYX(航向-横滚-俯仰) 旋转顺序：

```
先按Z轴转航向yaw → 再按Y轴转横滚roll → 最后按X轴转俯仰pitch
```

对应公式（见 `/workspace/psins/base/base0/a2qua.m:23-31`）：

```
att2 = att/2;  [sp,sr,sy] = sin(att2);  [cp,cr,cy] = cos(att2);
q0 = cp*cr*cy - sp*sr*sy
q1 = sp*cr*cy - cp*sr*sy
q2 = cp*sr*cy + sp*cr*sy
q3 = cp*cr*sy + sp*sr*cy
```

确保 q0>0（即实部为正），保证四元数双值唯一性。

### ④ 为什么初始化 Kg=I₃, Ka=I₃, eb=0, db=0 这些默认量级

- **Kg/Ka=单位阵**：标度因子误差默认"已理想校准"，即标称值=真值。后续KFsysclbt标定才会修改为非对角矩阵。
- **eb=0 (≈0.001°/h量级)**：光纤陀螺典型零偏约 0.001~1°/h；如果后续要加入 `imuadderr(imu, eb, db)`，可在外部覆盖。
- **db=0 (≈100μg量级)**：MEMS加速度计零偏约 100μg~1mg，战术级约 10~50μg。
- **tauG/tauA=inf**：随机游走模型中 inf 表示零偏为常值（一阶马尔可夫退化为常值偏置）。

---

## 📝 逐行注释 (4列表格，行号严格对齐)

| 行号 | 原代码 | 中文注释 | 公式/备注 |
|------|--------|----------|-----------|
| 1 | `function ins = insinit(avp0, ts, var1, var2)` | 函数入口：初始化SINS结构体 | 4种调用方式见注释 |
| 2 | `% SINS structure array initialization.` | 函数说明注释 | SINS=Strapdown Inertial Nav System |
| 3 | `%` | 空行 | |
| 4 | `% Prototype: ins = insinit(avp0, ts, var1, var2)` | 函数原型声明 | var1/var2可选参数 |
| 5 | `% Initialization usages(maybe one of the following methods):` | 用法说明开始 | |
| 6 | `%       ins = insinit(avp0, ts);` | 用法1：标准9维avp+采样周期 | |
| 7 | `%       ins = insinit(avp0, ts, avperr);` | 用法2：avp上加初始误差 | avperr为9维误差向量 |
| 8 | `%       ins = insinit(qnb0, vn0, pos0, ts);` | 用法3：直接传qnb/vn/pos/ts | nargin==4分支 |
| 9 | `% Inputs: avp0 - initial avp0 = [att0; vn0; pos0]` | 输入说明：avp0定义 | att(3)+vn(3)+pos(3)=9 |
| 10 | `%         ts - SIMU sampling interval` | 输入ts：IMU采样间隔 | 单位秒s |
| 11 | `%         avperr - avp error setting` | 输入avperr：初值误差 | 用于蒙特卡洛仿真 |
| 12 | `% Output: ins - SINS structure array` | 输出：SINS结构体 | |
| 13 | `%` | 空行 | |
| 14 | `% See also  insupdate, avpset, kfinit.` | 相关函数交叉引用 | |
| 15 | | 空行 | |
| 16 | `% Copyright(c) 2009-2014, by Gongmin Yan, All rights reserved.` | 版权声明 | 作者：严恭敏 西北工业大学 |
| 17 | `% Northwestern Polytechnical University, Xi An, P.R.China` | 单位声明 | 西安，中国 |
| 18 | `% 22/03/2008, 12/01/2013, 18/03/2014` | 创建/修改日期 | |
| 19 | `global glv` | ★ 声明全局变量glv | 包含Re/e2/wie/g0等地球常数 |
| 20 | `    avp0 = avp0(:);` | ★ 将avp0强制转为列向量 | 保证后续length判断正确 |
| 21 | `    if length(avp0)==1, avp0=zeros(9,1); end` | 便捷入口1：avp0=0时生成全零初值 | 即att=vn=pos=0 |
| 22 | `    if length(avp0)==4, avp0=[0;0;avp0(1); 0;0;0; avp0(2:4)]; end` | 便捷入口2：[yaw; lat; lon; hgt]→9维 | 前两个att=0：pitch=roll=0 |
| 23 | `    if length(avp0)==6, avp0=[avp0(1:3); 0;0;0; avp0(4:6)]; end` | 便捷入口3：[att; pos]→9维 | vn默认填0（静基座） |
| 24 | `    if length(avp0)==7, avp0=[0;0;avp0]; end` | 便捷入口4：[yaw; vn(3); pos(3)]→9维 | pitch=roll=0，vn前2项=0 |
| 25 | `    if nargin==2      % ins = insinit(avp0, ts);` | ★ 分支1：2个输入参数，标准用法 | |
| 26 | `        [qnb0, vn0, pos0] = setvals(a2qua(avp0(1:3)), avp0(4:6), avp0(7:9));` | ★ 解析avp→att→qnb0 / vn0 / pos0 | a2qua(att0)：姿态角→四元数 |
| 27 | `    elseif nargin==3  % ins = insinit(avp0, ts, avperr);` | 分支2：3个输入，带初始avp误差 | avperr由avperrstd生成 |
| 28 | `        avperr = var1;` | 取出第3参数命名为avperr | |
| 29 | `        avp0 = avpadderr(avp0, avperr);` | 给avp0加上随机误差 | 用于蒙特卡洛仿真 |
| 30 | `        [qnb0, vn0, pos0] = setvals(a2qua(avp0(1:3)), avp0(4:6), avp0(7:9));` | 同样分解出qnb0/vn0/pos0 | |
| 31 | `	elseif nargin==4  % ins = insinit(qnb0, vn0, pos0, ts);` | 分支3：4个输入，直接传qnb/vn/pos/ts | 注意avp0实际是qnb0 |
| 32 | `        [qnb0, vn0, pos0, ts] = setvals(avp0, ts, var1, var2);` | setvals按顺序赋值给4个变量 | |
| 33 | `    end        ` | 输入分支结束 | |
| 34 | `	ins = [];` | 创建空结构体 | 后续逐字段赋值 |
| 35 | `	ins.ts = ts; ins.nts = 2*ts;` | ★ 采样周期：ts=双样间隔，nts=子步间隔 | nts=Ts/nsub，这里nsub默认=2 |
| 36 | `    [ins.qnb, ins.vn, ins.pos] = setvals(qnb0, vn0, pos0); ins.vn0 = vn0; ins.pos0 = pos0;` | ★ 写入核心导航状态：qnb/vn/pos + 备份vn0/pos0 | |
| 37 | `	[ins.qnb, ins.att, ins.Cnb] = attsyn(ins.qnb);  ins.Cnb0 = ins.Cnb;` | ★★ attsyn同步：从qnb反算att和Cnb，三者一致 | 见attsyn.m；备份Cnb0 |
| 38 | `    ins.avp  = [ins.att; ins.vn; ins.pos];` | ★ 组装9维avp列向量 | [att(3); vn(3); pos(3)] |
| 39 | `    ins.eth = ethinit(ins.pos, ins.vn);` | ★★ 调用ethinit初始化地球参数结构体 | 含RMh/RNh/wnie/wnen/gn等 |
| 40 | `	% 'wib,web,fn,an,Mpv,MpvCnb,Mpvvn,CW' may be very useful outside SINS,` | 注释：以下字段方便外部读取 | |
| 41 | `    % so we calucate and save them.` | | |
| 42 | `    ins.wib = ins.Cnb'*ins.eth.wnin;` | ★ 机体系初始角速度 ω_ib^b = C_b^n·ω_in^n | Cnb'即为C_b^n |
| 43 | `    ins.fn = -ins.eth.gn;  ins.fb = ins.Cnb'*ins.fn;` | 静基座初始比力：f^n=-g^n(向上)；机体系fb=C_b^n·fn | |
| 44 | `	[ins.wnb, ins.web, ins.an] = setvals(zeros(3,1));  ins.wbar = zeros(3,1);` | 初始化中间变量为零 | wnb/web/an/wbar均为3×1 |
| 45 | `    ins.Mpv = [0, 1/ins.eth.RMh, 0; 1/ins.eth.clRNh, 0, 0; 0, 0, 1];` | ★ 位置微分→速度的Mpv矩阵 | dpos/dt=Mpv·vn，RMh/RNh子午/卯酉圈半径 |
| 46 | `    ins.MpvCnb = ins.Mpv*ins.Cnb;  ins.Mpvvn = ins.Mpv*ins.vn; ` | 预计算组合矩阵：MpvCnb=Mpv·Cnb，Mpvvn=Mpv·vn | 后续insupdate中复用 |
| 47 | `	[ins.Kg, ins.Ka] = setvals(eye(3)); % calibration parameters` | ★★ Kg/Ka初始化为3×3单位阵 | 无标度/安装误差，"理想校准" |
| 48 | `    [ins.eb, ins.db] = setvals(zeros(3,1));` | ★★ 陀螺零偏eb、加计零偏db初始化为0 | 后续可由imuadderr/标定覆盖 |
| 49 | `    [ins.tauG, ins.tauA] = setvals(inf(3,1)); % gyro & acc correlation time` | 一阶马尔可夫相关时间→∞表示常值偏置 | |
| 50 | `    ins.lever = zeros(3,1); ins = inslever(ins); % lever arm` | ★ 杆臂向量=0，调用inslever预计算杆臂补偿矩阵 | 非零时inslever生成M_a/M_b |
| 51 | `	ins.tDelay = 0; % time delay` | 时间延迟默认0 | 多传感器异步时设置 |
| 52 | `    ins.openloop = 0;` | ★★ 开环标志位=0表示闭环(默认)；=1表示纯惯导开环不反馈 | 组合导航KFs反馈会用到此字段 |
| 53 | `    glv.wm_1 = zeros(3,1)';  glv.vm_1 = zeros(3,1)';  % for 'single sample+previous sample' coning algorithm` | 双子样圆锥算法前一拍wm/vm备份(全局glv) | 双子样圆锥/划船补偿使用 |
| 54 | `    ins.an0 = zeros(3,1);  ins.anbar = ins.an0;` | 初始化加速度备份字段 | 平滑或后续算法使用 |

---

## 🔍 断点调试建议

在 `test_SINS.m` 里调完 `insinit` 后，在Workspace里点开ins结构体看字段：

1. **ins.qnb** 应该是4维归一化：
   - ‖qnb‖ = 1（误差<1e-15）
   - q0≈1，q1~q3≈sin(θ/2)小角度量级
   - 若 θ=1°，|q1~q3| ≈ 0.0087 rad
2. **ins.Cnb** 应该是3×3正交：
   - det(Cnb) = 1.0（误差<1e-14）
   - Cnb·Cnbᵀ ≈ I₃（各元素误差<1e-14）
3. **ins.eth.RMh / ins.eth.RNh** 应该≈6.4×10⁶ m量级：
   - WGS84赤道半径Re=6378137m
   - 在中纬度 RM≈RN≈6.38e6 m
4. **ins.nts**：
   - 若IMU=100Hz双样→ts=0.01→nts=0.02
   - 若IMU=200Hz双样→ts=0.005→nts=0.01

---

## ❌ 初学者最容易踩的坑

### 坑1：avp顺序/维度错了
**症状**：avp写成 [vn;att;pos] 或者 pos 填 [x;y;z] ECEF坐标，导致 insinit 一运行就炸，qnb出现NaN，ethinit报错纬度超出[-π/2,π/2]。
**规避**：永远记死顺序 `[pitch; roll; yaw; VE; VN; VU; lat; lon; hgt]`，9维，前3姿态、中3速度、后3位置(lat/lon用rad，hgt用m)。

### 坑2：att用deg不是rad
**症状**：a2qua输入的att是度数(如30°直接传30)，而a2qua内部sin/cos按rad计算。结果qnb的q0≈0.15而不是≈0.9999，姿态全错57.3倍。
**规避**：所有角度在传进PSINS函数之前一律 `×deg`（即π/180）。调试时看 `ins.att(1)`：如果>3.14肯定是deg没转。

### 坑3：ts / nts 与IMU实际数据不匹配
**症状**：后面 `insupdate` 跑完，vn积分误差超大，或 `cnscl` 子步计数报维度错。
**规避**：insinit的ts = IMU一行数据对应的"双样"时间。例如imu以100Hz存一行(Δt=0.01s双样)，ts就传0.01。nts会自动变成2×ts=0.02子步。不要传成单样周期。

---

## 🎯 配套练习

**练习题目**：
自己构造 `avp=[30*deg,0,90*deg; 100;0;0; 34*deg,108*deg,0]`（即俯仰30°/横滚0/航向90°，东向速度100m/s，位置西安34°N/108°E/高度0），调用：

```matlab
ins = insinit(avp, imuerrset(1,10,0,0), 5, 0, 0, 0);
```

再手动用 a2qua 算出 qnb：
```matlab
att0 = avp(1:3);
qnb_manual = a2qua(att0);
```

对比 `ins.qnb` 与 `qnb_manual` 的误差：
```
max(abs(ins.qnb - qnb_manual))  < 1e-12
```

**扩展验证**：再从qnb反算Cnb，手动验证 det(Cnb)=1、Cnb·Cnb'=I。
