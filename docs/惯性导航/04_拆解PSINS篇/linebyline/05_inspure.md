# inspure.m 逐行注释 Wiki (PSINS)

> 配套源码: [inspure.m](../../assets/psins260314/base/base2/inspure.m)
> 所属层级: L1纯惯导
> 前置依赖: 00_glvf / 01_earth / 03_insupdate / 04_insinit
> 学习目标: 读完能回答3个问题

---

## 🧩 函数作用一句话

批量跑纯惯导循环，存轨迹并可选阻尼/外参约束。

---

## 📐 数学原理 / 物理意义

### ① 纯惯导主循环结构：KF步×IMU子样的分组关系

inspure主循环不是一行IMU跑一次insupdate，而是**按KF周期分组**批量跑：

```
时间轴：   ├────── 1个KF更新步 = nn行IMU数据 ────────┤
IMU行：   [k行  k+1行  ...  k+nn-1行] 共nn行
           ↓ 一次性取出 wvm=imu(k:k1,1:6)
           ↓ 调 insupdate(ins, wvm) 内部再拆成 nsub子步
           ↓ 积分完得到本KF步结束时刻的 avp
           ↓ 存入 avp(ki,:) 一行
```

关键参数关系（由 `nnts(glv.ns, imu(:,end))` 返回）：
| 参数 | 含义 | 典型值举例 |
|------|------|-----------|
| `ts` | IMU相邻两行的间隔(双样周期) | 0.005 s → IMU=200Hz |
| `nts` | 单个INS子步更新间隔 | 0.01 s (双样=2子步) |
| `nn` | 1个KF步=多少行IMU | 10 → KF=20Hz (200/10) |
| 等价nts2ins | 1次KF更新=多少次INS子步 | nn×nsub=10×2=20次 |

> ⚠️ 代码里变量名是 `nn`（不是nts2ins），但语义等价：1个KF步内包含的IMU行数。

### ② 为什么 openloop=1 时纯惯导不反馈

`vp_fix='O'` 模式（行55-58、行111-113）下设置：

```matlab
ins.vn0 = zeros(3,1);   % 参考速度设为0
ins.openloop = 1;       % 开环标志=1
```

其物理含义：
- **闭环(openloop=0)**：惯导误差会在KFs更新时被反馈修正，ins状态跳变
- **开环(openloop=1)**：惯导内部状态 **永远不修正**，纯粹靠积分走
- 纯惯导评估时用开环，才能看到SINS本身的误差发散特性（舒勒周期、傅科周期、指数发散等）
- 如果用闭环跑纯惯导，vn被强行拉回vn0，就无法评估惯导算法本身了

### ③ avpcvt 设计：把结构体ins打包成avp数组的设计模式

inspure行117核心操作：
```matlab
avp(ki,:) = [ins.avp; t]';   % ki为行索引，每KF步写一行
```

设计模式：
- **ins结构体**：内部高效更新，包含qnb/Cnb/att/vn/pos/eth/各种临时字段(>30个字段)
- **avp数组(10列)**：对外输出的精简轨迹
  ```
  avp = [ att(3), vn(3), pos(3), t ]  即  [pitch,roll,yaw, VE,VN,VU, lat,lon,hgt, time]
  ```
- 时间对应关系：avp第i行对应第(i×nn)行IMU数据的时刻；avp行数=fix(len/nn)，不是len
- 通用接口avpcvt：avp↔ins互转，insplot/trjplot/inserr等后处理函数都吃avp格式

---

## 📝 逐行注释 (4列表格，行号严格对齐)

| 行号 | 原代码 | 中文注释 | 公式/备注 |
|------|--------|----------|-----------|
| 1 | `function [avp, ins] = inspure(imu, avp0, href, isfig)` | 函数入口：纯惯导批量处理 | 输出轨迹avp + 最终ins |
| 2 | `% Process SINS pure inertial navigation with SIMU log data and` | 函数说明：使用SIMU日志数据处理纯惯导 | |
| 3 | `% using initial condition avp0 = [att0,vn0,pos0].` | 初值条件avp0 | |
| 4 | `%` | 空行 | |
| 5 | `% Prototype: avp = inspure(imu, avp0, href, isfig)` | 函数原型 | href/isfig可选 |
| 6 | `% Inputs: imu - SIMU data array` | 输入imu：[wm(3), vm(3), time] 每行双样 | N×7矩阵 |
| 7 | `%         avp0 - initial parameters, avp0 = [att0,vn0,pos0], or see the code note` | 初值avp0=9维列/行向量 | 或见39-43行便捷入口 |
| 8 | `%         href - reference height for altitude damping.` | href：高度阻尼参考或约束模式 | 见下逐模式 |
| 9 | `%                If href is a char, then ` | href是字符时的模式列表 | |
| 10 | `%                   'v' - velocity fix-damping, =vn0` | 'v'：速度全3维固定=vn0 | |
| 11 | `%                   'V' - vertical velocity fix-damping, =vn0(3)` | 'V'：仅垂直速度VU固定 | |
| 12 | `%                   'p' - position fix-damping, =pos0` | 'p'：位置3维固定=pos0 | |
| 13 | `%                   'P' - position fix-damping, =pos0 & vertical velocity fix-damping, =vn0(3)` | 'P'：位置+垂直速度双固定 | |
| 14 | `%                   'H' - height fix-damping, =pos0(3)` | 'H'：仅高度h固定(默认) | 最常用 |
| 15 | `%                   'f' - height free.` | 'f'：高度自由，无约束 | |
| 16 | `%                   'O' - open loop, vn=0.  Ref: my PhD thesis P41` | 'O'：开环纯惯导，速度置0 | openloop=1 |
| 17 | `%                If href is a 3or2-column vector and length(href)==length(imu)` | href是时间序列向量的模式 | |
| 18 | `%                   'z' - fix vU & hgt, vU=href(:,1), hgt=href(:,2).` | 'z'：按IMU时刻提供VU+hgt参考 | |
| 19 | `%                   'Z' - fix hgt, hgt=href(:,1).` | 'Z'：按IMU时刻提供hgt参考 | |
| 20 | `%         isfig - figure on/off flag` | isfig=1出图，=0静默 | |
| 21 | `% Output: avp - navigation results, avp = [att,vn,pos,t]` | 输出avp：10列矩阵，每行一个KF步 | [p,r,y,VE,VN,VU,lat,lon,h,t] |
| 22 | `%` | 空行 | |
| 23 | `% Example:` | 用法示例1 | |
| 24 | `%     t0=880; t1=940; t2=t1+1000;` | 截取IMU区间 | |
| 25 | `%     att0 = aligni0(datacut(imu,t0,t1), getat(gps(:,4:end),t0));` | 静基座自对准得到初始att0 | |
| 26 | `%     avp = inspure(datacut(imu,t1,t2), [att0;getat(gps(:,4:end),t1)], 'f');` | 跑纯惯导，高度自由 | |
| 27 | `%` | 空行 | |
| 28 | `% Example:` | 用法示例2 | |
| 29 | `%     t0=0; t1=300; t2=inf;` | 前300s对准，之后导航 | |
| 30 | `%     att0 = aligni0(datacut(imu,t0,t1), pos0);` | 粗对准 | |
| 31 | `%     avp = inspure(datacut(imu,t1,t2), [att0;pos0], 'f');` | 纯惯导 | |
| 32 | `% See also  insinstant, attpure, inspurest, insupdate, drpure, nhcpure, insopenav, inspurervs.` | 相关函数 | |
| 33 | | 空行 | |
| 34 | `% Copyright(c) 2009-2014, by Gongmin Yan, All rights reserved.` | 版权 | 严恭敏 |
| 35 | `% Northwestern Polytechnical University, Xi An, P.R.China` | 单位 | 西工大 |
| 36 | `% 12/01/2013, 04/09/2014` | 创建/修改日期 | |
| 37 | `global glv` | 声明全局glv | ns/ugpsHz/g0/Re等 |
| 38 | `    [nn, ts, nts] = nnts(glv.ns, imu(:,end));` | ★★ 解析分组参数：nn=1个KF步含几行IMU；ts=行间隔；nts=子步间隔 | nts2ins语义=nn；IMU200Hz+KF20Hz→nn=10 |
| 39 | `    if avp0(1)>pi, aT=fix(avp0(1)/ts); pos=avp0(2:4);  % avp0=[alignT;pos]` | 便捷入口1：首元素>π认为是对准时长(秒) + pos(3) | 内置调用alignsb自对准 |
| 40 | `        avp0=[alignsb(imu(1:aT,:),pos);pos]; imu(1:aT,:)=[];` | 调用静基座粗对准alignsb，然后删掉前aT行IMU | |
| 41 | `    end` | 便捷入口1结束 | |
| 42 | `    if abs(norm(avp0(1:4))-1)<1e-6, avp0(1:3)=q2att(avp0(1:4)); avp0(4)=[]; end % avp0=[qnb; ...]` | 便捷入口2：首4维是四元数‖q‖≈1时，转成att | 兼容qnb输入 |
| 43 | `    if length(avp0)<9, avp0=[avp0(1:3);zeros(3,1);avp0(4:end)]; end  % avp0=[att;pos]` | 便捷入口3：不足9维，补vn=0 | [att;pos] 6维→9维 |
| 44 | `    ins = insinit(avp0, ts);  vn0 = avp0(4:6); pos0 = avp0(7:9);` | ★★ 调insinit初始化SINS结构体，并保存vn0/pos0参考 | |
| 45 | `    if ~isempty(glv.dgn), ins.eth = attachdgn(ins.eth, glv.dgn); end` | 若设置了扰动重力异常dgn，则挂到eth上 | 高精度导航用 |
| 46 | `    if nargin<3,  href = 'H';  end` | href缺省默认='H'，即高度阻尼=初始hgt | 最常用模式 |
| 47 | `    vp_fix = 'n';` | 默认vp_fix='n'（高度滤波阻尼） | 后续length(href)==1时会覆盖 |
| 48 | `%     vp_fix = 'b';  % unsing baro height` | 注释掉的备用模式（气压高度） | |
| 49 | `    if length(href)==1` | 分支A：href是单个元素（字符或标量高度） | |
| 50 | `        if ischar(href), vp_fix = href;` | A1：是字符→vp_fix=该字符（v/V/p/P/H/f/O/n/b/z/Z） | |
| 51 | `        else` | A2：是标量→视为固定高度值 | |
| 52 | `            t = imu(10:10:end,end);` | 生成参考时间戳（每10行IMU一采样） | |
| 53 | `            href = [href*ones(size(t)),t];  % all to be the same height` | 拼成[固定高度, 时间]两列 | 后面走vp_fix='n' |
| 54 | `        end` | 分支A结束 | |
| 55 | `        if vp_fix=='O',` | ★ vp_fix='O'开环模式设置 | |
| 56 | `            ins.vn0 = zeros(3,1);` | 参考速度置0 | |
| 57 | `            ins.openloop = 1;` | ★★ openloop=1：KFs不反馈修正，纯积分跑 | |
| 58 | `        end` | 'O'模式设置结束 | |
| 59 | `    else` | 分支B：href是数组（多列） | |
| 60 | `        if size(href,2)==3  && length(href)==length(imu)` | B1：3列且行数=IMU→'z'（VU+hgt时间序列） | |
| 61 | `            vp_fix = 'z';` | | |
| 62 | `        elseif size(href,2)==2  && length(href)==length(imu)` | B2：2列且行数=IMU→'Z'（仅hgt时间序列） | |
| 63 | `            vp_fix = 'Z';` | | |
| 64 | `        end` | 分支B结束 | |
| 65 | `    end` | href分类结束 | |
| 66 | `    if vp_fix=='n';` | 'n'模式：二阶高度阻尼滤波器 | |
| 67 | `        alt = altfilt(1000, 1*glv.ugpsHz, 10.0, nts);` | 初始化高度滤波器：带宽1000s？采样1Hz，阻尼10 | altfilt对象 |
| 68 | `        imugpssyn(imu(:,end), href(:,2));` | 建立IMU时间↔参考时间的对应索引表 | |
| 69 | `        dbU = href; dbU(:,1) = 0;` | 初始化dbU=高度偏差记录 | |
| 70 | `    end` | 'n'模式初始化结束 | |
| 71 | `    if vp_fix=='b';` | 'b'模式：气压高度阻尼 | |
| 72 | `        imugpssyn(imu(:,end), href(:,2));` | 时间同步 | |
| 73 | `        ins_vz = ins.vn(3);  ins_h = ins.pos(3);   baro_h = ins_h;` | 初始化状态量 | |
| 74 | `        wn = 0.1; xi = 0.707;  K2 = wn^2+2*glv.g0/glv.Re;  K1 = xi*2*sqrt(K2-2*glv.g0/glv.Re);  % Qin,'Inertial Navigation',Eq.(7.5.3)` | 二阶阻尼参数wn/ξ/K1/K2 | 秦永俊惯导方程7.5.3 |
| 75 | `    end` | 'b'模式初始化结束 | |
| 76 | `    len = length(imu);    avp = zeros(fix(len/nn), 10);` | ★★ 预分配avp内存：行数=fix(len/nn)，每行10列[att,vn,pos,t] | |
| 77 | `    ki = timebar(nn, len, 'Pure inertial navigation processing.');` | 进度条初始化 | |
| 78 | `    for k=1:nn:len-nn+1` | ★★ 主循环开始：k从1起，步长nn，每次处理nn行IMU | 最后一轮保证k+nn-1 ≤ len-nn+1+nn-1=len |
| 79 | `        k1 = k+nn-1;` | ★★ 本KF步IMU的结束行号 | k~k1连续nn行 |
| 80 | `        wvm = imu(k:k1, 1:6);  t = imu(k1,end);` | ★★ 一次性取出本KF步内所有IMU子样：wvm=wm(3)+vm(3)共nn×6矩阵；t取结束时刻 | insupdate内部会拆分子步 |
| 81 | `        ins = insupdate(ins, wvm);  ins.eth.dgnt=t;` | ★★★ 核心：调insupdate做子步解算；并把当前时刻写入eth.dgnt | 1次调用完成内部nsub×nn子步 |
| 82 | `        if vp_fix=='v',      ins.vn = vn0;` | 约束v：强行vn=初始vn0 | |
| 83 | `        elseif vp_fix=='V',  ins.vn(3) = vn0(3);` | 约束V：仅VU=初始VU(3) | |
| 84 | `        elseif vp_fix=='p',  ins.pos = pos0;` | 约束p：强行pos=初始pos0 | |
| 85 | `        elseif vp_fix=='P',  ins.pos = pos0;  ins.vn(3) = vn0(3);` | 约束P：pos+VU双固定 | |
| 86 | `        elseif vp_fix=='H',  ins.pos(3) = pos0(3);` | 约束H：高度h固定=初始h | |
| 87 | `        elseif vp_fix=='N',  N=0; % no damping, same as =='f'` | 约束N：占位无操作 | 等价于'f' |
| 88 | `        elseif vp_fix=='n',` | 约束n：高度滤波阻尼 | |
| 89 | `            alt = altfilt(alt);` | 滤波器一步预测 | |
| 90 | `            [khref, dt] = imugpssyn(k, k1, 'F');` | 查本KF步是否到达参考时间点 | khref>0表示命中 |
| 91 | `            if khref>0` | 命中参考点→量测更新 | |
| 92 | `                dh = ins.pos(3)-ins.vn(3)*dt - href(khref,1);` | 高度偏差预测残差 | |
| 93 | `                alt = altfilt(alt, dh);` | 滤波器量测更新 | |
| 94 | `                ins.pos(3) = ins.pos(3) - alt.xk(3);  % vertical vn&pos feedback` | ★ 反馈修正：位置h减去滤波器估计误差 | 闭环阻尼 |
| 95 | `                ins.vn(3) = ins.vn(3) - alt.xk(2);    alt.xk(2:3) = 0;` | ★ 反馈修正：速度VU减去估计误差 | |
| 96 | `                dbU(khref,1) = alt.xk(1); % just for plot debug` | 记录偏差 | |
| 97 | `            end` | 滤波更新结束 | |
| 98 | `        elseif vp_fix=='b',` | 约束b：气压高度经典二阶阻尼 | |
| 99 | `            [khref, dt] = imugpssyn(k, k1, 'F');` | 参考时间同步 | |
| 100 | `            if khref>0, baro_h = href(khref,1); end` | 若有新气压值则更新 | |
| 101 | `            dh = ins_h - baro_h;` | 高度差 | |
| 102 | `            ins_vz = ins_vz + (ins.an(3)-K2*dh)*ins.nts;` | 阻尼积分1：VU更新（含K2·dh项） | |
| 103 | `            ins_h = ins_h + (ins_vz-K1*dh)*ins.nts;` | 阻尼积分2：h更新（含K1·dh项） | |
| 104 | `            ins.vn(3) = ins_vz; ins.pos(3) = ins_h;` | 写回ins结构体 | |
| 105 | `        elseif vp_fix=='f',` | 约束f：高度自由 | |
| 106 | `            ins.vn(3) = ins.vn(3);  % free, no need` | 空操作，纯积分 | |
| 107 | `        elseif vp_fix=='z',` | 约束z：VU+hgt按参考时间序列 | |
| 108 | `            ins.vn(3) = href(k1,1);  ins.pos(3) = href(k1,2);` | 直接赋值覆盖 | |
| 109 | `        elseif vp_fix=='Z',` | 约束Z：仅hgt按参考时间序列 | |
| 110 | `            ins.pos(3) = href(k1,1);` | 直接赋值h | |
| 111 | `        elseif vp_fix=='O',` | ★ 约束O：开环纯惯导 | |
| 112 | `            ins.vn0 = zeros(3,1);  % duplicate, no need init again` | 重复设置vn0=0（冗余） | |
| 113 | `            ins.openloop = 1;` | ★ 再次确保openloop=1：后续KFs不反馈 | |
| 114 | `        else` | 未知模式 | |
| 115 | `            error('No SINS-pure type matched!');` | 报错退出 | |
| 116 | `        end` | vp_fix多分支结束 | |
| 117 | `        avp(ki,:) = [ins.avp; t]';   %  avp(ki,1:3) = sum(imu(k:k1, 4:6))+ins.eth.gn'*0.01;` | ★★★ 核心：将ins.avp(9维) + t(时间)拼成10列，写入avp第ki行 | 即avpcvt的语义：ins→轨迹行 |
| 118 | `%         avp(ki,7:9) = ins.eth.wnen';  avp(ki,5)=ins.eth.tl;` | 注释调试行：可存eth中间量 | |
| 119 | `        ki = timebar;` | 进度条推进+1 | |
| 120 | `    end` | ★ 主循环for结束 | |
| 121 | `    if k1~=len  % the last IMU record, 2024-07-31` | 处理末尾不足nn行的IMU尾巴 | k1=上一轮结束行 |
| 122 | `        ins = insupdate(ins, imu(k1+1:len,1:6));` | 跑剩余几行 | |
| 123 | `        avp(ki,:) = [ins.avp; imu(end,end)]';` | 写入最后一行avp | |
| 124 | `    end` | 尾巴处理结束 | |
| 125 | `    if nargin<4, isfig=1; end` | 缺省isfig=1（出图） | |
| 126 | `    if isfig==1,` | 出图分支 | |
| 127 | `        if vp_fix=='n'` | 若用了'n'阻尼 | |
| 128 | `            myfig, plot(dbU(:,2), dbU(:,1)/glv.ug), xygo('dbU');` | 画高度阻尼偏差dbU曲线 | |
| 129 | `        end` | 阻尼偏差图结束 | |
| 130 | `        insplot(avp);` | ★ 调用insplot画att/vn/pos 3×3子图 | 标准惯导结果可视化 |
| 131 | `    end` | 出图分支结束 | |

---

## 🔍 断点调试建议

在主循环 `k=1` 第一次迭代（处理最开头的几行IMU）时抓以下对比：

1. **进入循环前**（第78行 break）：抓 `ins.avp`，此时 vn 全是初值，pos 是初值。
2. **第一次调完 insupdate 后**（第81行后）：再次抓 `ins.avp`，应出现：
   - `ins.vn(3)` 变化量 ≈ g₀×Δt ≈ 9.796m/s² × (nn×nts) ≈ 9.796 × 0.2 ≈ 2 m/s（若nn=10，nts=0.02）
   - `ins.pos(3)` 变化量 ≈ 初VU×Δt + ½g₀Δt² ≈ 0 + 0.5×9.8×0.04 ≈ 0.2 m
   - vn/pos的变化量应是纯积分方向：向下(h减小？注意VU向上为正，g指向-U，所以VU(3)会**负向增大**即下坠)

3. **循环跑完后**检查 `avp` 数组：
   - `size(avp,1) ≈ fix(size(imu,1)/nn)`，维度差nn倍
   - `avp(1,10) = imu(nn,7)`（第1个KF步结束时刻=第nn行IMU的时间戳）

---

## ❌ 初学者最容易踩的坑

### 坑1：以为 nn(nts2ins) 必须=1
**症状**：看到 for k=1:nn:len 以为步长必须是1，把nn强行设成1，结果insupdate一次只处理1行，速度慢10倍甚至子步计数报错。
**规避**：nn=10是正常配置！意思是IMU=200Hz(ts=0.005s双样，行间隔=5ms)，KF更新=20Hz，1个KF步=10行IMU=0.05s。inspure每次取10行，内部insupdate再拆成20个子步，完全正确。不要乱改nn。

### 坑2：画图横坐标用成imu.time而不是avp(:,10)
**症状**：`plot(imu.time, avp(1:length(imu),1))`，报维度不一致（avp比imu短nn倍），或者强行截取后图形完全错位。
**规避**：avp的时间轴是 `avp(:,10)`，每一行对应**第nn/2nn/...行IMU**的时刻，画图永远是 `plot(avp(:,10), avp(:,1:3))`。如果要把avp和gps对比，需要用imugpssyn做时间对齐，不能直接索引。

### 坑3：href传错，高度约束模式搞混
**症状**：传 `href='O'` 以为是自由，结果ins.vn全被置0+openloop=1，输出速度永远=0，还以为惯导积分为0了。或者 `href=100` 传一个标量高度，以为是固定hgt=100m，但实际默认模式'H'只用pos0(3)做高度。
**规避**：需要纯惯导无约束用 `href='f'`；需要高度固定用默认 `href='H'` 或不传；开环纯惯导评估误差发散才用 `href='O'`。

---

## 🎯 配套练习

**练习题目**：
复制 `test_SINS_trj` 生成的 trj/imu 数据（或用 `trjsimu` 自己生成一段60s静基座数据）：

**步骤A**：手写纯惯导循环版
```matlab
nn = 1;  % 简化：一次处理1行
len = length(imu);
avp_manual = zeros(len, 10);
ins2 = insinit(avp0, ts);
for k = 1:len
    ins2 = insupdate(ins2, imu(k,1:6));
    avp_manual(k,:) = [ins2.avp; imu(k,7)]';
end
pos_final_manual = avp_manual(end,7:9);
```

**步骤B**：调用inspure函数版
```matlab
avp_func = inspure(imu, avp0, 'f', 0);  % 'f'高度自由, isfig=0
pos_final_func = avp_func(end,7:9);
```

**步骤C**：对比数值等价
```
err_pos = norm(pos_final_manual - pos_final_func)
```

检查 `err_pos < 1e-6`（即微米级），两者应该**数学等价**，因为都是insupdate积分的直接结果。如果差得大，检查nn和kfsub设置是否一致，或手动循环里少加了某步约束。
