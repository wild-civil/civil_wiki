# 12 CKalman 核心：工程卡尔曼的"最后一公里"

> 08/09 篇讲了"组合怎么用"，本篇讲卡尔曼类的**工程实现本体**——教科书 KF 到可跑 168MHz MCU 的差距就在这几百行里。
> 代码：`CKalman` 基类与 `CSINSTDKF` 派生 [PSINS.cpp#L2149 L2560](../../assets/PSINS_STM32F4xx_Keil4_V2.1/Psinscore/PSINS.cpp#L2149 L2560)。

   

## 〇、先立骨架：教科书 KF 五个式子 → 工程 9 个机制

| 教材 KF | 本工程实现函数 |
|   |   |
| Φ 离散化 | `Fk = I + Ft·Δt` |
| P⁻ = ΦPΦᵀ + Q | `RowMul + RowMulT` 逐行计算（省内存、可打断） |
| S、K、X⁺、P⁺ | `CSINSTDKF::MeasUpdate` 顺序量测（**一个量测一维**处理） |

工程多出来的机制（教材不讲的 9 个）：

1. **量测有效标志** `measflag` / 屏蔽 `measmask`
2. **量测停用计数** `measstop` / **丢失计数** `measlost` / R 停用 `Rstop`
3. **时间分布式状态机** `iter`（08 篇的 nStep=5 摊薄）
4. **顺序量测**（每维分别更新，省矩阵求逆）
5. **新息一致性自适应 R** `RAdaptive`
6. **P/Z 衰减** `RPkFading` / `RtFading`
7. **状态/协方差限幅** `XPConstrain`（Pmin/Pmax/Pset）
8. **反馈式 ESKF** `Feedback`（FBTau 限幅、X 清零）
9. **计算占空比统计** `SetCalcuBurden`（选 100）

   

## 一、时间更新：`CKalman::TimeUpdate`

[PSINS.cpp#L2149 L2162](../../assets/PSINS_STM32F4xx_Keil4_V2.1/Psinscore/PSINS.cpp#L2149 L2162)：

```cpp
kftk += kfts;  kfcount++;
SetFt(nq);
Fk = ++(Ft*kfts);      // Fk = I + Ft*Δt   （C++ 重载："+=" 前面再自增 = I + F·Δt）
Xk = Fk * Xk;          // 状态预测
Pk = Fk*Pk*(~Fk);  Pk += Qt*kfts;   // P⁻ = ΦPΦᵀ + Q·Δt
if(fback) Feedback(nq, kfts);       // ESKF：误差反馈回 sins，X 清零
for(int i=0; i<nr; i++) {           // 计时器维护
    measlost.dd[i] += kfts;         //   丢失时长++
    if(measstop.dd[i]>0.0) measstop.dd[i] = kfts;  // 停用倒计时
}
```

> `Fk*Pk*(~Fk)` 是 O(n³) 的矩乘，STM32F4 上 19 维≈6.9k 次乘加。**这就是为什么 TS 周期里要拆 nStep**（见第三节状态机）——把一个大矩乘切到 4 个 IMU 周期里做。

**Feedback 细节** [L2285 L2310](../../assets/PSINS_STM32F4xx_Keil4_V2.1/Psinscore/PSINS.cpp#L2285 L2310)：

```cpp
if(*pTau<INFp5) {            // 该状态启用"缓反馈"
    if(|x|>FBOne1) pXk = x;            // 误差太大：直接全量回馈
    else { afa = fbts<tau ? fbts/tau : 1;   // 按时间常数分摊回馈
           pXk = x*afa; 限幅±FBOne; }
    p  = pXk;  pTotal += pXk;          // X 清零 + 累计
} else pXk = 0;
```

  **FBTau** 08 里 `Set(fXX9(0.1), fXX6(1.0), fINF3, INF)`：姿态/速度反馈时间常数 0.1 s（快速校正），零偏 1.0 s（慢反馈防冲过头），杆臂/时间误差 `INF`（禁用缓反馈，每次全量）。
  反馈完 `Xk` 被清（`p  = pXk`，pXk 是拷贝量），所以 **ESKF 的误差态在每周期末归零**，下一周期从 0 再估——这是"反馈式"的精髓。

   

## 二、顺序量测：`CSINSTDKF::MeasUpdate`

[PSINS.cpp#L2499 L2509](../../assets/PSINS_STM32F4xx_Keil4_V2.1/Psinscore/PSINS.cpp#L2499 L2509)：

```cpp
Pxz = Pk*(~Hi);
Pz0 = (Hi*Pxz)(0,0);
innovation = Zi (Hi*Xk)(0,0);
Pzz = Pz0 + Ri;
Kk  = Pxz*(1.0/Pzz);
Xk += Kk*innovation;
Pk  = Kk*(~Pxz);
```

**为什么行得通**：卡尔曼量测更新对**互不相关**的观测可拆成若干维串行做——每用一维更新 (X,P)，再拿新的 (X,P) 处理下一维。好处：① 不用对 R 求逆（只除标量 Pzz）；② 工程上"哪几维在这次有效"可以逐位开关（配合 measflag）。

二维块状更新在 [08 篇 6.2](08_SINS_GNSS静态组合.md) 的 `SetHk` 只是把 H 填好，真正顺序更新在这。

   

## 三、时间分布式状态机：`TDUpdate` 的 iter

[PSINS.cpp#L2390 L2490](../../assets/PSINS_STM32F4xx_Keil4_V2.1/Psinscore/PSINS.cpp#L2390 L2490)（08 篇第三节有全景图，这里补代码语义）：

```
iter= 2      构造量测（SetFt/SetMeas/SetHk）一次         [每 N 个 IMU 周期 1 次]
iter= 1      离散化：Fk=I+F·tdts, Qk=Q·tdts, X=F·X      [1 步]
iter∈[0,nq)       Pk1 = Fk*Pk 第 iter 行               [nq 步]
iter∈[nq,2nq)     Pk  = Pk1*Fkᵀ+Qk 第 iter 行          [nq 步]
iter∈[2nq,2(nq+nr)) 顺序量测（逐维，2 小步/维）        [2·nr 步]
iter=2(nq+nr)     XPConstrain + symmetry(Pk)           [1 步]
iter 回到  2                                            （循环）
```

`maxStep = 2*(nq+nr)+3`（[L2377](../../assets/PSINS_STM32F4xx_Keil4_V2.1/Psinscore/PSINS.cpp#L2377)）即一轮完整 KF 的最多“子步”数。`nStep`（main 里传 5）是**每 IMU 周期推进的步数**：5 × 9 ≈ 44+ 步跑完一轮（2·19+2·6+3=41）。

**关键工程点**（[L2410 L2480](../../assets/PSINS_STM32F4xx_Keil4_V2.1/Psinscore/PSINS.cpp#L2410 L2480)）：

  每次到 `iter== 2` 前会把 `meanfn`（多周期平均比力）存进 `sins.fn` 再 `SetFt/SetHk`——**用平均比力算状态转移**，消掉子周期抖动；
  顺序量测分支里 `iter%2==0` 算增益（Hi/Pxz/K），`iter%2==1` 才真正 `Xk+=K·r, Pk =K·Pxz`——**把"算"和"写"分到两个子步**，确保一维的量测若被拒绝（adptOKi=0）不会污染 P；
  `flag&measmask` 有效才进；无效则 `nStep++`（把这一小步"让"给下一周期，不空转）。

   

## 四、四个"标志/计时"机制（新手最容易看懵的地方）

| 变量 | 物理含义 | 谁置它 | 何时检查 |
|   |   |   |   |
| `measflag` | **本次哪些量测有效**（位 0 5=速度/位置/航向各维） | `SetMeasFlag(bit)`（08 篇 `SetMeasGNSS` 里 00057/00070） | 每维更新前 `measflag&measmask` |
| `measmask` | **能用的量测掩码**（屏蔽掉某些量测通道） | `SetMeasMask(type, mask)` | 同上（0=temporarily 屏蔽） |
| `measstop` | **某量测"停用倒计时"**（到达后恢复使用，>EPS 表示期间不可用） | `SetMeasStop(stop, bit)` | 更新时 `measstop.dd[row]<EPS` 才用 |
| `Rstop` | **R 自适应停用倒计时**（期间 R 固定不调） | `SetRadptStop` | `Rstop.dd[row]<EPS` 才 `RAdaptive` |
| `measlost` | 各量测**连续丢失时长**（累计，用来 FDI / 判断观测是否失效） | 时间更新累加 | 量测成功后清零 |

> 例：08 静态模式 GPS 丢了 >10s，`SetMeasGNSS(gpspos, v)` 照样注入→ `measflag` 仍置位→但滤波器已按 `RAdaptive` 放大 R 秒弃——这靠的是 R 自适应，不是 measflag。

   

## 五、三个"数值稳健"机制

### 5.1 RAdaptive（新息一致性自校准）

[L2217 L2226](../../assets/PSINS_STM32F4xx_Keil4_V2.1/Psinscore/PSINS.cpp#L2217 L2226)：

```cpp
double rr = r*r   Pr;                       // r² 比预期 Pz0 大了多少
if(rr < Rmin) rr = Rmin;
if(rr > Rmax) { Rt=Rmax; Rmaxcount++; }     // 连续爆表 → 判定量测坏
else Rt = (1 beta)*Rt + beta*rr;            // 指数加权更新 Rt
Rbeta = Rbeta/(Rbeta+Rb);                    // beta 随时间衰减（Rb=0.6 fading）
adptOK = (Rmaxcount==0 || Rmaxcount>Rmaxcount0);   // 爆表期间不采纳该量测
```

即：**新息若长期大于模型预期（自由度 1 时应 ~Pz0），说明 R 给小了——把 R 调大**，等于"自动不相信坏观测"。（08 篇 2.2 的 `Rb=0.6`、`Rmax/Rmin=100/0.01` 都在这里被消费。）

### 5.2 RPkFading（Z 滤波 + P 行衰减）与 RtFading

  `Zfd` 对新息做一阶低通（`Zfd = (1 zfdafa)·Zfd + zfdafa·Z`），超阈值触发 `DVMDVafa(P)` 按衰减系数整体缩放 P 的行/列——**防 P 膨胀到不可控**；
  `RtFading` 让 `Rt/rts` 中 `rts` 随时间增大→等效 R 变小→**长时间没有量测时宽松量测信任**，避免滤波器"冷却"后第一次量测把解震飞。

### 5.3 XPConstrain（X/P 限幅 + Pset）

[L2235 L2283](../../assets/PSINS_STM32F4xx_Keil4_V2.1/Psinscore/PSINS.cpp#L2235 L2283)（08 篇 2.2 已提三明治，这里补细节）：

  `Xk` 各维 ±`Xmax` 限幅；
  `P` 对角元 clamp 到 `[Pmin,Pmax]`；**若超 Pmax**，不是直接截断，而是按 `sqrt(Pmax/P)` 缩放整行和整列再回写（保证对称和半正定，20200303 修订注）；
  `Pset` 是"目标协方差"：若 P 比它小就设到它（防止过度自信）；用过一次后置  1 不再重复。

   

## 六、计算占空比：`SetCalcuBurden(100, 1)`

08 篇 2.1 里看到 `SetCalcuBurden(100, 1)`：记录一次 KF 完整循环占用的"等效 MCU 时间片"，`dt/计数` 统计实际耗时。严老师在 F4 上用它是为了**实测滤波到底占了多少算力**，便于决定 nStep。

> 结合 08 篇主循环 `kf.Update(...,5)`：static 模式一轮完整 KF ≈ 90ms（约 11Hz 量测更新率），这在 MK 篇已被时间分布式化解——你的 2.5g VTOL 若要用 SINS/GNSS，nStep 和 burden 是第一道要重新标定的闸门。

   

## 参考资料

  严恭敏, 严热宝. *捷联惯导算法与组合导航原理.* 西北工业大学出版社 —— 组合导航滤波工程实现一章
  [PSINS 官网](http://www.psins.org.cn/)——`CKalman/CSINSTDKF` 原始实现
  本 wiki：[08_SINS_GNSS静态组合.md](08_SINS_GNSS静态组合.md)（`TDUpdate` 应用上下文）、[03 卡尔曼滤波基础](../../03_组合导航篇/10_卡尔曼滤波基础.md)（五矩阵物理意义与 Joseph 形式）、[10_机械编排与惯导解算.md](10_机械编排与惯导解算.md)（`sins.Update` 是状态机前的 Step1）

---

## 导航
- 上一篇：[11_算法附录_旋转矢量与机械编排.md](11_算法附录_旋转矢量与机械编排.md)
- 下一篇：[13_PSINS基础库与初始对准.md](13_PSINS基础库与初始对准.md)
- 回到总览：[00_总览与架构.md](00_总览与架构.md)
