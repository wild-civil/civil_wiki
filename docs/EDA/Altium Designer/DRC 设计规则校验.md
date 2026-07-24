---
title: Altium Designer DRC 设计规则校验
tags: [EDA, Altium, PCB, DRC, 设计规则, 校验]
---

# DRC 设计规则校验（Design Rule Check）

DRC 是按你在 `Design → Rules` 里设的约束，批量检查 PCB 是否违规。它是出图前最后一道关——**DRC 不过，别出图**。

> 前置：铺铜相关的几条 DRC 见 [铺铜（Polygon Pour）](铺铜（Polygon Pour）.md) 第七节。

## 一、在哪里跑 DRC（菜单 + 快捷键）

- 菜单：`Tools → Design Rule Check`，快捷键 **`T` → `D` → `R`**；
- 弹出 *PCB Design Rule Check* 窗口，勾选要跑的类别（通常全选），点 **Run Design Rule Check**；
- 结果：生成 DRC 报告，并在 **Messages 面板**逐条列出 Violation，PCB 上用绿色高亮标出违规处；
- **实时（Online）DRC**：`Preferences → PCB Editor → General` 勾选 *Online DRC*，编辑时即时标错（工具栏也有闪电图标可切换）。

## 二、怎么看违规 + 怎么清零

1. 打开 **Messages 面板**（`View → Panels → Messages`）；
2. **双击某条违规** → 画面飞到该处并高亮；
3. 逐条修：改间距 / 线宽 / 连接方式 / 重铺铺铜，再重跑；
4. 所有 Violation 清零才算过。

## 三、DRC 规则条目 中英对照（含简要说明）

> 下表按你工程中实际出现的条目整理，类别列用于归类理解。规则匹配遵循"**优先级高的先生效**"原则（规则列表靠上 / 优先级数值高的先匹配，可在规则编辑器用 *Priority* 调整顺序）。

| # | 英文条目 | 中文翻译 | 功能简要说明 | 类别 |
|---|---|---|---|---|
| 1 | `Clearance Constraint (Gap=10mil),(Disabled)(All),(All)` | 间距约束（间隙=10mil，**已禁用**），适用全部对象 | 旧的 10mil 铜间距规则，已关闭不再参与校验 | 电气·间距 |
| 2 | `Clearance Constraint (Gap=6mil),(All),(All)` | 间距约束（间隙=6mil），适用全部对象 | 全局铜箔/走线/焊盘/过孔最小间距 | 电气·间距 |
| 3 | `Clearance Constraint (Gap=5mil),(All),(All)` | 间距约束（间隙=5mil），适用全部对象 | 铜箔、走线、焊盘、过孔之间电气安全间距 | 电气·间距 |
| 4 | `Short-Circuit Constraint (Allowed=No),(All),(All)` | 短路约束（禁止短路），适用全部对象 | 检测不同网络铜箔互相重叠干涉 | 电气·短路 |
| 5 | `Un-Routed Net Constraint ((All).)` | 未布线网络约束 | 检查网络内存在没有连通的飞线（开路、漏布线） | 布线·未布线 |
| 6 | `Modified Polygon (Allow modified: No),(Allow shelved: No)` | 已变更铺铜约束（不允许未重铺铺铜、不允许搁置铺铜） | 检测编辑后还没重新浇注的铺铜 Polygon | 铺铜·已变更 |
| 7 | `Width Constraint (Min=4mil),(Max=20mil),(Preferred=5mil).(All)` | 线宽约束（最小4mil，最大20mil，优选5mil） | 控制信号线走线宽度上下限 | 布线·线宽 |
| 8 | `Width Constraint (Min=10mil),(Max=10mil),(Preferred=10mil).(All)` | 线宽约束（固定10mil） | 一般给电源宽走线使用 | 布线·线宽 |
| 9 | `Routing Topology Rule(Topology=Shortest).(All)` | 布线拓扑规则（最短路径模式） | 走线按最短路径连接 | 布线·拓扑 |
| 10 | `Power Plane Connect Rule(Relief Connect)(Expansion=20mil),(Conductor Width=10mil),(Air Gap=10mil),(Entries=4).(All)` | 电源内电层连接规则（热焊盘连接） | 扩张20mil、导线宽10mil、隔热间隙10mil、4根连接臂 | 平面·内电层 |
| 11 | `Hole Size Constraint (Min=1mil),(Max=100mil).(All)` | 孔径尺寸约束（最小1mil，最大100mil） | 限制过孔、机械孔钻孔直径范围 | 制造·孔径 |
| 12 | `Hole To Hole Clearance (Gap=5mil).(All)` | 孔与孔间距约束（间隙5mil） | 两个钻孔中心之间最小安全距离，防连孔 | 制造·孔间距 |
| 13 | `Minimum Solder Mask Sliver (Gap=1mil).(All)` | 最小阻焊桥约束（全局1mil） | 相邻焊盘开窗之间绿油最小宽度，防绿油脱落 | 制造·阻焊桥 |
| 14 | `Minimum Solder Mask Sliver (Gap=1mil).(InBGA).(All)` | 最小阻焊桥约束（BGA区域1mil） | 专门给 BGA 芯片放宽的阻焊桥规则 | 制造·阻焊桥 |
| 15 | `Silk To Solder Mask (Clearance=0mil).(IsPad).(All)` | 丝印到阻焊开窗间距（0mil，仅焊盘） | 丝印可压到焊盘开窗上的特例规则 | 丝印·丝印到阻焊 |
| 16 | `Silk To Solder Mask (Clearance=5mil).(IsPad).(All)` | 丝印到阻焊开窗间距（5mil，仅焊盘） | 丝印字符距离焊盘绿油开窗的安全距离 | 丝印·丝印到阻焊 |
| 17 | `Silk to Silk (Clearance=10mil).(All)` | 丝印与丝印间距约束（10mil） | 两层丝印字符互相之间距离 | 丝印·丝印互距 |
| 18 | `Silk to Silk (Clearance=0mil).(All)` | 丝印与丝印间距约束（0mil） | 允许丝印互相重叠的特例规则 | 丝印·丝印互距 |
| 19 | `Net Antennae (Tolerance=0mil).(All)` | 网络天线约束（允许长度0mil） | 禁止走线出现无负载悬空铜桩，高频板抑制辐射 | 电气·天线 |
| 20 | `Board Clearance Constraint (Gap=0mil).(InNet('VDD_MCU'))` | 板边间距约束（0mil，仅VDD_MCU网络） | VDD_MCU 铜皮到 PCB 板框距离 | 制造·板边间距 |
| 21 | `Board Clearance Constraint (Gap=0mil).(All)` | 板边间距约束（0mil，全部网络） | 铜箔距离 PCB 外形板框的安全间隙 | 制造·板边间距 |
| 22 | `Height Constraint (Min=0mil),(Max=1000mil).(Prefered=500mil).(All)` | 高度约束（最低0mil，最高1000mil，优选500mil） | 3D 装配高度限制，检查元器件高度干涉 | 装配·高度 |

## 四、规则优先级与冗余清理（重要）

你当前同时存在多条**重复规则**：

- Clearance 有 10mil（已禁）/ 6mil / 5mil 三条；
- Silk To Solder Mask 有 0mil / 5mil 两条；
- Silk to Silk 有 10mil / 0mil 两条。

重复规则容易**冲突、报莫名其妙的错**。建议：

1. 保留一条**主规则**（如全局 6 mil Clearance）；
2. 把"特殊区域"用 **Query 限定作用域**的更具体规则覆盖（例如 `InBGA` 的阻焊桥、`InNet('VDD_MCU')` 的板边间距），并把它**优先级调高**；
3. 删掉纯粹重复、无差异的规则。

> 匹配顺序：规则列表**自上而下，靠上的先生效**（即优先级更高）；也可用规则编辑器里的 *Priority* 按钮调整。清理后 DRC 结果更干净、更可控。
> 如果需要，我可以另出一份「规则清理优化建议」专门讲怎么合并去重。

## 下一步

- 铺铜相关的几条 DRC 怎么理解 → 回看 [铺铜（Polygon Pour）](铺铜（Polygon Pour）.md)；
- 常用操作快捷键 → [快捷键速查](快捷键速查.md)。
