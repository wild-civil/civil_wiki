---
title: Altium Designer 铺铜（Polygon Pour）详解
tags: [EDA, Altium, PCB, 铺铜, Polygon, 铜皮, 地]
---

# 铺铜（Polygon Pour）详解

铺铜是 PCB 里最容易让人"似懂非懂"的一块：间距在哪设？它到底连不连导线？改了板子为什么还是旧的？这篇把这些问题一次讲透。

> 前置：先读 [PCB Layout 基础知识](PCB Layout 基础知识.md) 的第 5、6 节有个总览；本文是铺铜专题。
> 跑完规则后记得去 [DRC 设计规则校验](DRC 设计规则校验.md) 把违规清零。

## 一、什么是铺铜 / 为什么要铺铜

**铺铜（Polygon Pour）** = 在 PCB 的某一层上自动填充一大块铜箔，并赋给某个网络（通常是 `GND`）。它不是手动画的铜块，而是由规则驱动的"智能填充"。

主要作用：

- **降低地阻抗**：给地一个低感、低阻的回流平面，信号回流路径短，噪声小；
- **改善 EMI/EMC**：完整的地平面能屏蔽、吸收高频噪声；
- **均流与散热**：大电流网络（电源）铺铜能分摊电流、帮助散热；
- **做电源平面 / 屏蔽**：整块铜当电源或做局部屏蔽。

⚠️ **死铜（Floating Copper）**：没连任何网络的孤立铜皮 = 天线，会辐射/接收噪声。所以铺铜属性里一定要勾 **Remove Dead Copper**（去除死铜）。

## 二、三种"铜"的区别（Polygon Pour / Fill / 内电层）

| 类型 | 怎么放 | 网络感知 | 会随规则重画 | 典型用途 |
|---|---|---|---|---|
| **Polygon Pour 铺铜** | `P` → `G` | ✅ 赋网络 | ✅ 可 Repour | 日常铺地/电源，首选 |
| **Fill 实心填充** | `P` → `F` | 可赋但不智能 | ❌ 不会自动重画 | 散热片、屏蔽罩接地、天线净空 |
| **内电层 Plane（负片层）** | `Design → Layer Stack` 建层 + 分割线 | ✅ 整层一个网络 | 按 Plane 规则 | 多层板整层 GND/电源 |

关键区别：**Fill 不会因规则改变而自动重画**，它就是一个固定铜块；**Polygon Pour 会**，而且遵守 Clearance / Polygon Connect 等规则——所以"铺铜"默认指 Polygon Pour。

> 内电层（负片 Plane）的编辑逻辑与表层铺铜**完全不同**：网络分配走 `Tools → Split Planes → Rebuild Split Planes`、分割只靠 `Place → Line` 画闭合轮廓、禁止放 Polygon/Fill。实操要点（含跨 PCB 复制丢层、DRC 清空平面等坑）见 [AD24 多层板实操](AD24 多层板实操.md)。

<img src="../assets/正片与负片层对照.svg" alt="正片层(表层Polygon Pour)与负片层(内电层Internal Plane)对照：左为起始无铜、画铜才有铜；右为起始满铜、画线挖空" />

> 上图直观对比：表层铺铜是「加法」——在空板上画铜才有铜；内电层是「减法」——整层满铜，画线挖空来分割网络。

## 三、怎么放铺铜（步骤 + 快捷键）

1. 放铺铜：快捷键 `P` → `G`（`Place → Polygon Pour`）；
2. 沿板子画一个闭合多边形：点击落点，**双击 / Enter 闭合**；画的过程中按 **Shift+Space** 切换拐角模式（直角 / 45° / 圆弧）；
3. 在大块铺铜里"抠洞"（如天线净空、高压隔离）：同一菜单 `Place → Polygon Pour Cutout`，画闭合区域即可挖掉；
4. 改属性：放完后**双击铺铜**（或右侧 Properties 面板）。

属性面板里最重要的几项：

| 属性 | 作用 |
|---|---|
| **Net（网络）** | 赋给 `GND` / 某电源网络 → **这是"铺铜是否连接导线"的关键**（见第五节） |
| **Layer（层）** | Top / Bottom / 内层 |
| **Remove Dead Copper（去除死铜）** | 勾选，自动删掉不连任何焊盘的孤立铜 |
| **Pour Over Same Net（同网络覆盖）** | 允许铺铜直接盖在同网络走线上，降低阻抗（默认常开） |
| **Grid Size / Track Width** | Hatched（网格填充）模式下控制栅格；Solid 为实铜 |
| **Connect Style** | 此处只影响"预览"，真正的连接方式在规则里设（见第五节） |

## 四、铺铜与导线的间距——在哪里设

这是 **Clearance（间距）规则** 管的，**不是铺铜自己的设置**。

- 路径：`Design → Rules` → **Electrical → Clearance**（PCB Rules and Constraints Editor）。
- 条目形如 `Clearance Constraint (Gap=6mil) (All)(All)`：表示所有对象之间最小间隙 6 mil。铺铜与走线、焊盘、过孔、其它铺铜之间的间距都受它约束。
- 想给"铺铜 ↔ 导线"单独一套更宽松（或更紧）的间距，用 **Query 限定作用域**：
  - 新建一条 Clearance，在 *Where The First Object Matches* 填 `InPolygon`（或 `InNet('GND')`），*Where The Second* 填 `IsTrack`（或 `All`），设一个更大的 Gap，并把这条规则**优先级调高**；
  - 这样"GND 铺铜 ↔ 走线"用专门间距，其余仍走全局 6 mil。

> 注意：同在 `GND` 网络下的铺铜与 `GND` 走线，若 Clearance 规则设为 **Different Nets Only**（默认），它们之间不会报间距错；若设为 Same Net，则会按间距互相避让（通常没必要）。

## 五、铺铜是否与导线连接（连通性）——核心

"铺铜连不连导线"取决于两件事：

1. **铺铜的 Net 属性**：只有赋了网络（如 `GND`）的铺铜，才会和该网络的焊盘/过孔/走线"算一家人"。`Net = No Net` 的铺铜就是死铜岛（除非你故意做屏蔽/天线）。
2. **Polygon Connect Style 规则**（铺铜连接方式）：`Design → Rules → Plane → Polygon Connect Style`。

连接方式三种：

| 方式 | 说明 | 何时用 |
|---|---|---|
| **Relief Connect 热焊盘 / 花焊盘** | 用 2/4 根"辐条"连焊盘，中间留隔热间隙（Air Gap） | 双层板、手工焊接、常规 SMD 焊盘 |
| **Direct Connect 全连接** | 铺铜直接贴满焊盘 | 过大电流、内层、散热要求高 |
| **No Connect 不连接** | 故意不连该焊盘 | 隔离、净空 |

**关键澄清**：

- 铺铜与**同网络走线**：平行走时按 Clearance 留间距隔离，并非任意点熔合；只有在**重叠处**（铺铜盖过走线）才直接连。
- 铺铜与**同网络焊盘/过孔**：按 Polygon Connect Style 规则连接（热焊盘或全连）。

所以一句话答案：**赋了相同 Net 的铺铜，会和该网络的焊盘/过孔按连接规则连通，和同网络走线在重叠处连通、并行时按间距隔离；赋 No Net 则谁都不连（死铜）。**

## 六、重铺 / 更新铺铜（改了板子一定要重铺）

布线、移动元件后，铺铜**不会自动**跟着变，必须 **重铺（Repour）**：

- 菜单：`Tools → Polygon Pours → Repour All`（重铺全部）
- 菜单：`Tools → Polygon Pours → Repour Selected`（重铺选中）
- 铺铜上 **右键 → Polygon Actions → Repour**（也含 Shelve 搁置 / Resume 恢复显示）

常用快捷键（详见 [快捷键速查](快捷键速查.md)）：

- 全部重铺：`T` → `G` → `A`
- 重铺选中：`T` → `G` → `M`（先选中铺铜；加速键随版本可能为 S/R，以 `Tools → Polygon Pours` 菜单显示为准）

> **Shelve（搁置）**：临时把铺铜收成边框只显示轮廓，加快大板操作；出图前务必 **Resume** 并再 Repour 一次。

## 七、铺铜相关的 DRC 校验

铺铜改动后，跑 DRC（[DRC 设计规则校验](DRC 设计规则校验.md)）时重点关注这几条：

- `Clearance`：铺铜与别的东西间距不够；
- `Short-Circuit`：不同网络铺铜重叠干涉；
- `Modified Polygon`：**专为铺铜设**——编辑后忘了重铺就会报这条；
- `Un-Routed Net`：该连的网络还有飞线没连（铺铜没赋对网也会这样）。

看到 `Modified Polygon` 报错 = 忘了 Repour，全铺一次即可。

## 八、常见坑

- 铺了 `GND` 但地没连上 → 没赋 Net，或改完没 Repour；
- 死铜岛 → 没勾 Remove Dead Copper，成了天线；
- 铺铜间距太小工厂做不了 → 改 Clearance，或单独给 `InPolygon` 放宽；
- 热焊盘导致大电流过载 → 大电流地/电源改 Direct Connect，或加多根辐条。

## 下一步

- 把规则设好 → 跑 [DRC 设计规则校验](DRC 设计规则校验.md) 把违规清零；
- 想快速操作 → 看 [快捷键速查](快捷键速查.md)。
