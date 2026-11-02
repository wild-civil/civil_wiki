# 13 PSINS 基础数学库与初始对准

> 07/10/11 篇散用了一堆自由函数（`rv2q/q2att/m2att/a2qua/askew`），本篇把它们集中成**速查表 + 推导**，并补上"开机怎么从静止得到初始姿态"的正交对准流程。
> 代码：基础库 [PSINS.cpp#L400-L950](../../assets/PSINS_STM32F4xx_Keil4_V2.1/Psinscore/PSINS.cpp#L400-L950)（本工程不用的部分已省略）。

---

## 一、姿态表达互转速查表

`PSINS` 全套姿态工具，输入约定：欧拉角 `att=[pitch; roll; yaw]`（ENU：p→i, r→j, y→k 的 ZYX 右手系），四元数 `qnb=[q0,q1,q2,q3]=[w;x;y;z]`，DCM `Cnb`（body→nav）。

| 函数 | 输入 → 输出 | 代码位置 | 用途 |
|---|---|---|---|
| `a2qua(att)` | 欧拉角 → 四元数 | [L840-L856](../../assets/PSINS_STM32F4xx_Keil4_V2.1/Psinscore/PSINS.cpp#L840-L856) | 初始姿态、`SetYaw` 转向 |
| `a2mat(att)` | 欧拉角 → DCM | [L858-L868](../../assets/PSINS_STM32F4xx_Keil4_V2.1/Psinscore/PSINS.cpp#L858-L868) | 直接看 DCM 分量 |
| `q2mat(qnb)` | 四元数 → DCM | [L920-L931](../../assets/PSINS_STM32F4xx_Keil4_V2.1/Psinscore/PSINS.cpp#L920-L931) | `Cnb = q2mat(qnb)` 主路径 |
| `m2att(Cnb)` | DCM → 欧拉角 | [L870-L877](../../assets/PSINS_STM32F4xx_Keil4_V2.1/Psinscore/PSINS.cpp#L870-L877) | 输出 att |
| `q2att(qnb)` | 四元数 → 欧拉角 | [L907-L918](../../assets/PSINS_STM32F4xx_Keil4_V2.1/Psinscore/PSINS.cpp#L907-L918) | 07 篇 Mahony 输出 |
| `m2qua(Cnb)` | DCM → 四元数 | [L879-L905](../../assets/PSINS_STM32F4xx_Keil4_V2.1/Psinscore/PSINS.cpp#L879-L905) | 可靠性校验 |
| `rv2q(rv)` | 旋转矢量 → 四元数 | [L408-L429](../../assets/PSINS_STM32F4xx_Keil4_V2.1/Psinscore/PSINS.cpp#L408-L429) | 机械编排（11 篇详解） |
| `askew(v)` | 向量 → 反对称阵 | [L431-L436](../../assets/PSINS_STM32F4xx_Keil4_V2.1/Psinscore/PSINS.cpp#L431-L436) | 叉积的矩阵形式 |
| `adj/inv` | 3×3 伴随/求逆 | [L933-...](../../assets/PSINS_STM32F4xx_Keil4_V2.1/Psinscore/PSINS.cpp#L933) | 矩阵工具 |

### 关键推导一：`a2qua`（欧拉角 → 四元数，ZYX 顺序）

代码半角展开：

```cpp
pitch/=2, roll/=2, yaw/=2;
q0 = cp·cr·cy − sp·sr·sy;
q1 = sp·cr·cy − cp·sr·sy;
q2 = cp·sr·cy + sp·cr·sy;
q3 = cp·cr·sy + sp·sr·cy;
```

对应 ZYX 组合（先 yaw 绕 z，再 roll 绕 y，再 pitch 绕 x，ENU 下 x=东=机体纵轴）：

$$
q = q_{\text{pitch}}\otimes q_{\text{roll}}\otimes q_{\text{yaw}},\qquad q_{\text{roll}}\otimes q_{\text{yaw}} = \text{上式}
$$

> 这是 07 篇 **`q2att` 的逆**——`a2qua(att)` 和 `q2att(qnb)` 互为反函数（数值上）。

### 关键推导二：`m2att`（DCM → 欧拉角，用 asin/atan2 取角）

```cpp
att.i = asinEx( Cnb.e21 );                  // pitch = asin(2(q2q3+q0q1))
att.j = atan2Ex(-Cnb.e20, Cnb.e22);         // roll  = atan2(-2(q2q3−q0q2), q0²−q1²−q2²+q3²)
att.k = atan2Ex(-Cnb.e01, Cnb.e11);         // yaw   = atan2(-2(q1q3−q0q2), q0²−q1²+q2²−q3²)
```

三个角度里只有 **pitch 用 asin**（范围 ±90°，天然限制奇异），**roll/yaw 用 atan2**（±180° 四象限正确）。`asinEx/atan2Ex` 是加了数值保护的版本。这就是为什么 07 篇 Mahony 输出用 `q2att` 能稳定给 `[roll,pitch,yaw]`。

### 关键推导三：`q2mat`/`m2qua`（互转，四元数→DCM→四元数）

`q2mat` 是四元数乘法展开的 DCM（L920-L931 逐项）；`m2qua` 用 Shepperd 法避免大分量根号精度丢失——两者互逆，用于自检。

---

## 二、初始对准（开机怎么站起来）

### 2.1 数学本质：用两个不共线参考向量把 qnb 确定下来

姿态对准只需要**两个不共线的已知向量**（在 nav 系已知、在 body 系测得）：

1. **重力 gⁿ**（nav 系：`[0,0,-g0]`；body 系测得：比力 fb，静止时 fb = -gᵇ）→ 定 **水平**（pitch/roll）；
2. **磁/航向向量**（nav 系：磁北；body 系：磁力计，或 GPS 航迹方向）→ 定 **yaw**。

### 2.2 代码怎么"直接用"：`a2qua` 一行完成粗对准

[main.cpp#L54-L125](../../assets/PSINS_STM32F4xx_Keil4_V2.1/scr/main.cpp#L54-L125) 静态模式 `CKFApp kf(TS); kf.Init(CSINS(O31, gpsvn, gpspos))` → `CSINS::Init`→ `a2qua(att0)`——**att0=O31 就是假设"初始水平朝北"**。

动态模式（09 篇）`yawinit` 用 GPS 速度方向得到初始 yaw，再 `a2qua(0,0,yaw)` 重构初始 qnb。真正的"物理对准"（用两段时间积分消除比力中的重力）由 **[粗对准类 `CAligntf`/`Alignsb`](../../assets/PSINS_STM32F4xx_Keil4_V2.1/Psinscore/PSINS.cpp#L4034)** 承担——本工程 SINS 模式没走它，而是直接"假设静止且水平"，由 EKF 在头几秒把残余失准角收敛掉（P0 里姿态块 600 分≈10° 就是预留给这个误差的）。

### 2.3 `CSINSTDKF::SetYaw`（动态对准的转向修正）

[L2523-L2537](../../assets/PSINS_STM32F4xx_Keil4_V2.1/Psinscore/PSINS.cpp#L2523-L2537)：

```cpp
CQuat qnn = a2qua(0, 0, diffYaw(yaw, sins.att.k));  // 需要转的航向差
sins.qnb = qnn*sins.qnb;   sins.Cnb = q2mat(sins.qnb); sins.att = m2att(sins.Cnb);
sins.vn  = qnn*sins.vn;                                // 速度也随坐标准转
*(CVect3*)&Xk.dd[statephi] = qnn * Xk[statephi];       // 误差态同步旋转
*(CVect3*)&Xk.dd[statedvn] = qnn * Xk[statedvn];
Pk = diag(diag(Pk));     // 旋转后只保留对角——相关性清零
TDReset();               // 状态机从 -2 重来
```

即：一旦获得外部航向（GPS 航迹），把整个姿态/速度/误差状态绕 z 转过去，并**重置 P 相关性**再继续滤波——工程上的"人对准"就是这两步。

---

## 三、给初学者的"开机十分钟"路径

1. 看 [07_Mahony模式详解.md](07_Mahony模式详解.md)（第一个 AHRS 跑起来）→ 用到了 `q2att`、`rv2q`；
2. 看 [10_机械编排与惯导解算.md](10_机械编排与惯导解算.md)（SINS 怎么推）→ 用到了 `q2mat`、`m2att`、`a2qua`；
3. 回本篇速查表——需要哪个函数回来看一眼推导与边界；
4. 组合导航再回 [08](08_SINS_GNSS静态组合.md)/[09](09_SINS_GNSS动态组合.md)/[12](12_CKalman核心与工程机制.md)（那里用到 `askew`、`diffYaw`、`SetYaw`）。

---

## 参考资料

- 严恭敏, 严热宝. *捷联惯导算法与组合导航原理.* 西北工业大学出版社 —— 姿态描述与正交对准章节
- [PSINS 官网](http://www.psins.org.cn/)——基础函数原始实现
- 本 wiki：[11_算法附录_旋转矢量与机械编排.md](11_算法附录_旋转矢量与机械编排.md)（rv2q 详细推导）、[10_机械编排与惯导解算.md](10_机械编排与惯导解算.md)、[07_Mahony模式详解.md](07_Mahony模式详解.md)


---

## 导航
- 上一篇：[12_CKalman核心与工程机制.md](12_CKalman核心与工程机制.md)
- 下一篇：[14_H743移植指南.md](14_H743移植指南.md)
- 回到总览：[00_总览与架构.md](00_总览与架构.md)
