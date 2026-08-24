# Mini-INS 参考实现库

把 PSINS 拆解后内化成**自己的**惯导工具箱：代码自写、逐行注释、零依赖、有 API 边界和回归测试。
对应 wiki 拆解 PSINS 系列（civil_wiki `docs/惯性导航/04_拆解PSINS篇/`，路线图见 `00_内化蓝图.md`）。

## 三者关系

| | PSINS | **Mini-INS（本库）** | AHRS 固件 |
|---|---|---|---|
| 定位 | 工业级教学参考 | 自写参考实现库 | 量产目标实现 |
| 语言 | MATLAB | MATLAB 主 + Python 镜像 | C |
| 用途 | 对照 / 对拍基准 | SIL oracle、算法试验台 | 上板运行 |

对拍链路：`PSINS 原版 ⇄ Mini-INS ⇄ 固件 C`（同一组数据，三方误差应在同一量级）。

## 设计铁律（全库遵守）

1. **API 签名对齐 PSINS**——同名同参，PSINS ⇄ Mini-INS 对照零成本，对拍脚本直接复用；
2. **每行都是教学注释**——函数头给"公式层"（公式编号 + 符号表），体内逐行标注对应公式；
3. **`data_classes.m` = 第 0 篇数据结构速查表的代码形态**——wiki 写字段表，库写结构定义，两处同步；
4. **零依赖**——不调用 PSINS、不依赖任何 MATLAB 工具箱，`verify/` 自证正确；
5. **确定性**——误差注入的随机游走默认关（`web=wdb=0`），保证双轨/对拍逐数字可复现。

## 目录结构

```
miniins/
├── README.md          # 本文件
├── core/              # 核心函数（平铺目录，addpath 后直接调用：q2cnb(q) 等）
│     glvs.m           #   地球模型与单位常量
│     data_classes.m   #   数据结构字段定义 + 默认构造函数
│     q2cnb/cnb2q/euler2cnb/cnb2euler  # 四元数↔姿态阵↔欧拉角
│     qmul/qconj/qmulv/rv2q            # 四元数运算
│     rv2m/m2rv/rotv/skew/vecc         # 旋转矢量与矩阵小工具
│     earth.m          #   地球参数：RM / RN / g / wnie
│     insupdate.m      #   机械编排：姿态 / 速度 / 位置更新（逐行注释版）
│     trjsegment.m     #   轨迹生成：航段语言（8 基本段，M2）
│     trjsimu.m        #   轨迹正演机：avp → imu 反算（六步，M2）
│     …                #   （M3-M4 陆续加入：dr / kf …）
├── demos/             # 场景脚本（对标 PSINS demos/）
├── verify/            # 回归自检：verify_trans / verify_ins / verify_trj（确定性，无工具箱）
└── assets/            # 出图
```

> 注：本库用**平铺 `core/` 目录 + 直接函数调用**（而非 MATLAB package `+ins`），
> 避免"包名 `ins` 与结构体变量 `ins` 同名冲突"（MATLAB 工作区变量优先于包名）。

## 快速开始

```matlab
addpath(genpath('docs/惯性导航/assets/miniins'));      % 一次性把 core/verify 都加进路径

q   = rv2q([0; 0; pi/2]);             % 绕 z 转 90° 的四元数
C   = q2cnb(q);                       % → 姿态阵 [0 -1 0; 1 0 0; 0 0 1]
att = cnb2euler(C);                   % → 欧拉角 [0; 0; 1.5708]（弧度）
verify_trans                           % 转换模块自检（应全 PASS）
verify_ins                             % 机械编排自检（应全 PASS）
verify_trj                             % 轨迹生成自洽自检（应全 PASS，M2）
```

## 里程碑

- **M1 ✅**：`trans` 系列 + `earth.m` + `insupdate.m`（纯惯导闭环，逐行注释）
- **M2 ✅**：轨迹生成（`trjsegment` 航段语言 + `trjsimu` 正演机），`verify_trj` 正演→反演自洽
- **M3**：航位推算（`drinit` / `drupdate`）
- **M4**：组合导航 KF（`kfinit` / `kfupdate` / `kffk` / `kffeedback`，15→22 维）
- **M5**：GNSS 扩展 + 与固件 C SIL 打通
