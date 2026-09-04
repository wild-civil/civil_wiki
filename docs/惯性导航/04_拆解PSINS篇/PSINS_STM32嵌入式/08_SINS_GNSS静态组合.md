# 08 SINS/GNSS 静态组合（0x2222 模式）

> 入口 [main.cpp#L54-L125](../../assets/PSINS_STM32F4xx_Keil4_V2.1/scr/main.cpp#L54-L125)（同时包含 0x3333 动态模式的实现，本文只分析 L54~L83 的 static 分支）。
> 19 维 ESKF 实现：继承链 `CKFApp → CSINSGNSS → CSINSTDKF → CKalman`。

`0x2222` 模式面向**静止基座（实验室/桌面）**使用：SINS 以 100 Hz 纯惯导积分，GPS（若存在）以~1 Hz 提供 6 维观测（位置 + 速度），若 GPS 长时间丢失则用固定坐标 + 极小伪速度（0.01 m/s U）注入防止滤波器发散。输出 `att / vn / pos`。

---

## 一、主循环数据流

```cpp
void SINSGPS_static_main(void)
{
  CKFApp kf(TS);                                          // TS = 0.01 s
  CVect3 gpspos = LLH(34.228022, 108.880422, 422.0);      // 硬编码：西安精准楼坐标
  kf.Init(CSINS(O31, gpsvn, gpspos));                     // 初始 vn=0, 初始姿态=单位四元数

  USART1_Configuration(0);
  while(1)
  {
    if(pcmd->cmd1==0xa5a5) { pcmd->cmd1=0; break; }      // PC 退出
    if(GAMT_OK_flag==0) continue;  GAMT_OK_flag = 0;     // 100 Hz IMU 同步
    wm = (*(CVect3*)mpu_Data_value.Gyro*DPS - eb)*TS;
    vm = (*(CVect3*)mpu_Data_value.Accel*G0 - db)*TS;

    if(GPS_OK_flag)                                       // GPS 1 Hz 到达
    {
      GPS_OK_flag = 0;
      if(gps_Data_value.GPS_numSV>6 && gps_Data_value.GPS_pDOP<5.0f) {
        CVect3 gpos = *(CVect3*)gps_Data_value.GPS_Pos;
        CVect3 gvn  = *(CVect3*)gps_Data_value.GPS_Vn;
        kf.SetMeasGNSS(gpos, gvn);                        // 量测注入
      }
    }
    if(GPS_Delay/10000>10 && MCU_ms_cnt%250==0)           // GPS 丢失 >10 s
    {
      kf.SetMeasGNSS(gpspos, CVect3(0,0,0.01));           // 固定坐标 + 伪速度
    }
    kf.Update(&wm, &vm, 1, TS, 5);                        // 5 步分散 KF 更新
    AVPUartOut(kf.sins.att, kf.sins.vn, kf.sins.pos);
    MainProcessDone();
  }
}
```

**时序图**（100 Hz IMU + 1 Hz GPS + 4 Hz 伪位置补投）：

```
10 ms IMU tick :|----|----|----|----|----|----|----|----|----|----|...
SINS + Feedback:  S    S    S    S    S    S    S    S    S    S
nSteps=5      :   /5   /5   /5   /5   /5   /5   /5   /5   /5   /5
                (SetMeas +离散+19步P更新+6维量测更新)
GPS 1 Hz      :                         ● (SetMeasGNSS(pos,vn))
伪位置 4 Hz   :      ●                 ●                   ●   ...(250ms)
```

### 1.1 关键参数含义

| 参数 | 值 | 来源 | 说明 |
|---|---|---|---|
| `TS` | 0.01 s | [KFApp.h#L17](../../assets/PSINS_STM32F4xx_Keil4_V2.1/Psinscore/KFApp.h#L17) | IMU 采样周期 |
| `nStep` | 5 | `main.cpp#L83` | 把 1 个 IMU 周期内的 KF 拆成 5 步，降低每步计算抖动，避免中断阻塞 |
| `GPS_Delay >10s` | `GPS_Delay/10000` | 见下文 | GPS 时间戳与 MCU 时间差，单位 s；>10s 视为无 GPS |
| 伪速度 `CVect3(0,0,0.01)` | 0.01 m/s U 方向 | `main.cpp#L81` | 保持垂向速度观测约束，避免 vn.k 漂移发散 |

---

## 二、CKFApp 构造与 P/Q/R 调参

### 2.1 状态 / 观测维度

```cpp
CKFApp::CKFApp(double ts):CSINSGNSS(19, 6, ts)
{
  // state: 0-2 phi; 3-5 dvn; 6-8 dpos; 9-11 eb; 12-14 db; 15-17 lever; 18 dt
  // meas:  0-2 dvn; 3-5 dpos
  SetCalcuBurden(100,-1);
}
```

**19 维状态向量**（ESKF 误差状态）：

| 位置 | 物理量 | 符号 | 单位 | 来源 |
|---|---|---|---|---|
| 0:2 | 姿态失准角 | $\delta\phi = [\phi_E,\phi_N,\phi_U]$ | rad | PSINS 误差模型 |
| 3:5 | 速度误差 | $\delta v^n = [\delta v_E,\delta v_N,\delta v_U]$ | m/s | PSINS 误差模型 |
| 6:8 | 位置误差 | $\delta p = [\delta\lambda,\delta L,\delta h]$（经纬度弧度，高米） | [PSINS.h#L134](../../assets/PSINS_STM32F4xx_Keil4_V2.1/Psinscore/PSINS.h#L134) |
| 9:11 | 陀螺零偏 | $\delta e_b$ | rad/s | Gauss-Markov（仅在 IMU grade 版开启 Markov） |
| 12:14 | 加计零偏 | $\delta d_b$ | m/s² | 同上 |
| 15:17 | GNSS 天线杆臂 | $l_{\text{GNSS}}$（body 系） | m | IMU 中心与 GPS 天线偏心 |
| 18 | 量测时间误差 | $dt$ | s | GPS 时间戳偏差 |

**6 维观测**（0:2 速度；3:5 位置）：

$$
z_v = \hat v^n - v_{\text{GPS}},\quad z_p = \hat p - p_{\text{GPS}}
$$

### 2.2 协方差矩阵

`CKFApp::Init`（`grade=-1` 未覆盖 PSINS 默认，**等价 MEMS grade**）:

```cpp
void CKFApp::Init(const CSINS &sins0, int grade)
{
  CSINSGNSS::Init(sins0);
  Pmax.Set2(fPHI(600,600), fXXX(500), fdPOS(1e6), fDPH3(5000), fMG3(10), fXXX(10), 0.1);
  Pmin.Set2(fPHI(1,10),    fXXX(0.01),fdPOS(0.1), fDPH3(50),   fUG3(500),fXXX(0.01),0.0001);
  Pk.SetDiag2(fPHI(600,600),fXXX(1.0), fdPOS(200), fDPH3(1000),fMG3(10), fXXX(1.0), 0.01);
  Qt.Set2(fDPSH3(10.1),  fUGPSHZ3(100.0), fOOO, fOO6, fOOO, 0.0);
  Rt.Set2(fXXZ(0.5,1.0), fdLLH(10.0,30.0));
  Rmax = Rt*100;  Rmin = Rt*0.01;  Rb = 0.6;
  FBTau.Set(fXX9(0.1), fXX6(1.0), fINF3, INF);
}
```

**宏展开参考**（[PSINS.h#L118-L138](../../assets/PSINS_STM32F4xx_Keil4_V2.1/Psinscore/PSINS.h#L118-L138)）：

| 宏 | 展开 | 物理含义 |
|---|---|---|
| `fPHI(600,600)` | `[600, 600, 600]*MIN` ≈ `[0.1, 0.1, 0.1] rad` | 姿态失准角方差 600 分 ≈ 10° |
| `fXXX(500)` | `[500,500,500]` (m/s)² | 速度误差方差 |
| `fdLLH(10,30)` | `[10/RE, 10/RE, 30]` ≈ `[1.57e-6, 1.57e-6, 30]` | 经纬度 10 m，高度 30 m |
| `fDPH3(5000)` | `[5000,5000,5000]*°/h` ≈ 1.4 °/s²*s | 陀螺零偏驱动（白噪声 Allan σ） |
| `fDPSH3(10.1)` | `10.1°/√h` → 陀螺角随机游走 | 过程噪声 Qt 陀螺项 |
| `fUGPSHZ3(100)` | `100 μg/√Hz` → 加计速度随机游走 | 过程噪声 Qt 加计项 |
| `Rb = 0.6` | fading memory 系数 | 长期无观测时 Rt 指数放大 |

**P 矩阵三明治限幅**：每次更新后 `Pk = clamp(Pk, Pmin, Pmax)`，防止 P 矩阵过膨胀或过收缩。这是工程上的数值稳定策略。

---

## 三、继承链：CKFApp → CSINSGNSS → CSINSTDKF → CKalman

### 3.1 `CKFApp::Init`

```cpp
void CKFApp::Init(const CSINS &sins0, int grade) {
    CSINSGNSS::Init(sins0);     // 调用 CSINSGNSS::Init，完成 F 系变量 & 插值器初始化
    /* 覆盖 P/Pmin/Pmax/Q/R 等 */
}
```

`CSINSGNSS::Init` [PSINS.cpp#L2582-L2603](../../assets/PSINS_STM32F4xx_Keil4_V2.1/Psinscore/PSINS.cpp#L2582-L2603)：

```cpp
void CSINSGNSS::Init(const CSINS &sins0, int grade)
{
    CSINSTDKF::Init(sins0);      // sins = sins0, Pk0=diag(...)
    sins.lever(-lvGNSS);
    sins.pos = sins.posL;        // 杆臂修正后位置
    avpi.Init(sins, kfts);       // AVP 插值器初始化（用于 GNSS 延迟补偿）
    /* grade 0/1/2/... 对应 MEMS / 战术 / 惯导级默认参数 */
}
```

### 3.2 关键数据成员：`CAVPInterp avpi`

`avpi` 是长度 **50 帧的 AVP 环形缓冲**（[PSINS.h#L656-L669](../../assets/PSINS_STM32F4xx_Keil4_V2.1/Psinscore/PSINS.h#L656-L669)）。每个 `Update` 调用后执行：

```cpp
int CSINSGNSS::Update(...)
{
    int res = TDUpdate(pwm,pvm,nn,ts,nSteps);
    sins.lever(lvGNSS);              // 把 IMU 中心位置投到天线中心
    avpi.Push(sins, 1);              // 推入 AVP 历史
    return res;
}
```

**作用**：GPS 数据存在通信延迟（串口 + 解算耗时 ~100ms），不能把 t_k 时刻的 SINS 结果直接和 t_{k-Δ} 的 GPS 位置作差。`avpi.Interp(tpast)` 在历史缓冲中以 t = t_k + tpast（tpast<0 为"回溯"）为节点三线性插值，得到 GNSS 量测产生时刻的**对齐 SINS 姿态/速度/位置**，从而保证 SINS 预测与 GNSS 观测的时间同步。

---

## 四、`SetMeasGNSS`：GNSS 量测注入

[PSINS.cpp#L2696-L2713](../../assets/PSINS_STM32F4xx_Keil4_V2.1/Psinscore/PSINS.cpp#L2696-L2713)

```cpp
void CSINSGNSS::SetMeasGNSS(const CVect3 &posgnss, const CVect3 &vngnss, double yawgnss)
{
    if(!IsZero(posgnss) && avpi.Interp(posGNSSdelay))
    {
        *(CVect3*)&Zk.dd[3] = avpi.pos - posgnss;     // Zk[3:5] = SINS_pos - GPS_pos
        SetMeasFlag(00070);                            // 位置量测有效标志 (bits 3-5)
    }
    if(!IsZero(vngnss) && avpi.Interp(vnGNSSdelay))
    {
        *(CVect3*)&Zk.dd[0] = avpi.vn - vngnss;       // Zk[0:2] = SINS_vn - GPS_vn
        SetMeasFlag(00007);                            // 速度量测有效标志 (bits 0-2)
    }
    if(!IsZero(yawgnss) && avpi.Interp(yawGNSSdelay))
    {
        Zk.dd[6] = -diffYaw(avpi.att.k, yawgnss+dyawGNSS);
        SetMeasFlag(00100);
    }
}
```

### 4.1 延迟参数（静态 vs 动态模式）

| 模式 | `posGNSSdelay / vnGNSSdelay` | 含义 |
|---|---|---|
| 静态 `0x2222` | 未设置 → 默认 0（[PSINS.cpp#L2574](../../assets/PSINS_STM32F4xx_Keil4_V2.1/Psinscore/PSINS.cpp#L2574)） | 不做时间对齐——桌面场景 GPS 到达即使用 |
| 动态 `0x3333` | `-outFrame.GPS_delay`（[main.cpp#L112](../../assets/PSINS_STM32F4xx_Keil4_V2.1/scr/main.cpp#L112)） | 按 MCU 端测得的 GPS 时间滞后回溯插值 |

`GPS_Delay` 计算 [stm32f4xx_it.c#L210](../../assets/PSINS_STM32F4xx_Keil4_V2.1/scr/stm32f4xx_it.c#L210)：`GPS_Delay = MCU_ms_cnt*10 - PPS_cnt`，单位 0.1 ms → `/10000.0` 得到秒。即 "MCU 当前时间 - 上次 GPS PPS 脉冲的 10 kHz 计数值"，代表 PPS 到当前的时间差。

### 4.2 静态模式的伪位置补投

`GPS_Delay/10000 > 10` 即 10 s 内无 GPS PPS → 视为 GPS 丢失。工程上在 `MCU_ms_cnt % 250 == 0`（4 Hz）注入：

```cpp
kf.SetMeasGNSS(gpspos, CVect3(0, 0, 0.01));
```

- `gpspos` 硬编码西安精准楼坐标（若桌面不在该位置，**位置解将漂移到硬编码坐标**）。
- `vn = [0,0,0.01]`：水平速度强制 0（静态），U 方向给 0.01 m/s 是为了**避免观测向量全零导致 `IsZero(vngnss)` 判断跳过**，同时量级极小对结果无影响——这是工程中常见的"保活"小技巧。

---

## 五、`TDUpdate`：时间分布式 Kalman 更新

`CSINSTDKF::TDUpdate` [PSINS.cpp#L2390-L2450](../../assets/PSINS_STM32F4xx_Keil4_V2.1/Psinscore/PSINS.cpp#L2390-L2450)。在 1 个 IMU 周期内把完整 KF 拆成 nStep=5 个**子阶段**轮询执行，每阶段耗时均匀，**避免某次 IMU 周期因 KF 量测更新阻塞而掉中断**。

```cpp
int CSINSTDKF::TDUpdate(...)
{
    sins.Update(pwm, pvm, nSamples, ts);        // Step 1：纯 SINS 机械编排积分
    if(++curOutStep>=maxOutStep) RTOutput();
    Feedback(nq, sins.nts);                      // Step 2：状态反馈（修正 sins）

    tdts += sins.nts; kftk=sins.tk;
    for(int i=0; i<nStep; i++)                   // Step 3：nStep 次，走 iter 状态机
    {
        if(iter==-2) { /* SetFt + SetMeas + SetHk  */            iter++; }
        else if(iter==-1) { /* Fk = I+Ft*ts, Qk = Qt*ts, Xk=FkXk, tdts=0 */ iter++; }
        else if(iter<nq) { /* row-by-row Fk*Pk           */ iter++; }         // nq=19 步
        else if(iter<2*nq) { /* row-by-row Fk*Pk*Fk^T + Qk */ iter++; }       // 再 19 步
        else if(iter<2*(nq+nr)) { /* sequential MeasUpdate */  iter++; }       // nr=6 步
        else { iter = -2; }
    }
}
```

**5 步分配**（nStep=5）：每调用 1 次 `Update(...,nStep=5)`，状态机向前推进 5 步。19+19+6=44 个"行级"更新，大约 9 个 IMU 周期（90 ms）跑完一次完整的 KF 循环，观测更新约 11 Hz 有效。

> 这是严老师针对 STM32F4 168 MHz 主频做的经典工程技巧：把重计算摊薄到多个 IMU 周期，**保证实时性优先**。代价是观测不是同步更新（延迟约 0.1 s），桌面静态场景可忽略。

---

## 六、`SetFt` / `SetHk` / `Feedback`：ESKF 三件套

### 6.1 连续状态转移矩阵 Ft

[PSINS.cpp#L2621-L2649](../../assets/PSINS_STM32F4xx_Keil4_V2.1/Psinscore/PSINS.cpp#L2621-L2649)：

```cpp
void CSINSGNSS::SetFt(int nnq)
{
    sins.etm();   // 计算 Maa/Mav/Map, Mva/Mvv/Mvp, Mpv/Mpp (误差模型矩阵)
    Ft.SetMat3(0, 0, sins.Maa);     Ft.SetMat3(0, 3, sins.Mav);
    Ft.SetMat3(0, 6, sins.Map);     Ft.SetMat3(0, 9, -sins.Cnb);
    Ft.SetMat3(3, 0, sins.Mva);     Ft.SetMat3(3, 3, sins.Mvv);
    Ft.SetMat3(3, 6, sins.Mvp);     Ft.SetMat3(3,12,  sins.Cnb);
    Ft.SetMat3(6, 3, sins.Mpv);     Ft.SetMat3(6, 6, sins.Mpp);
    Ft.SetDiagVect3( 9, 9, sins._betaGyro);      // 一阶马尔可夫陀螺
    Ft.SetDiagVect3(12,12, sins._betaAcc);       // 一阶马尔可夫加计
}
```

这是 PSINS 标准 ENU 系 15 维误差方程。对比 MATLAB `ins_15state_err.m` 对应项：

$$
\begin{bmatrix}
\delta\dot\phi \\
\delta\dot v^n \\
\delta\dot p \\
\dot e_b \\
\dot d_b \\
\end{bmatrix}
=
\begin{bmatrix}
M_{aa} & M_{av} & M_{ap} & -C_b^n & 0 \\
M_{va} & M_{vv} & M_{vp} & 0 & C_b^n \\
0 & M_{pv} & M_{pp} & 0 & 0 \\
0 & 0 & 0 & -\beta_g I & 0 \\
0 & 0 & 0 & 0 & -\beta_a I \\
\end{bmatrix}
\begin{bmatrix}
\delta\phi \\ \delta v^n \\ \delta p \\ e_b \\ d_b
\end{bmatrix}
+ w
$$

（15-17 杆臂、18 dt 状态在 Ft 中未显式建模，为零漂移随机游走，只在 Hk 中体现）。

### 6.2 观测矩阵 Hk

[PSINS.cpp#L2651-L2663](../../assets/PSINS_STM32F4xx_Keil4_V2.1/Psinscore/PSINS.cpp#L2651-L2663)：

```cpp
void CSINSGNSS::SetHk(int nnq)
{
    if(nnq>=18) {     // 杆臂状态存在（本工程 nnq=19 满足）
        CMat3 CW = sins.Cnb * askew(sins.web);
        Hk.SetMat3(0, 15, -CW);                    // δvn 对 δl 的导数
        Hk.SetMat3(3, 15, -Mpv*sins.Cnb);          // δpos 对 δl 的导数
    }
    if(nnq>=19) {
        CVect3 MV = sins.Mpv*sins.vn;
        Hk.SetClmVect3(0, 18, -sins.an);           // δvn 对 dt 导数 = -a^n
        Hk.SetClmVect3(3, 18, -MV);                // δpos 对 dt 导数 = -Mpv v^n
    }
}
```

基础观测（默认非 0 块）由 `CSINSGNSS::SetMeas` 或 `Zk = pred - obs` 隐式给出为 $H = [0\ I_{6}\ 0\ \dots]$——因为位置和速度误差直接就是状态 3:8，无须映射（对 phi/eb/db 都为 0）。只有杆臂 15:17 与时间误差 18 才需要写 Hk。

### 6.3 反馈 Feedback

[PSINS.cpp#L2665-L2695](../../assets/PSINS_STM32F4xx_Keil4_V2.1/Psinscore/PSINS.cpp#L2665-L2695)：

```cpp
void CSINSGNSS::Feedback(int nnq, double fbts)
{
    CKalman::Feedback(nq, fbts);
    sins.qnb -= *(CVect3*)&FBXk.dd[0];   // 失准角→四元数小角度修正
    sins.vn  -= *(CVect3*)&FBXk.dd[ 3];   // 速度减误差
    sins.pos -= *(CVect3*)&FBXk.dd[ 6];   // 位置减误差
    sins.eb  += *(CVect3*)&FBXk.dd[ 9];   // 陀螺加估计零偏
    sins.db  += *(CVect3*)&FBXk.dd[12];   // 加计加估计零偏
    if(nnq>=18) lvGNSS       += *(CVect3*)&FBXk.dd[15];
    if(nnq>=19) dtGNSSdelay  += FBXk.dd[18];
}
```

ESKF 的"反馈式"模式：状态误差每周期估计后**加到标称状态 sins**，然后把 Xk 向量重置为 0（由 `CKalman::Feedback` 做），再做 P 矩阵的 Joseph 或简单补偿。这是 PSINS 的标准做法。

---

## 七、输出：`AVPUartOut(kf)` → 串口帧

[KFApp.cpp#L23-L37](../../assets/PSINS_STM32F4xx_Keil4_V2.1/Psinscore/KFApp.cpp#L23-L37):

```cpp
void AVPUartOut(const CVect3 &att, const CVect3 &vn, const CVect3 &pos)
{
    outFrame.Att[0] = att.i/DEG; outFrame.Att[1] = att.j/DEG;
    outFrame.Att[2] = CC180C360(att.k)/DEG;        // yaw: -180~180 → 0~360

    outFrame.Vn[0] = vn.i; outFrame.Vn[1] = vn.j; outFrame.Vn[2] = vn.k;

    int deg;
    deg = (int)(pos.j/DEG);
    outFrame.Pos[0] = deg;       outFrame.Pos[1] = pos.j/DEG - deg;   // 经度 度+小数
    deg = (int)(pos.i/DEG);
    outFrame.Pos[2] = deg;       outFrame.Pos[3] = pos.i/DEG - deg;   // 纬度 度+小数
    outFrame.Pos[4] = pos.k;                                        // 高度 m
}
```

串口打包、DMA 发送细节见 [05_串口输出帧.md](05_串口输出帧.md)。

---

## 八、静态模式的已知陷阱与改进方向

### 8.1 硬编码坐标的误导

```cpp
CVect3 gpspos = LLH(34.228022, 108.880422, 422.0);
if(GPS_Delay>10s && 250ms一次) kf.SetMeasGNSS(gpspos, [0,0,0.01]);
```

- 若实际测试位置与硬编码坐标不同，**滤波器会把位置强行"拉回"到西安精准楼**——这在桌面静态调试中会产生虚假的 vn 估计（因为 P 修正后 sins.pos 被反馈修正，SINS 下一周期的 vn 会补偿性变化）。
- 建议：把 `gpspos` 改成"首次接收到的 GPS 坐标"或直接从配置区读取。

### 8.2 `eb`/`db` 的主循环 vs 卡尔曼估计

```cpp
// main.cpp 全局
eb = CVect3(-4.0,1.3,0.0)*DPS;   db = O31;
// main循环中：
wm = (Gyro*DPS - eb)*TS;  vm = (Accel*G0 - db)*TS;
```

注意这里 $e_b, d_b$ **先在主循环中扣了一次**（固定经验零偏），KF 状态 9:11/12:14 估计的是**残余零偏**。若传感器个体差异大（-4°/s x 轴零偏不成立），残余过大导致 Q/ARW 噪声模型失配——建议先做静态 6 位置标定或在 `Feedback` 收敛后把估计值回填到全局 `eb/db`。

### 8.3 nStep=5 摊薄不支持 1 Hz GPS 严格同步

如前所述，完整 KF 循环 ~90 ms，1 Hz GPS 在随机时刻到达，观测到被使用的延迟可能达到 0.1 s 量级。静态不敏感，若动基需同步可减小 `nSteps=1`（但抖动增大）。

### 8.4 Qt 中 eb/db 是白噪声，无 Markov

`CKFApp::Qt.Set2(..., fOOO, fOO6, fOOO, 0.0)` 中 eb/db 过程噪声对应 `fOOO, fOOO` 即 **Qt 的 9:14 块全 0**。只有 Markov 开启（`MarkovGyro/MarkovAcc`，被注释在 grade=0 分支）才能体现 β_g, β_a 的 1 阶 GM 模型。**默认版本 eb/db 完全无过程噪声驱动**，仅依靠初始 Pk0 中的协方差——长时间运行后 eb/db 的 P 会塌到 Pmin，估计收敛但无法跟踪慢漂。需长时间静态精度建议开启 Markov。

---

## 九、19 状态量快速映射

| 索引 | 数学名 | 代码访问 | ENU 含义 |
|---|---|---|---|
| 0:2 | $\delta\phi$ | `(CVect3*)&Xk.dd[0]` | φ_E, φ_N, φ_U (rad) |
| 3:5 | $\delta v^n$ | `(CVect3*)&Xk.dd[3]` | δv_E, δv_N, δv_U (m/s) |
| 6:8 | $\delta p$ | `(CVect3*)&Xk.dd[6]` | δlon, δlat (rad), δh (m) |
| 9:11 | $e_b$ | `(CVect3*)&Xk.dd[9]` | δeb_x, δeb_y, δeb_z (rad/s) |
| 12:14 | $d_b$ | `(CVect3*)&Xk.dd[12]` | δdb_x, δdb_y, δdb_z (m/s²) |
| 15:17 | $l_{\text{GNSS}}$ | `(CVect3*)&Xk.dd[15]` | 杆臂 body 系 (m) |
| 18 | $dt$ | `Xk.dd[18]` | GPS 时间滞后 (s) |

观测 Zk（6 维）：

| 索引 | 代码访问 | 含义 |
|---|---|---|
| 0:2 | `(CVect3*)&Zk.dd[0]` | vn_SINS − vn_GPS (m/s) |
| 3:5 | `(CVect3*)&Zk.dd[3]` | pos_SINS − pos_GPS ([rad,rad,m]) |

---

## 参考资料

- [Sola, J. (2017). *Quaternion Kinematics for the Error-State Kalman Filter.*](https://arxiv.org/abs/1711.02508) — 19 维 ESKF 误差状态定义、F_t 状态转移矩阵、H_k 观测矩阵推导
- [严恭敏教授 PSINS 官网](http://www.psins.org.cn/) — CKFApp 类定义、SetMeasGNSS 接口、Q/R 矩阵默认值来源
- [严恭敏, 严热宝. *捷联惯导算法与组合导航原理.* 西北工业大学出版社](https://book.douban.com/subject/34759212/) — ESKF 在 SINS/GNSS 组合中的完整理论推导（教材）
- [Groves, P. D. (2013). *Principles of GNSS, Inertial, and Multisensor Integrated Navigation Systems.* Artech House.](https://www.artechhouse.com/principles-of-gnss-inertial-and-multisensor-integrated-navigation-systems-2nd-edition) — GNSS/SINS 松组合、紧组合的工程分类与本工程"松组合"定位
- [PSINS MATLAB 版 CKFApp 源码对照](https://github.com/yanliang-zhu/PSINS-MATLAB) — 本嵌入式工程 19 维 ESKF 与 MATLAB 版的 1:1 对照

---

## 导航

- 上一篇：[07_Mahony模式详解.md](07_Mahony模式详解.md)
- 下一篇：[09_SINS_GNSS动态组合.md](09_SINS_GNSS动态组合.md)
- 回到总览：[00_总览与架构.md](00_总览与架构.md)
