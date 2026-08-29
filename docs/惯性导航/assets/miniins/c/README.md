# Mini-INS C 移植版（`c/`）

把 MATLAB 版 `core/` 迁到 C，目标是 **STM32H743 固件可直接用的模块**。当前处于 **D0–D3 试点**：以 `triad` + `mahonyupdate` 打通 SIL 对拍管线，后面 `insupdate` / `kf` 沿用同一套流程。

## 机体系约定（D0 拍板，2026-08-29）

**NED + FRD（航空惯例）**：

- 导航系 n = NED：x 北(N)、y 东(E)、z 地(D)
- 机体系 b = FRD：x 前(F)、y 右(R)、z 下(D)
- 姿态角 `att = [roll; pitch; yaw]`（绕 x / y / z），yaw=0 朝北、**yaw 增大 = 右转**（向东）
- `Cbn` 为体→导航姿态阵：`v_n = Cbn · v_b`

选它的理由：VTOL/无人机生态（PX4、MTi、ArduPilot）通用，便于对标与外接；与 MATLAB 版（PSINS 约定：ENU + 机体 x右 y前 z上、att=[pitch;roll;yaw]）的差异全部收敛到一个固定适配阵（见下）。

### 与 MATLAB 版的适配（上电初始化算一次，不进热路径）

```text
P = [0 1 0; 1 0 0; 0 0 -1]     % ENU→NED，同时 机体(右前上)→机体(前右下)，P·P = I
C_NED = P · C_PSINS · P'
```

已数值验证（MATLAB R2023b）：

| PSINS/ENU 姿态 | NED+FRD 姿态 | 说明 |
|---|---|---|
| `[0;0;0]` | `[0;0;0]` | 水平朝北一致 |
| roll `10°` | roll `+10°` | 同为绕前向轴 |
| yaw `+10°` | yaw `−10°` | PSINS 左转为正，NED 右转为正 |
| pitch `+10°` | 前向轴 z = `−0.174` | NED 的 z 朝下，抬头为负 |

## 目录

```
c/
├── include/    ins_types.h（类型+约定说明）/ ins_math.h / triad.h / mahony.h
├── src/        ins_math.c（四元数·矩阵·NED 欧拉）/ triad.c / mahony.c
├── tests/      test_trans.c / test_triad.c / test_mahony.c（读 CSV → 输出 CSV）
├── sil/        gen_tv.m（生成测试向量+oracle 期望）
│               cmp_sil.m（对拍并报 max|err|）
│               sil_run.m（一键：生成 → 编译 → 运行 → 比对）
│               data/     （生成物，.gitignore 排除）
├── Makefile    make / make float / make clean
└── build/      （生成物，.gitignore 排除）
```

## 快速开始

```matlab
cd docs/惯性导航/assets/miniins/c/sil
sil_run            % double：默认，允差 1e-13
sil_run('float')   % 单精度：固件实际精度，允差 1e-4
sil_run('double', false)   % 跳过编译（已构建过）
```

命令行等价流程：

```bash
cd c && make                                    # 或 make float
./build/test_trans.exe  sil/data/tv_trans_in.csv  sil/data/out_trans.csv
./build/test_triad.exe  sil/data/tv_triad_in.csv  sil/data/out_triad.csv
./build/test_mahony.exe sil/data/tv_mahony_in.csv sil/data/out_mahony.csv
```

## 当前对拍结果（2026-08-29）

| 用例 | double max abs err | float max abs err |
|---|---|---|
| `q2dcm` | 5.6e-16 | 1.3e-07 |
| `dcm2q` | 3.3e-16 | 7.4e-08 |
| `rv2q` | 2.2e-16 | 3.0e-08 |
| `qmul` | 1.1e-16 | 5.8e-08 |
| `a2dcm`（NED） | 1.7e-16 | 1.1e-07 |
| `dcm2att`（NED） | 2.2e-16 | 1.3e-07 |
| `triad` | 3.3e-16 | 8.1e-08 |
| `mahony`（1500 步流式） | 4.4e-16 | 6.0e-08 |

功能性抽查：静止段 10 s，从 3~5° 初始误差收敛到 `[−0.073 0.079 −0.156]°`——yaw 最慢，与 M-A 结论一致（磁助 yaw 回路增益被 cos²(磁倾角) 压低）。

## 两处 NED 化的坑（调试实录）

1. **期望四元数要符号归一**：`q` 与 `−q` 是同一旋转但数值差一个整体负号。C 版 `dcm2q`/`triad` 统一强制 `w>0`，oracle 侧若不做同样归一，大角度例会误报 ~2 的"误差"（实测 1.677）。
2. **NED 重力矢量是 `[0;0;+g]`**（z 朝下）。写成 ENU 的 `−g` 会让加计数据指向"下"，滤波器被拉向 180°（实测末态 −173°）。比力恒为 `f = a − G`。

## 后续（依赖由少到多）

`trans` → `triad` / `mahony`（已完成）→ `insupdate`（需 earth.c + 适配阵 P）→ `kf`（矩阵库 3×3 / 6×6 / 22×22）→ D4 上板（CMSIS-DSP `arm_math` + SPI 驱动 + 时间同步 → HIL）。
