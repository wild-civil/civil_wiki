# ENU 坐标卡 + insupdate 逐行 + eth 字典

> 配套：`psins260314/base/base1/{insupdate,ethupdate,vn2dpos,insinit}.m`、`base/base2/etm.m`
> 用途：读 PSINS 源码前的坐标约定速查；机械编排每步吃什么、给什么；第 3 周误差模型（与 etm.m 的 F 矩阵同源）。

## 1. ENU 坐标卡（最重要，先钉死再读码）

**PSINS 内部导航系 = 东-北-天（E-N-U），vn=[vE; vN; vU]，pos=[Lat; Lon; H]。**

| 量 | 我们第 1–2 周（NED） | PSINS（ENU） |
|---|---|---|
| 速度 | [vN, vE, vD] | **[vE, vN, vU]** |
| ω_ie^n | [ωcosL, 0, −ωsinL] | [0, ωcosL, +ωsinL] |
| ω_en^n | [vE/R, −vN/R, −vE tanL/R] | **[−vN/RMh, vE/RNh, vE tanL/RNh]** |
| 重力 g^n | [0, 0, +g] | **[0, 0, −g]** |
| 比力 f^n（静止） | [0, 0, −g] | **[0, 0, +g]** |
| 高度 | h = −∫vD | h = +∫vU |
| 姿态误差记号 | φ(俯仰/横滚/航向) | 同记号，分量按 (E,N,U) |

**三条代码铁证**（都在仓库里）：
1. `vn2dpos.m: dpos=[vn(2)/RMh; vn(1)/clRNh; vn(3)]`：纬度率由 vn(2) 驱动 → vN 是第 2 个分量。
2. `ethupdate.m: wnie=[0; ωcosL; ωsinL]`：第 1 分量恒 0 = 东；gn=[0;0;−g] = z 朝上。
3. `insupdate.m: ins.Mpv=[0,1/RMh,0; 1/clRNh,0,0; 0,0,1]`：行序 (Lat, Lon, H)，与 vn 顺序配套。

**口诀**：x=东、y=北、z=天；速度先 E 后 N；z 轴方向和第 1 周完全反着。
**陷阱提醒**：读任何 PSINS 函数，先确认 `vn(1)` 是东向——否则 gcc、Mpv、etm 全对不上。

## 2. eth 字典（ethupdate 每拍刷新的地球参数）

| 字段 | 内容（ENU） | 一句人话 |
|---|---|---|
| `sl/cl/tl/sl2` | sinL, cosL, tanL, sin²L | 极区保护：`|cl|<1e-7 → 1e-7`（分裂经度防除零） |
| `RNh` | R_N + h（卯酉圈） | 东西向曲率半径 |
| `RMh` | R_M + h（子午圈） | 南北向曲率半径 |
| `clRNh` | cosL·(R_N+h) | 纬圈半径（东移时用） |
| `wnie` | [0, ωcosL, ωsinL] | 地球自转投影 |
| `wnen` | [−vN/RMh, vE/RNh, vE tanL/RNh] | 运输率（参考系随载体移动的转动） |
| `wnin` | = wnie+wnen | n 相对 i；姿态更新/中点旋转用 |
| **`wnien`** | **= wnie+wnin = 2ω_ie+ω_en** | **比力方程 (2ωie+ωen) 的打包** |
| `g` | 正常重力（随 L,h） | WGS84 椭球模型 |
| `gn` | [0,0,−g] | ENU 下重力向下 |
| `gcc` | gn − wnien×vn | 重力+哥氏+牵连合并项 |

**洞察**：`wnien = wnie+wnin = 2wnie+wnen`，所以速度更新一行 `an=rotv(-wnin·ts/2, fn)+gcc` 就写完了整个比力方程。

## 3. insupdate.m 逐行（psins260314/base1/insupdate.m）

执行顺序：**锥桨补偿 → 标定 → 中点外推 → eth 中点刷新 → 速度 → 位置 → 姿态**。
核心思想：不是"谁给谁最新值"，而是**整帧按区间中点/梯形组织**（一阶欧拉只是我们的教学版）。

| 步 | 代码 | 含义 / 为什么 |
|---|---|---|
| ① | `[phim,dvbm]=cnscl(imu,0)` | 圆锥(coning)+划桨(sculling)补偿，把 nn 个子样合成一个姿态增量+速度增量；**速度用旧姿态投影的损失在这里被划桨项补回** |
| ② | `phim=Kg*phim-eb*nts; dvbm=Ka*dvbm-db*nts` | 标定：比例因子+零偏 |
| ③ | `vn01=vn+an*nts2; pos01=pos+Mpv*vn01*nts2` | 用当前加速度**外推半拍**的中点速度/位置 |
| ④ | `eth=ethupdate(eth, pos01, vn01)` | **用中点值刷新 eth**（不是旧值也不是新值） |
| ⑤ | `wib=phim/nts; fb=dvbm/nts` | 增量→平均速率（供 KF/DR/显示用，编排本身只用增量） |
| ⑤′ | `web=wib-Cnb'*wnie; wbar=0.9*wbar+0.1*web` | web=体相对地球角速度；**wbar 是低通(0.9/0.1)**，用于 sinsod 转不转弯检测 |
| ⑤″ | `wnb=wib-(Cnb*rv2m(phim/2))'*wnin` | ω_nb 投影用**姿态中点** rv2m(phim/2) |
| ⑥ | `fn=qmulv(qnb,fb)` | 旧姿态投影 dvbm（划桨已含姿态变化） |
| ⑥′ | `an=rotv(-wnin*nts2,fn)+gcc` | 比力旋转回中点时刻 + 重力/哥氏合并项 |
| ⑥″ | `anbar=0.9*anbar+0.1*an` | 比力加速度低通，供 sinsgps 做 **GPS 时间延迟补偿**（zk=vnL+(tDelay-dt)*anbar） |
| ⑦ | `vn1=vn+an*nts` | 速度更新 |
| ⑦′ | `Mpv(2)=1/clRNh; Mpv(4)=1/RMh` | 位置矩阵只改两个元素（其余不变） |
| ⑦″ | `Mpvvn=Mpv*(vn+vn1)/2; pos+=Mpvvn*nts` | **梯形平均**新旧速度积位置 |
| ⑦‴ | `an0=an` | 存上一拍加速度（三阶位置项 `(an-an0)*nts²/3` 被注释掉时用，默认不需要） |
| ⑧ | `Cnb0=Cnb` | 上一拍姿态阵，KF 反馈用 |
| ⑧′ | `qnb=qupdt2(qnb,phim,wnin*nts)` | 姿态更新：`qnb1=rv2q(-rv_in)⊗qnb0⊗rv2q(phim)`（注释注明 qupdt 直接 wnb*nts 是低精度） |
| ⑧″ | `[qnb,att,Cnb]=attsyn(qnb)` | 四元数→欧拉角/姿态阵同步，保证单位化 |

**注释里的彩蛋**：L33 水平阻尼（`an(1:2)-2*0.207*ws*vn(1:2)`，阻尼惯导，默认关）；L38 三阶位置修正；L45 qupdt vs qupdt2。

## 4. 第 3 周接口

`etm.m` 的 15 维连续误差转移矩阵用的就是本页的 `wnin/wnien/fn/Mpv/rmh...`：

```
状态序：[φ(3) | δv(3) | δp(3) | ε(3) | ∇(3)] = 15
Ft = [ Maa  Mav  Map  -Cnb  O33
       Mva  Mvv  Mvp   O33  Cnb
       O33  Mpv  Mpp   O33  O33
       zeros(6,9)  diag(-1/[tauG;tauA]) ]
```
其中 `Maa=-skew(wnin)`、`Mva=skew(fn)`、`Mvv=Avn*Mav-Awn`（Awn=skew(wnien)）、`Mpv=ins.Mpv`。下一份笔记（第 3 周）逐块讲物理意义。