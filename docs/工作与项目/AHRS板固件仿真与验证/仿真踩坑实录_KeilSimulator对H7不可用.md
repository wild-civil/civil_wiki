# 仿真踩坑实录：Keil 内置 Simulator 对 STM32H7 不可用

> 一份省时间的记录：**想用 Keil 内置 Simulator 在没板子时先跑固件抓 HardFault？对 STM32H7 走不通，别再试了。**

## 背景

空窗期（PCB 已画好、样片未回）想先抓「固件本身会不会在真芯片上 HardFault」这类 CPU 级风险。Keil 自带一个 **Use Simulator** 模式（不接 ST-Link，纯软件模拟 CPU），看起来是零成本 L2 方案。我们实测踩坑如下。

## 现象时间线

1. 切到 `Options for Target → Debug → Use Simulator`，`Ctrl+F5` 进入调试会话。
2. 立刻报：
   ```
   *** error 65: access violation at 0x5802480C : no 'read' permission
   ```
   `0x58024800` 起是 STM32H7 的 **PWR** 外设区（电源控制）。HAL 在初始化时读它，而仿真器**没建模该外设**，于是抛「无读权限」。
3. 按常见解法，在 **Command 窗口** 执行：
   ```
   MAP 0x58020000, 0x5802FFFF READ WRITE
   ```
   error 65 消失，但程序**死循环**——界面卡在 `system_stm32h7xx.c`，调试按钮全灰、CPU 空转。
4. 精确定位卡死行：
   ```c
   while ((PWR->CSR1 & PWR_CSR1_ACTVOSRDY) == 0U)
   ```
   这是 `HAL_PWREx_ConfigSupply` / 时钟配置阶段，等待 VOS 电压调节就绪。

## 根因

`MAP` 命令**只给未建模外设区加了读写权限**，让仿真器不再报 error 65——但它**没有真的建模 PWR/RCC**。仿真器对所有未建模寄存器一律**返回 0**。

于是：
- `PWR->CSR1` 恒为 0 → `PWR_CSR1_ACTVOSRDY`（就绪标志位）永远是 0 → `while(...==0U)` 永远跳不出去 → **死循环**。
- 同理，RCC/时钟树（PLL、HSE/HSI）根本不走时，任何「等待时钟 ready」的循环都会死锁，或者即使勉强跑过、时序也全错。

**结论：这是 Keil 仿真器不建模 H7 时钟树 / 电源树的固有限制，不是固件 bug，也不是操作错。** 你的固件在真芯片上这两微秒就过。

> 即便把 `MAP` 范围铺满整个 AHB/APB 外设区，外设寄存器仍然恒 0，问题不会消失——只会从「error 65」变成「死循环在别处」。

## 怎么脱困

点调试工具栏的 **红色方块（Stop / 退出调试会话）**，或 `Debug → Start/Stop Debug Session`（Ctrl+F5 再按一次）退出即可，按钮会恢复彩色。

## 正确的替代路径

| 想抓的东西 | 该走哪条路 | 说明 |
|---|---|---|
| 软件 / 逻辑 / 协议层 | **本项目 gcc-SIL（已 PASS）** | 8 路 init、0 NaN/Inf、AA55 CRC 全对，已验完 |
| CPU 级崩溃（空指针 / 栈溢出 / 坏函数指针 → HardFault） | **样片回来后用真板 SWD + HardFault 分析** | 最可信，且能看真实栈/寄存器 |
| 指令级全固件仿真 | **Renode**（建模 STM32H743 + 7 外设跑真 `.elf`） | 比 Keil Sim 完整，但要建外设模型，工作量大，作为备选 |
| 大型动力学 / 闭环 | Gazebo / X-Plane / Simulink | **不跑你的固件**，只当数据源 / 参照系 / 闭环宿主，没板子也没法闭环 |

> 一句话：**L2 的 CPU 级验证别指望 Keil 内置 Simulator；样片回来用真板 SWD，或视情况上 Renode。** 你在这趟里学会的 Keil 调试按钮（Run/Step/断点/Call Stack）在真板上电调试时正好用得上，不算白学。

## 顺带：空窗期仿真该做什么、不该做什么

- ✅ **该做**：把已 PASS 的 gcc-SIL 巩固成「回放真实采数」回归基线（板回抓一段真总线数据即当金标准反复重放）。
- ❌ **别做**：在 Keil Simulator 上继续打 MAP 补丁、或现在就上 Renode 建模 7 个外设——性价比低，且 SIL 已覆盖逻辑层。
- ⏳ **等样片**：真硅验证（D-Cache 一致性、SPI 时序、1000 Hz 实时性、栈深度）只能等板子回来照 [板级 Bring-up 清单](板级BringUp与验证清单.md) 打勾。
