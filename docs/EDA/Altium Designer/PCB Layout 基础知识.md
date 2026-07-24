---
title: Altium Designer PCB Layout 基础知识
tags: [EDA, Altium, PCB, 布局, 布线]
---

# Altium Designer PCB Layout 基础知识

PCB（印刷电路板）是原理图的「物理实现」：把元件摆到板子上、用铜箔把该连的网络连起来，并满足制造与电气规则。本文讲从原理图同步进来之后，到输出生产文件的最小可用流程。

> 前置：先读 [基础知识](基础知识.md) 与 [原理图绘制](原理图绘制.md)。

## 流程总览

1. 从原理图 **Update PCB**，元件带着飞线进来；
2. 画 **板框（Board Outline）**；
3. 定 **叠层（Stack-up）**；
4. **布局（Placement）**；
5. **布线（Routing）**；
6. **铺铜（Polygon Pour）**，通常先铺地；
7. 设 **设计规则** 并跑 **DRC**；
8. 输出 **Gerber / 钻孔 / BOM / 坐标**。

## 1. 导入与板框

- 同步后元件堆在板外，先画 **板框**：在 Mechanical 层（或 Keep-Out）画闭合矩形/异形，再用 `Design → Board Shape → Define from selected objects` 定义板形。
- 板子尺寸受外壳和工艺限制，先定下来再布局。

## 2. 叠层（Stack-up）

- 双层板：Top（信号）+ Bottom（信号），最常用。
- 多层板：加 Mid（内层走线）和 Plane（整层电源/地）。`Design → Layer Stack Manager` 配置。
- 嘉立创工艺下，4 层板也很便宜，高速/复杂板值得上。

## 3. 布局（Placement）

优先级：

1. **固定件先放**：连接器、按键、显示屏、天线区域——受结构束缚；
2. **核心 IC 及其去耦电容**靠近放；
3. **模块化**：电源一块、RF 一块、数字一块，互不干扰；
4. 考虑散热（大功率器件留铜皮/散热过孔）、装配（插座方向）、维修（标号朝外）。

> 布局约占成败的 70%。布局乱，布线再漂亮也救不回来。

## 4. 布线（Routing）

- **交互式布线**：`Route → Interactive Routing`，沿飞线走线。
- **线宽**：由电流和规则决定；电源/大电流线加宽，信号线可细。默认线宽在规则里设。
- **过孔（Via）**：换层用，内层越多过孔越多；注意孔径工艺下限。
- **差分对（Differential Pair）**：USB、以太网、RF 等差分信号成对走，等长等距；用 `Differential Pair Routing`。
- **等长（蛇形）**：DDR、高速总线需长度匹配，用 `Interactive Length Tuning` 调蛇形。

> 先走电源和关键信号（时钟、差分、射频），再走普通信号；电源可先走粗线或后面用铺铜补。

## 5. 铺铜（Polygon Pour）

- 通常把 **GND 整层/大块铺铜**，降低地阻抗、改善回流。
- `Place → Polygon Pour`，选网络（如 GND），设连接方式（一般直接连接或热焊盘）。
- 铺铜后 `Tools → Polygon Pours → Repour All` 更新。

## 6. 设计规则与 DRC

规则在 `Design → Rules`（PCB Rules and Constraints Editor）里设，常用：

- **Clearance（间距）**：导线/焊盘之间最小间距（如 6 mil）；
- **Width（线宽）**：不同网络不同线宽（电源加宽）；
- **Routing Via Style（过孔）**：孔径/盘径；
- **Differential Pairs**：差分间距/线宽；
- **Plane / Polygon Connect**：铺铜连接方式。

设好规则后跑 **DRC（Tools → Design Rule Check）**，按 Messages 把违规清零。DRC 不过，别出图。

## 7. 输出生产文件

用 **OutJob（.OutJob）** 一键输出，或手动：

- **Gerber**：各层光绘文件，工厂用来做板；
- **NC Drill**：钻孔文件；
- **BOM**：物料清单（贴片用）；
- **Pick & Place（坐标文件）**：SMT 贴片机用。

> 出图前最后跑一次 DRC + 目检丝印（别压焊盘）、确认封装和方向（二极管/极性电容/IC 第一脚）。

## 常见坑

- 封装画错/方向反了 → 板回来焊不上；
- 忘了铺地或地没连上 → 回流差、噪声大；
- 丝印压在焊盘上 → 看不清还影响焊接；
- 间距/线宽低于工艺能力 → 工厂做不了或良率低；
- 没跑 DRC 就出图 → 回来一堆飞线没连。

## 下一步

三篇入门路径到此打通：你已经能画原理图、布一块双层板并出生产文件。后续可深入：自己画封装库、多图纸层次化设计、高速差分与阻抗、刚柔结合、用 OutJob 标准化输出。
