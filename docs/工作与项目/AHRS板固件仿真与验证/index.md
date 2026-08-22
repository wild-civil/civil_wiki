# AHRS 板固件仿真与验证

> 围绕 STM32H743VIH6 航姿解算板的「烧入真机前如何提前验证」讨论复盘。
> 核心结论先放这：**仿真省的是「算法 / 逻辑 / 协议」试错钱；硬件时序、D-Cache 缓存一致性、1000 Hz 实时性必须上真硅收口。**

## 当前状态（一眼看懂走到哪了）

| 事项 | 状态 | 说明 |
|---|---|---|
| 板卡 | 🟡 已画好、打样未回 | PCB 设计完成，等样片回来才能上电 |
| SPI3 改 SLAVE+Mode3 | ✅ 已完成 | CubeMX 改 `.ioc` 并重新生成，blocking 项消除 |
| D-Cache/DMA 一致性修复 | ✅ 已落地 | UM982 RX 读前 Invalidate、SPI3 TX 发前 Clean，真硅必现 bug 先修 |
| L1 / SIL（gcc，真实固件零修改） | ✅ PASS | 8 路 init 全过、0 NaN/Inf、姿态跟踪真值、3680 帧 AA55 CRC 全对 |
| Keil 内置 Simulator | ❌ 不可用 | 对 STM32H7 死循环（详见 [踩坑实录](仿真踩坑实录_KeilSimulator对H7不可用.md)），别再试 |
| L2 指令级（Renode）/ L3 真板 HIL | 🟡 Renode 探索已启动 | 样片回来用真板 SWD 抓 HardFault；Renode 已开 wiki 作为空窗期 L2 路径（见 [Renode 仿真验证](Renode仿真验证.md)） |
| 板级 Bring-up 清单 | ✅ 已写好 | [板级 Bring-up 与验证清单](板级BringUp与验证清单.md) |

## 我们走到哪了（一句话旅程）

板子还没回 → 先想「烧之前怎么验」→ 搞清了 MIL/SIL/PIL/HIL 阶梯与各类仿真工具谱系 → 把**真实固件零修改编译到 PC 跑通 SIL**（逻辑闭环验完）→ 想用 Keil Simulator 顶 L2 却踩死循环（已记成踩坑实录）→ 结论：**空窗期仿真线先到头，剩下真硅验证等样片**。

## 本章内容

- [验证策略总览（MIL/SIL/PIL/HIL 与仿真工具谱系）](验证策略总览.md)
  - 三层验证金字塔 L1/L2/L3 各抓什么
  - MIL/SIL/PIL/HIL 一把尺 + 阶段澄清（手写 C 团队为何从 SIL 起步、等价链图）
  - 仿真工具四类谱系（学校 / 企业 / 军工各用什么）
  - **MATLAB/Simulink 到底怎么用、C 代码要不要进仿真、得到什么结果算好**
- [PC 端 SIL 实战（真实固件零修改跑通）](SIL_PC实战.md)
  - gcc-SIL 脚手架架构、运行结果（PASS 证据表）、能抓 / 不能抓边界、一键复跑命令
- [板级 Bring-up 与验证清单](板级BringUp与验证清单.md)
  - 样片回来后的上电 / 点亮 / 逐传感器 / 融合 / 收尾全流程 + 本项目特有查缺
- [仿真踩坑实录：Keil Simulator 对 H7 不可用](仿真踩坑实录_KeilSimulator对H7不可用.md)
  - error 65 → MAP → 死循环 `while ((PWR->CSR1 & PWR_CSR1_ACTVOSRDY) == 0U)` 全过程与正确替代路径
- [MATLAB ESKF 算法验证（Phase 1）](MATLAB_ESKF算法验证.md)
  - 独立 MATLAB ESKF 参考实现 + 数据发生器 + 验证脚本，证明 ESKF 数学收敛无误
  - 三张核心图：数据流、单步循环、15 维状态布局
  - 已知坑：气压计默认关闭、数据须从 body 角速度积分、函数名须与文件名一致
- [Renode 仿真验证（L2 指令级）](Renode仿真验证.md)
  - 官方已内置 `stm32h743.repl`（cortex-m7），但无 `.resc` demo，需自写模板
  - 跑通 Keil `.axf` 的 `.resc` 模板 + armclang 产物的 VTOR/PC/SP 坑
  - 三条路线：A 仅 MCU / B 自建传感器 C# 模型挂总线 + 合成数据喂真实 INS / C RESD 数据表
  - 与 SIL/PIL/HIL 衔接、D-Cache+DMA 在 Renode 下不一定建模的提醒
- [验证矩阵与真实数据回放（L4）](验证矩阵与真实数据回放.md)
  - 数据真实度 × 执行载体的 2×2 矩阵：SIL / 回放评估 / PIL / HIL 各抓什么
  - **真实数据回放评估不需要板子**——样片回来前即可用真实噪声/磁扰/丢星数据评估
  - 完整七步验证链路（MATLAB 参考 → 等价对拍 → SIL → 回放 → PIL → HIL → 地面试验）
  - L4 工具链：ins_logger（板载记录）/ raw2sim（格式转换）/ replay_eval（回放判定）
- [ESKF 验证与踩坑实录](ESKF验证与踩坑实录.md)
  - 高机动发散根因：错 F 矩阵伪耦合 + 雅可比多乘 R + 朴素协方差坍缩，被 reset_att quirk 掩盖
  - 修复：标准 Solà 右误差 ESKF + Joseph 协方差 + decoupled gating（65.4s 高机动 1.82° 收敛）
  - baro 消融（与姿态块解耦）、float/double 假阴性与缩放判据、MATLAB 封装 C 的坑
  - MTi v2.x/v3.x 版本核对、check_mag 幅值阈值与参考向量不一致的真机隐患

## 下一步该干什么（做仿真？还是写 C？）

**结论：对「算法 / 逻辑」层的仿真已到头（SIL PASS + MATLAB 验完）；但 Renode 作为空窗期 L2 路径已开 wiki 探索 —— 它补的是「真实 .axf 在 H743 上跑不跑得起来」，和继续写 C 不冲突。**

- ❌ **别盲目投仿真**：
  - Keil Simulator 对 H7 死循环（不可用，见踩坑实录）；
  - Gazebo/X-Plane 不跑你的固件，是数据源 / 参照系，没板子也没法闭环；
  - Renode 的 **B 路线（建模 7 个外设）**工作量确实大，不急着全上 —— 但 **A 路线（仅 MCU 最小系统）成本低、今天就能跑**，已开 [Renode 仿真验证](Renode仿真验证.md) 专门记，且和写 C 可并行。
- ✅ **该写 C（硬件无关、板回即测）**，可选项：
  1. **SIL 回放框架**：把合成数据源改成「回放真实采数」，让 SIL 变成可重复回归基线；
  2. **底板 SPI3 主机侧解析**：航姿板已按 68B 帧从机输出，底板需读 → 纯 C、硬件无关；
  3. **FRAM（SPI2）驱动**：补全存储节点，硬件无关可写、暂不可测；
  4. **SIL 加覆盖率 / 最坏执行时间**（gcov + 计时桩）。

> 具体选哪个开干，见对话里给出的选项。
