# 09 SINS/GNSS 动态组合（0x3333 模式）

> 入口 [main.cpp#L90-L126](../../assets/PSINS_STM32F4xx_Keil4_V2.1/scr/main.cpp#L90-L126)。
> 19 维 ESKF 底层与 [08_SINS_GNSS静态组合.md](08_SINS_GNSS静态组合.md) 完全一致，仅**初始化策略、GPS 延迟补偿、量测闸门**不同。

`0x3333` 模式面向**运动载体**（车载/机载）。上电后不立即启动 KF：先等 GPS 水平速度超过 3 m/s，用速度方向（tracking angle）初始化航向 → 重置 KF → 开启真正的 KF 循环；K 时刻每次量测到达前按 `GPS_delay` 回溯到历史 SINS 结果再作差，确保时间同步。

---

## 一、主循环：与静态模式的差异

```cpp
void SINSGPS_moving_main(void)
{
  CKFApp kf(TS);                                     // 同一个 19/6 维 ESKF
  int yawinit = 0;                                   // ★ 动态特有：航向初始化标志
  kf.Init(CSINS(O31, O31, posNWPU));                 // posNWPU = 西工大实验室坐标

  USART1_Configuration(0);
  while(1)
  {
    if(pcmd->cmd1==0xa5a5) { pcmd->cmd1=0; break; }
    if(GAMT_OK_flag==0) continue;  GAMT_OK_flag = 0;
    wm = (*(CVect3*)mpu_Data_value.Gyro*DPS - eb)*TS;
    vm = (*(CVect3*)mpu_Data_value.Accel*G0 - db)*TS;

    if(GPS_OK_flag)                                        // GPS 到达
    {
      GPS_OK_flag = 0;
      if(gps_Data_value.GPS_numSV>6 && gps_Data_value.GPS_pDOP<5.0f)
      {
        CVect3 gpos = *(CVect3*)gps_Data_value.GPS_Pos, gvn = *(CVect3*)gps_Data_value.GPS_Vn;
        if(yawinit) {
          kf.posGNSSdelay = kf.vnGNSSdelay = -outFrame.GPS_delay;   // ★ 动态特有：延迟补偿
          kf.SetMeasGNSS(gpos, gvn);
        }
        else {
          if(normXY(gvn)>3.0) {                                      // ★ 动态特有：航向初始化
            kf.Init(CSINS(a2qua(CVect3(0.0, 0.0, atan2(-gvn.i, gvn.j))),
                         gvn, gpos));
            yawinit = 1;
            continue;                                                // 重置后跳过当次 Update
          }
        }
      }
    }
    if(yawinit) kf.Update(&wm, &vm, 1, TS, 5);       // 只有航向对齐后才启动 KF
    AVPUartOut(kf);
    MainProcessDone();
  }
}
```

对比静态：

| 差异项 | 静态 0x2222 | 动态 0x3333 |
|---|---|---|
| 初始坐标 | 硬编码 JingZhun pos | 硬编码 NWPU pos（`posNWPU` 常量 [PSINS.cpp#L11](../../assets/PSINS_STM32F4xx_Keil4_V2.1/Psinscore/PSINS.cpp#L11)） |
| 初始姿态 | 单位四元数 | 先单位四元数（无效）→ 速度 >3 m/s 时重初始化 |
| 航向来源 | 依赖加速度+磁力计（Mahony/对齐） | **速度跟踪角** atan2(-vE, vN)，ENU 北偏东 |
| GPS 延迟补偿 | 未设置（默认 0） | `-outFrame.GPS_delay`，启用 avpi 回溯 |
| GPS 丢失兜底 | 每 250 ms 注入固定坐标伪观测 | **无兜底**：纯 SINS 自由漂移 |
| KF 启动条件 | 无条件 | `yawinit==1` 才跑 `kf.Update` |

---

## 二、航向初始化：Tracking-Angle 启动法

```cpp
if(normXY(gvn)>3.0) {
    CVect3 att0 = CVect3(0.0, 0.0, atan2(-gvn.i, gvn.j));  // roll=0, pitch=0, yaw=ψ_gps
    kf.Init(CSINS(a2qua(att0), gvn, gpos));
    yawinit = 1;
    continue;
}
```

### 2.1 公式推导（ENU 下）

GPS 速度水平分量 $[v_E, v_N]$（本工程中即 `gvn.i, gvn.j`）。航向角 $\psi$ 定义为 "**从北顺时针转到前进方向的角度**"（导航标准定义）：

$$
\psi = \arctan\frac{v_E}{v_N} = \text{atan2}(v_E, v_N)
$$

代码用 `atan2(-gvn.i, gvn.j)`。注意此处 $v_E$ 前有负号，对照标准定义：

$$
\psi_{\text{code}} = \arctan(-v_E / v_N)
$$

**为什么是负号？**

PSINS 中 `qnb` 定义 body→ENU；`a2qua([φ,θ,ψ])` 对应 ZYX 顺序（先 yaw，再 pitch，再 roll 的逆序），ψ = **yaw**。而 ENU 下"前进方向与北方向夹角"要满足：令 body 轴 x 指向前，水平投影 $[C_{b,11}, C_{b,21}]$（ENU DCM 的 1,1 / 2,1 项），ψ 应等于其夹角。因此 `atan2(-E, N)` 本质是把 **MATLAB/PSINS 惯导 ψ 角的"北偏东"与 C++ 中 a2qua 约定对齐**。这是长期工程验证的经验写法。

> 对该负号存疑的验证方式：GPS 实际向北行驶（$v_E=0, v_N>0$），`atan2(0, v_N)=0` → `ψ=0`（正确——北航向）；向东行驶（$v_E>0, v_N=0$），`atan2(-vE, 0)` → π/2 或 −π/2，应与实际硬件输出对比取反。

### 2.2 速度阈值 3 m/s 的选择

车速场景下 3 m/s ≈ 10.8 km/h，低于此值时：
- GPS 多普勒速度噪声与真实速度量级接近，heading 抖动大；
- 车辆在掉头、倒车时航向会产生 180° 反转。

超过 3 m/s 后 0.1 m/s 速度误差带来的航向误差≈atan(0.1/3)≈2°，可被后续 KF 收敛。

### 2.3 `Init()` + `continue` 的作用

- 若 `yawinit==0` 时接收到有效 GPS 且速度达标，**用 gps 的 pos/vn/ψ 重初始化整个 KF**：`sins.qnb = a2qua(att0)`、`sins.vn = gvn`、`sins.pos = gpos`，并把 `Pk` 重置为初始对角阵（`Pk.SetDiag2(...)`）。
- `continue` 跳过当次 `kf.Update`（避免使用"初始化前的"wm/vm 对新 sins 积分一次，否则会把前一瞬间的错误姿态信息带进来）。

---

## 三、GPS 延迟补偿详解

### 3.1 延迟的物理来源

车载/机载 GPS 从信号到 PVT 解算输出的典型延迟：

1. **射频 → 基带**：相关运算 20~50 ms；
2. **导航解算**：1~5 ms；
3. **UART 串口**：115200 baud 下 UBX-NAV-PVT（92 B）约 8 ms；
4. **MCU 中断处理**：~1 ms。

总延迟 Δt 约 50~150 ms，本工程由硬件实测，范围 `GPS_Delay/10000` 秒，存放在 `outFrame.GPS_delay`（[usart.c#L100](../../assets/PSINS_STM32F4xx_Keil4_V2.1/scr/usart.c#L100)）。

### 3.2 `GPS_Delay` 的计算

[stm32f4xx_it.c#L210](../../assets/PSINS_STM32F4xx_Keil4_V2.1/scr/stm32f4xx_it.c#L210):

```cpp
GPS_Delay = MCU_ms_cnt * 10 - PPS_cnt;   // 单位：0.1 ms
```

- `PPS_cnt`：GPS PPS 引脚上升沿触发的外部中断计数（10 kHz TIMx），表示 PPS 脉冲距现在的 0.1 ms 数；
- `MCU_ms_cnt * 10`：当前系统时戳转 0.1 ms；
- 二者相减得"从最近一次秒脉冲到当前时刻的 0.1 ms"，即 UART 收到 PVT 的时刻相对于 **PPS 前沿**的滞后。严格意义上这只是"MCU 端的时间戳滞后"，并非真正的 PVT 物理延迟，但在 1 Hz GPS 输出与 PPS 紧邻场景下是工程可接受的近似。

→ 最后转成 s：`outFrame.GPS_delay = GPS_Delay / 10000.0f`。

### 3.3 延迟在 `SetMeasGNSS` 中的使用

```cpp
kf.posGNSSdelay = kf.vnGNSSdelay = -outFrame.GPS_delay;   // 延迟 Δt → 回溯 Δt
kf.SetMeasGNSS(gpos, gvn);
```

关键：**tpast 为负值代表"回溯"**。`avpi.Interp(tpast)` 签名 [PSINS.h#L668](../../assets/PSINS_STM32F4xx_Keil4_V2.1/Psinscore/PSINS.h#L668)：

```cpp
int Interp(double tpast);   // AVP interpolation, where -AVPINUM*ts<=tpast<=0
```

avpi 环形缓冲深度 50 × 0.01 s = **0.5 s**，最多回溯 500 ms。延迟超过 500 ms 时 `Interp` 返回 0，`SetMeasGNSS` 内部判断 `&&avpi.Interp(...)` 失败，本次量测被静默丢弃——这是保护机制，不会用错位数据污染估计。

### 3.4 延迟补偿对精度的影响（静态 vs 动态）

- **静止**：SINS 各量不变，是否回溯完全等价；
- **速度恒定 20 m/s**：延迟 Δt = 0.1 s → 位置偏差 2 m，若不补偿 SINS 预测位置与 GPS 观测差 2 m，相当于在 Rt 之外叠加了 2 m 偏差，会导致 KF 增益人为变大；
- **加速 1 m/s²**：Δt = 0.1 s → 速度偏差 0.1 m/s，位置偏差 0.005 m，速度偏差开始起作用；
- **机动过弯 0.5 g 横向**：速度方向每秒变约 5°，0.1 s 滞后 0.5°，方向误差映射到速度分量约 0.17 m/s；

因此动态场景**必须**开启延迟补偿。

---

## 四、动态模式下的惯导误差方程

由于底层 19 维 Ft/Hk 完全复用 CSINSGNSS（见 [08_SINS_GNSS静态组合.md 第六节](08_SINS_GNSS静态组合.md#setft-sethk-feedbackeskf)），这里只补充动态场景特有影响。

### 4.1 杆臂 15:17 的激活

动态中若 IMU 与 GPS 天线不在同一点（车辆典型场景：IMU 中控箱，天线车顶），转向机动时杆臂引入不可忽略的位置/速度差异：

$$
v_{\text{ant}} = v_{\text{imu}} + C_b^n(\omega_{ib}^b \times l) 
\quad\Rightarrow\quad
\delta v = H_k \cdot \delta l,\quad H_k(0:2,15:17) = -C_b^n[\omega^b_\times]
$$

代码对应 [PSINS.cpp#L2653-L2657](../../assets/PSINS_STM32F4xx_Keil4_V2.1/Psinscore/PSINS.cpp#L2653-L2657)：

```cpp
CMat3 CW = sins.Cnb * askew(sins.web);    // web = wm/ts（近似陀螺角速度）
Hk.SetMat3(0,15,-CW);                      // δvn 对 δl
Hk.SetMat3(3,15,-Mpv*sins.Cnb);            // δpos 对 δl，Mpv = pos 对 vn 的雅可比
```

`lvGNSS` 杆臂默认 $l_0 = [0,0,0]$，由 Feedback 在线估计（[PSINS.cpp#L2671](../../assets/PSINS_STM32F4xx_Keil4_V2.1/Psinscore/PSINS.cpp#L2671)）。**注意：杆臂可观性需"有足够旋转机动"（至少航向变化）**。若车辆长期直线，l 不可观，会缓慢发散，这时应把 15:17 的 Pmin 设为物理常值而不是估计。

### 4.2 时间误差 18 dt 的可观性

动基 `nnq=19` 打开 dt 状态（位置、速度同时对 dt 有梯度）：

```cpp
CVect3 MV = sins.Mpv*sins.vn;
Hk.SetClmVect3(0, 18, -sins.an);            // δvn 对 dt = −a^n
Hk.SetClmVect3(3, 18, -MV);                 // δpos 对 dt = −Mpv v^n
```

若 $a^n$ 一直为 0（恒速直线）+ $M_{pv}v^n$ 对 h 的分量可忽略，dt 可观性差；加减速或上坡下坡可显著提高 dt 估计收敛速度。

### 4.3 eb/db 的 Markov 未开启（见静态篇 §8.4）

动基转弯/加速会产生较大比力变化，加速度观测（通过 $a_m \to f^b$ 的扰动）有助于 eb 估计收敛，但 Qt 9:14 = 0 仍限制其跟踪缓慢变化的温漂。若载体长时间运行（>30 min）建议开启 MarkovGyro/Acc。

---

## 五、动态模式的典型收敛轨迹

以下是经验收敛时间（MEMS 9DoF + 6~8 星 GPS、Rt=0.5m/s + 10m，启动速度 10 m/s、航向偏差 5°）：

| 量 | 收敛到 1σ 以内 | 说明 |
|---|---|---|
| 姿态 φ, θ | 10 s | 由重力约束快速收敛 |
| 航向 ψ | 1~2 min | 先靠 tracking angle 给出初值，再靠 GPS 速度观测约束 |
| 速度 v | 30 s | 初值来自 gps，剩余偏差靠 vn 观测吃掉 |
| 位置 p | 1~2 min | 配合 vn 收敛 |
| 陀螺零偏 eb | 2~5 min | 需要足够航向变化才能分离水平 zro bias 与姿态失准 |
| 加计零偏 db | 5~10 min | 水平线加速度（直行、转弯离心）可观测 db 水平分量 |
| 杆臂 l | 需机动 + 10 min 以上 | 需偏航角变化 ≥ 30° 才进入可观区间 |
| dt | 需速度变化 + 5 min | 持续加减速可加速收敛 |

---

## 六、动态模式失效场景

### 6.1 GPS 失锁 > 10 s

动态模式**没有**静态模式的固定坐标伪观测兜底。完全依赖 SINS 自由传播：

- 姿态：约 30 s 到 1°（MEMS ARW~10 °/√h）
- 速度：10 s 后约 0.5~1 m/s 误差（db ≈ 1 mg + 失准耦合）
- 位置：10 s 后 CEP ≈ 5~10 m；30 s 后 CEP ≈ 50~100 m；60 s 可达数百米

隧道/高架等常见遮挡需要更高等级 IMU 或加 DR（里程计）辅助——本工程为此准备了 `CSINSGNSSDR` 子类（`CSINSGNSS + lvOD/posDR`，[PSINS.h#L851-L869](../../assets/PSINS_STM32F4xx_Keil4_V2.1/Psinscore/PSINS.h#L851-L869)），但 STM32 主循环未启用，留给 H7 移植时扩展。

### 6.2 低速长时间行驶

车速 <3 m/s 时 `yawinit` 永不成立，KF 不启动→无 `kf.Update`→输出全是初始化位置 `posNWPU`，姿态为单位四元数。这意味着**"车辆怠速挪车"的几分钟内导航完全不工作**。工程上建议把 `yawinit` 启动条件改为 OR：`normXY(gvn)>3.0 || (mag 有有效输入 && 静态粗对准完成)`，或直接沿用 Mahony 的初始航向（如 `0x1111` 模式）。

### 6.3 硬编码 posNWPU

`posNWPU = LLH(34.246048, 108.909664, 380)` 为西工大自动化学院实验室坐标，只用于 yawinit 前的初始占位。一旦 yawinit=1，该位置立即被 `gpos` 覆盖——因此动态模式下硬编码坐标的危害小于静态模式，但仍建议在启动前注入一次当前 GPS 坐标，避免 `AVPUartOut(kf)` 在启动前几秒发送虚假的"西工大"坐标到上位机。

### 6.4 侧风 / 侧滑场景

侧向风 / 轮胎侧滑时车辆前进方向（heading）与速度方向（course/tracking angle）不一致，二者之差为 sideslip β。β ≈ 5~15°（高速或湿滑路面），tracking-angle 初始化给出的是 **course（航迹角）而非 heading（姿态航向）**，这导致 ψ 偏差一个 β。工程上 `R` 矩阵 yaw 方向不应过于乐观，或当 `norm(vn)` 较小时动态放大 Rt（本工程通过 `Rb=0.6` fading 间接处理，但未针对 β 做显式模型）。

---

## 七、动态模式工程改进清单

按实现难度排序：

1. **Easy**：`yawinit` 启动条件加入 `|| GPS_fixType==3 && 静态粗对准完毕`，避免 <3 m/s 时长时间空转。
2. **Easy**：把 `posNWPU` 改为首次 GPS 锁定位置（`main` 初始化前阻塞等待 1 个 GPS PVT 解）。
3. **Medium**：`Rt(速度)` 随 `normXY(gvn)` 自适应：低速度时扩大速度量测 R（防止 sideslip / 多普勒噪声），可用 `R = Rt * max(1, 5/normXY(gvn))`。
4. **Medium**：开启 `MarkovGyro` / `MarkovAcc`，设置典型 τ = 3600 s GM 系数，让 eb/db 有慢漂建模。
5. **Hard**：接入轮速/里程计，派生 `CSINSGNSSDR` 在主循环使用，增加 `SetMeasOD(v_odometer)` 观测，应对 GPS 隧道遮挡。
6. **Hard**：增加磁力计 yaw 观测（Mahony 的倾角补偿磁场方向）作为 `yawgnss` 三维量测入口，低速 / GPS 失锁时引入航向约束。

---

## 八、动态 vs 静态模式调用链对照

```
 ┌──────── 0x2222 (static) ────────┐    ┌──────── 0x3333 (moving) ─────────┐
 │ Init: 姿态=I, 位置=硬编码精准楼  │    │ Init: 姿态=I, 位置=posNWPU       │
 │ 无 yawinit, 无条件跑 Update     │    │ yawinit=0, 不跑 Update            │
 │                                 │    │ ↓ GPS 到达, v_xy>3 m/s:           │
 │ GPS 到达 → SetMeasGNSS(pos,vn)  │    │   Init(qnb=a2qua(0,0,atan(-vE,vN))│
 │                                 │    │   yawinit=1 → 开始 Update         │
 │ 10s无GPS: 4Hz 伪位置+0.01m/s U  │    │ 无伪观测兜底                     │
 │                                 │    │                                 │
 │ pos/vn delay = 0 (无回溯)       │    │ pos/vn delay = -GPS_delay (回溯) │
 │ AVPUartOut 输出 att/vn/pos      │    │ AVPUartOut 输出 att/vn/pos         │
 └─────────────────────────────────┘    └──────────────────────────────────┘
            ↓                                      ↓
            └───────────── CKFApp::Update / CSINSGNSS 19维ESKF ──────────────┘
```

---

## 参考资料

- [Sola, J. (2017). *Quaternion Kinematics for the Error-State Kalman Filter.*](https://arxiv.org/abs/1711.02508) — GPS 延迟补偿、回溯机制、时间戳对齐的数学推导
- [严恭敏教授 PSINS 官网](http://www.psins.org.cn/) — kf.posGNSSdelay / vnGNSSdelay 字段、2qua 航向初始化、vpi 插值的工程实现
- [严恭敏, 严热宝. *捷联惯导算法与组合导航原理.* 西北工业大学出版社](https://book.douban.com/subject/34759212/) — 动态对准、行进间航向初始化的算法原理
- [Groves, P. D. (2013). *Principles of GNSS, Inertial, and Multisensor Integrated Navigation Systems.* Artech House.](https://www.artechhouse.com/principles-of-gnss-inertial-and-multisensor-integrated-navigation-systems-2nd-edition) — GNSS 速度辅助的 in-motion alignment 工程分类
- [PSINS MATLAB 版 	est_SINS_GPS.m 源码对照](https://github.com/yanliang-zhu/PSINS-MATLAB) — 动态组合模式与 MATLAB 测试脚本的对应关系

---

## 导航

- 上一篇：[08_SINS_GNSS静态组合.md](08_SINS_GNSS静态组合.md)
- 下一篇：[10_H743移植指南.md](10_H743移植指南.md)
- 回到总览：[00_总览与架构.md](00_总览与架构.md)
