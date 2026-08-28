# trjsegment / WAT 表 / trjsimu 三者关系与 WAT 重生成

> 位置：`civil_wiki/docs/惯性导航/assets/miniins/demos/`
> 关联：`demo_sins_dr.m`（M4 组合 demo，正文 §1 即 WAT 表）、`core/trjsegment.m`、`core/trjsimu.m`、`gen_trj.m`（P1 拆解，完整 14 段展开）

---

## 一、一句话结论

`trjsegment` 是**生成** WAT 表的"航段语言"函数；WAT 表是它产出的**数据**（N×8 矩阵，逐段描述运动）；`trjsimu` 是**消费** WAT 表、数值积分出真值轨迹 + IMU 读数的下游。三者是「**builder → 数据 → 积分器**」的链路，**不是并列替代关系**——WAT 表和 trjsegment 也不是"两种方法"，而是"产物 vs 制造它的工具"。

---

## 二、三者角色对照

| 角色 | 是什么 | 一句话 | 在库中的位置 |
|---|---|---|---|
| **trjsegment** | 函数（航段语言 builder） | **制造** WAT 表：往 `seg.wat` 逐行追加 | `core/trjsegment.m` |
| **WAT 表** | 数据（N×8 矩阵） | 轨迹的"段描述"，每行一段匀速/匀角速运动 | `demo_sins_dr` 第 38 行（字面 21 行）；`gen_trj` 运行时生成 |
| **trjsimu** | 函数（正演积分器） | **消费** WAT 表 → 数值积分出 `avp` 真值 + `imu` 增量 | `core/trjsimu.m` |

---

## 三、数据流

```
trjsegment(...)  ──build──▶  WAT 表(N×8)  ──integrate──▶  trjsimu  ──▶  avp真值 + imu
  （往 seg.wat 加行）          [lasting,vel,wx,wy,wz,ax,ay,az]
```

下游链路（以 `demo_sins_dr` 为例）：

```
WAT ─▶ trjsimu(avp0, WAT, ts) ─▶ trj(含 avp真值 + imu)
                               └▶ odsimu(trj) ─▶ 完美里程 od
imu ─(注入 eb/db/davp)─▶ insupdate 循环（SINS）
od  ─▶ drupdate 循环（DR）
两者 ─▶ kffk/kfupdate ─▶ 组合解算
```

`trjsimu` 只认 WAT 表，不认任何"语义"——它不关心某段叫"左转"还是"抬头"，只按 [w, a] 逐拍积分。所以**轨迹的"长相"完全由 WAT 表的数字决定**。

---

## 四、WAT 表格式（8 列）

每行一段运动，列定义：

| 列 | 名字 | 含义 | 单位 |
|---|---|---|---|
| 1 | `lasting` | 该段持续时间 | s |
| 2 | `vel` | 段**初**速度大小（由 `seg.vel` 游标填） | m/s |
| 3 | `wx` | 角速度 x（横滚速率） | rad/s |
| 4 | `wy` | 角速度 y（俯仰速率） | rad/s |
| 5 | `wz` | 角速度 z（**航向**速率，yaw） | rad/s |
| 6 | `ax` | 加速度 x（体轴前进方向） | m/s² |
| 7 | `ay` | 加速度 y | m/s² |
| 8 | `az` | 加速度 z | m/s² |

约定（PSINS 机体系，x右 y前 z上）：`wz` 正 = 航向增大 = 左转；`ax` 正 = 沿前进方向加速；`ay` 在协调转弯时承载向心加速度 `cf = w·v`。

---

## 五、trjsegment 怎么工作

### 5.1 航段语言（链式调用，每行加一段）

```matlab
seg = trjsegment(struct(), 'init');          % 初始化，vel0 默认 0
seg = trjsegment(seg, 'uniform', 100);       % 匀速 100 s
seg = trjsegment(seg, 'accelerate', 10, 1);  % 直线加速 10 s，a=1 m/s²（末速 0→10）
seg = trjsegment(seg, 'turnleft', 45, 2);    % 左转 45 s，w=2 °/s（协调：自动算 cf=w·v）
...
WAT = seg.wat;                               % ← 这就是生成的 WAT 表
```

### 5.2 关键机制

1. **`seg.vel` 是"内部游标"**：`accelerate` 后 `seg.vel = seg.vel + a·t`；`deaccelerate` 则减。下一段的 `vel` 列自动填末速。
2. **协调转弯自动算向心加速度**：`turnleft/right` 里 `cf = w·vel`，填入 `ay`（保持 |v| 不变、方向转北所需的横向加速度）。
3. **每种航段 = 往表里塞一行**：`uniform`→`[t, v, 0,0,0, 0,0,0]`；`headup`→`[t, v, 0,+w,0, 0,0,0]`；`rollleft`→`[t, v, +w,0,0, 0,0,0]` 等。

支持 8 种基本段：`init / uniform / accelerate / deaccelerate / headup / headdown / turnleft / turnright / rollleft / rollright`（详见 `core/trjsegment.m` 头部注释）。

---

## 六、为什么 `demo_sins_dr` 里 WAT 是"字面矩阵"而不是调 trjsegment

你看到的 `demo_sins_dr.m` 第 38 行是：

```matlab
WAT = [ 100,  0,  0, 0, 0,        0, 0, 0;
         10,  0,  0, 0, 0,        0, 1, 0;     % 加速 0→10
        100, 10,  0, 0, 0,        0, 0, 0;
         ... (共 21 行) ];
```

注释写着 **"P1 产物：test_SINS_trj 展开 21 行"**。含义是：

> PSINS 原版 `test_SINS_trj.m` 当年就是用 `trjsegment` 链式拼了 14 个航段生成这份 WAT 的。我们在 **P1 阶段把那段 `trjsegment` 调用链"展开/烘焙"成了这 21 行的字面矩阵**，让 M4 demo 自包含、不依赖运行时再调 builder。

两种"生成 WAT"是**同一份 WAT 的两种形态**：
- **语义上**：`trjsegment` 一行行拼（可读、好改）
- **demo 里**：已展开成字面矩阵（自包含、跑得快、且已对拍 P4 验证 44.9 m）

`gen_trj.m`（P1 拆解脚本）里完整复刻了 trjsegment 的展开过程（14 段 → 21 行），可对照看每条航段怎么变成 WAT 的一行。

---

## 七、怎么用 trjsegment 重新生成一条新 WAT

假设你想换一条更简单的轨迹（加速 → 匀速 → 左转 → 爬升），完整可跑示例：

```matlab
% 在任意脚本里（先 addpath 到 core/）
addpath('.../miniins/core');

seg = trjsegment(struct(), 'init');            % vel0 = 0
seg = trjsegment(seg, 'accelerate', 10, 1);    % 加速 10 s @1 m/s² → 末速 10
seg = trjsegment(seg, 'uniform', 100);         % 匀速 100 s
seg = trjsegment(seg, 'turnleft', 30, 2);      % 左转 30 s @2 °/s（cf=2°/s·10=0.349）
seg = trjsegment(seg, 'headup', 10, 3);        % 抬头 10 s @3 °/s（爬升）

WAT = seg.wat;                                 % 生成的 WAT 表
% 然后照 demo 那样：trj = trjsimu(avp0, WAT, ts);
```

生成的 `WAT` 前几行（按 `trjsegment.m` 当前实现）：

| 段 | lasting | vel | wx | wy | wz | ax | ay | az |
|---|---|---|---|---|---|---|---|---|
| accelerate | 10 | 0 | 0 | 0 | 0 | 1 | 0 | 0 |
| uniform | 100 | 10 | 0 | 0 | 0 | 0 | 0 | 0 |
| turnleft | 30 | 10 | 0 | 0 | 2°/s | 0 | **+0.349** | 0 |
| headup | 10 | 10 | 0 | 3°/s | 0 | 0 | 0 | 0 |

`seg.vel` 游标在 accelerate 后变成 10，所以后续 turnleft 的 `cf = w·v = 2°/s × 10 = 0.349` 自动正确。

---

## 八、⚠️ 一致性提示（重新生成前必读）

`core/trjsegment.m` 是 **PSINS 的教学简化版**，其约定与 `demo_sins_dr` 里那份"P1 从 PSINS 原版展开"的字面 WAT **不完全一致**，已知两处差异：

1. **`turnleft` 的 `ay` 符号相反**
   - `trjsegment.m`（2026-08-24 修正后）：`ay = +cf`
   - `demo_sins_dr` 字面 WAT 第 5 行：`45, 10, 0, 0, 2°/s, **-0.349**, 0, 0`（即 `ay = -cf`）
2. **`rollleft` 的 `az` 细微项**：`demo` 字面 WAT 滚转段带 `az = +0.349`，`trjsegment.m` 简化版 `rollleft` 写 `az = 0`（未含协调向心项）。

含义：**不要直接拿 `trjsegment` 生成的 WAT 替换 `demo_sins_dr` 已验证的字面 WAT**——符号/细微项不同会让轨迹方向或曲率变化，破坏与 P4 的 44.9 m 对拍基准。

正确做法：
- 若只是想**换轨迹做实验**：用 `trjsegment` 生成新 WAT，但生成后先跑 `verify_trj`（或肉眼比对轨迹首末点、总里程）确认合理，再喂给 `trjsimu`。
- 若想**复刻 demo 的 21 行**：以 `demo_sins_dr.m` 字面矩阵为权威（已是 P4 验证基准），不要回退到 `trjsegment` 重新拼。
- 若发现约定确实该统一：先确认 PSINS 原版 `trjsegment` 的符号（已记录在 `MEMORY.md` 的 M2 坑里），再改 `trjsegment.m`，并同步回归 `verify_trj` / `verify_dr`。

---

## 九、相关文件索引

| 文件 | 作用 |
|---|---|
| `core/trjsegment.m` | WAT 表生成器（航段语言，简化版） |
| `core/trjsimu.m` | 消费 WAT → 真值 avp + imu（正演积分） |
| `assets/gen_trj.m` | P1 拆解：14 段 → 21 行 WAT 完整展开 + 解析验证 |
| `miniins/demos/demo_sins_dr.m` | M4 demo，§1 即用字面 21 行 WAT（P4 验证基准） |
| `miniins/demos/demo_sins_dr与diag_m4区别说明.md` | 本文的"姊妹文档"：两 demo 区别 |
| `miniins/demos/M4调试实录_组合267到45.md` | M4 bug 定位全过程 |

---

## 十、M5 启动时统一 `trjsegment` 符号的具体步骤（待办清单）

**当前决策**：M4 已交付且全 PASS，**暂不改动 `trjsegment.m` 的符号**（避免无谓回归）；待 **M5 启动第一天统一，且只此一次**。理由：

- 现在改会牵动 M2 `verify_trj`、M3 `verify_dr`，等于多跑一轮回归，毫无收益（demo 仍用字面 WAT，不受影响）。
- M5 本就要造一条新 GNSS 场景轨迹（更长、含 GNSS 中断段），必然调 `trjsegment` 生成新 WAT——届时顺手统一 + 跑一次回归，**一次验证覆盖两件事**。
- 关键约束：M5 第一次造轨迹**前必须先统一符号**，否则新 WAT 的转弯方向相对 PSINS 是"镜像"的，对不上真值。

**统一步骤（照此顺序）**：

1. **确认 PSINS 原版约定**：`turnleft` 的 `ay = -cf`（已记于 `MEMORY.md` M2 坑）；`rollleft` 的 `az` 含协调向心项（原版带 `+cf` 类小量，非 0）。**以 PSINS 原版为准**，不是以 demo 字面 WAT 为准——因为 M5 要新造轨迹，builder 必须"正确"，而 demo 字面 WAT 只是已被烘焙的旧基线。
2. **改 `core/trjsegment.m`**：把 `turnleft`/`turnright` 的 `ay` 由 `+cf` 改为 `-cf`；`rollleft`/`rollright` 补上协调向心 `az` 项（对齐 PSINS 原版）。改完在文件头注释标注「2026-08-27 据 PSINS 原版统一符号」。
3. **回归验证**：依次跑 `verify_trans` / `verify_ins` / `verify_trj` / `verify_dr`，应全 PASS（M2/M3 的自洽性不应因符号修正而破坏）。
4. **重建 demo 基线（可选但建议）**：用统一后的 `trjsegment` 重新拼出 21 行 WAT，与 `demo_sins_dr` 字面矩阵逐行比对——若方向/曲率一致，说明两者已等价，后续可二选一；若仍不一致，以 `verify` 通过 + 与 P4 44.9 m 对拍为准，保留字面 WAT 为权威。
5. **再造 M5 新轨迹**：用统一后的 `trjsegment` 生成 GNSS 场景 WAT（含 outage 段），喂 `trjsimu` → 进入 M5-A 的 KF 集成。

> 注：第 1 步的"以 PSINS 原版为准"与 §8 里"复刻 demo 以字面矩阵为权威"看似冲突，其实是**阶段性的**——M4 阶段 demo 字面 WAT 是权威（已验证）；M5 阶段 builder 修正为 PSINS 原版后，新造轨迹以 builder 为准。两者在 M5 第 4 步回归对齐后应趋于一致。

---

*本文基于 `core/trjsegment.m` / `demo_sins_dr.m` / `gen_trj.m` 三方源码对照整理（2026-08-27）。*
