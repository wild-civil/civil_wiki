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
│     a2qua/q2att      #   ★ att↔四元数（PSINS 约定，M4 起全库统一）
│     qmul/qconj/qmulv/rv2q            # 四元数运算
│     rv2m/m2rv/rotv/skew/vecc         # 旋转矢量与矩阵小工具
│     earth.m          #   地球参数：RM / RN / clRNh / g / wnie
│     insupdate.m      #   机械编排：姿态 / 速度 / 位置更新（逐行注释版）
│     trjsegment.m     #   轨迹生成：航段语言（8 基本段，M2）
│     trjsimu.m        #   轨迹正演机：avp → imu 反算（M4 对齐 P4 minitrj）
│     odsimu.m         #   里程计增量仿真（真值位移差分 dS，M4）
│     drinit.m         #   航位推算：DR 初始化（M4 对齐 P4 mini_drinit）
│     drupdate.m       #   航位推算：体 y 里程 × 航向推位置（M4 对齐 P4 mini_drupdate）
│     kfinit.m         #   卡尔曼滤波器初始化（M4，22 维空壳）
│     kfupdate.m       #   卡尔曼滤波更新（时间 + 量测，Joseph，M4）
│     kffk.m           #   22 维状态转移阵（φ 角 INS15 + DR 扩展 7，M4）
│     kffeedback.m     #   反馈闭环（'v' 仅速度，M4）
├── demos/             # 场景脚本（demo_sins_dr.m：SINS+DR 组合完整仿真，M4 验收）
├── verify/            # 回归自检：verify_trans / verify_ins / verify_trj / verify_dr（确定性，无工具箱）
└── assets/            # 出图
```

> 注：本库用**平铺 `core/` 目录 + 直接函数调用**（而非 MATLAB package `+ins`），
> 避免"包名 `ins` 与结构体变量 `ins` 同名冲突"（MATLAB 工作区变量优先于包名）。

## ⚠️ 机体系约定（M4 起全库统一，勿用"航空 NED"直觉）

PSINS 的 att/里程约定与航空 NED **不同**，M4 对拍 P4 必须用这套：

- **机体系 x 右、y 前、z 上**（机器人/车体系，不是航空的 x 前 y 右 z 下）；
- 姿态角对应轴：**pitch 绕 x（右翼轴）、roll 绕 y（纵轴）、yaw 绕 z（竖轴）**——
  入口 `a2qua.m`（att→q）、`q2att.m`（q→att），`euler2cnb`/`cnb2euler` 是它们的阵形式；
- 体 **y = 前进方向** → 里程计默认沿体 y（drinit 里 `prj = Cbo·[0;1;0]`）；
- yaw=0 车头朝北，**yaw 增大 = 左转**（北→西）；
- wat 表加速度 `at=[a1;a2;a3]`：**a2 = 前向**（沿体 y）、a1 = 侧向。
- 易踩坑：与"标准航空 euler2cnb（pitch 绕 y）"差一个转置级——M1 的旧约定已废弃。

## 快速开始

```matlab
addpath(genpath('docs/惯性导航/assets/miniins'));      % 一次性把 core/verify/demos 都加进路径

q   = rv2q([0; 0; pi/2]);             % 绕 z 转 90° 的四元数
C   = q2cnb(q);                       % → 姿态阵 [0 -1 0; 1 0 0; 0 0 1]
att = cnb2euler(C);                   % → 欧拉角 [0; 0; 1.5708]（弧度）
verify_trans                           % 转换模块自检（应全 PASS）
verify_ins                             % 机械编排自检（应全 PASS）
verify_trj                             % 轨迹生成自洽自检（应全 PASS）
verify_dr                              % 航位推算自洽自检（应全 PASS，M4 版）

% —— M4 验收：SINS+DR 组合导航完整仿真（对拍 P4 基准）——
cd docs/惯性导航/assets/miniins/demos
demo_sins_dr        % 期望：SINS-only ≈345 m / DR-only ≈151 m / 组合 ≈45.5 m
```

## 里程碑

- **M1 ✅**：`trans` 系列 + `earth.m` + `insupdate.m`（纯惯导闭环，逐行注释）
- **M2 ✅**：轨迹生成（`trjsegment` 航段语言 + `trjsimu` 正演机），`verify_trj` 正演→反演自洽
- **M3 ✅**：航位推算（`drinit` / `drupdate`，航向×里程），`verify_dr` 自洽
- **M4 ✅**：组合导航 KF（`kfinit`/`kfupdate`/`kffk`/`kffeedback`，22 维 SINS+DR）——
  已对齐 P4 主循环并本机 MATLAB 验证（`demo_sins_dr` 组合 **44.9 m** 对齐 P4 45.5 m，dKod +0.0994 vs +0.1004）；
  修复两大隐蔽 bug（KF 时间更新推 x 致 267 m → 只推 P；`a2qua` q0 符号），`verify_trans/ins/trj/dr` 全 PASS。
- **M5**：GNSS 扩展 + 与固件 C SIL 打通（启动首项：统一 `trjsegment` 的 `cf` 符号约定，见 `demos/trjsegment与WAT表生成说明.md` §10）
