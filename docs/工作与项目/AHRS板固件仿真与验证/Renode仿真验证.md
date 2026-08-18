# Renode 仿真验证（STM32H743 / AHRS 板）

> 板子没回之前，用 Renode 跑**真实固件**，把「算法 → 固件集成 → 外设/总线」这条链路在没有硬件的情况下先验起来。
> 定位：本项目 **L2 指令级验证**路径（与「真板 SWD + HardFault 分析」并列 / 互补）。

## 0. 为什么现在碰 Renode（空窗期的机会）

空窗期（PCB 已画好、样片未回）我们已经走过的路（详见分区首页与同胞页面）：

- **Keil 内置 Simulator 对 H7 死循环** —— [踩坑实录](仿真踩坑实录_KeilSimulator对H7不可用.md) 已记死，别再试。
- **MATLAB SIL（Phase 1/2）只验到算法层** —— 手写 C `ins_eskf_15d.c` 与参考对拍，证「算法等价」，但没验到真实固件在真实 MCU 上跑不跑得起来。
- **gcc-SIL（L1）已 PASS** —— 真实固件零修改编译到 PC 跑通，逻辑闭环验完（见 [PC 端 SIL 实战](SIL_PC实战.md)）。

Renode 正好补中间的洞：**指令级、确定性**的嵌入式仿真框架，能直接 `LoadELF` 吃 Keil 出的 `.axf` 并跑起来，支持 GDB / VS Code 调试、外设建模、Python hook 追踪。

> 一句话：**MATLAB 验算法对不对，gcc-SIL 验固件逻辑通不通，Renode 验「真实 .axf 在 H743 上跑不跑得起来 + 总线/外设行为对不对」。**

## 1. Renode 是什么 / 不是什么

| 维度 | 说明 |
|---|---|
| 出身 | Antmicro 开源（[renode.io](https://renode.io)、[github.com/renode/renode](https://github.com/renode/renode)），Apache-2.0 |
| 指令集模拟 | C 写，快；支持 ARM Cortex-M（含 M0+/M3/M4/**M7**/M33）、RISC-V、PowerPC 等 |
| 外设模拟 | C# 写，开发效率高；可直接 `include` 一个 `.cs` **运行时编译**挂载 |
| 确定性 | ✅ 同输入同输出，**天然适合自动化测试 / CI** |
| vs QEMU | QEMU 的 STM32/MCU 支持弱、外设模型少、非确定性；Renode 给嵌入式 MCU/IoT 量身做，外设模型丰富、确定性好 |
| **不是** | ❌ 不是 cycle / timing 精确（不能代替示波器看时序）；❌ 不建模真实模拟量 / 电气特性；❌ 板级外部传感器（IMU/磁力计/气压计）**默认没有模型，要自己建** |

**最重要的边界**：Renode 仿真的是 **MCU 内部**（CPU + 片上外设 + 内存），**你们 PCB 上的外部器件（3×IMU、2×磁力计、2×气压计、FRAM、UM982、MAX3490）不在官方模型里**，需要按路线自己挂（见 §6）。

## 2. 两个核心文件：`.repl` 与 `.resc`

这是 Renode 的灵魂，务必分清：

- **`.repl`（Platform Description）** = **硬件 / 平台描述**：CPU 核心、内存映射（Flash/SRAM/DTCM/ITCM/SDRAM）、外设（UART/SPI/I2C/GPIO/TIM/RCC…）及其地址、IRQ 路由、引脚连接。写法 `<名字>: <类型> @ <总线> <地址>`、`->` 连 IRQ。官方库路径 `platforms/cpus/stm32h743.repl`（**我们直接复用**）。
- **`.resc`（Renode Script）** = **仿真脚本 / 场景**：建机器、加载 .repl 平台、加载固件 ELF、开 analyzer 窗口、连总线（如 CAN hub）、定义宏。你日常 `include` / `start` 的就是它。

Monitor 常用命令（括号内为缩写）：

| 命令 | 作用 |
|---|---|
| `mach create [名字]` | 新建一台机器 |
| `include @path/to/x.resc` (`i`) | 加载脚本 |
| `start` (`s`) | 启动仿真 |
| `machine LoadPlatformDescription @platforms/cpus/stm32h743.repl` | 加载平台描述 |
| `sysbus LoadELF $bin` | 加载并运行固件（设 PC/SP） |
| `showAnalyzer sysbus.usart3` | 弹出该 UART 的虚拟终端（看 printf） |
| `machine StartGdbServer 3333` | 开 GDB server，接 VS Code / arm-none-eabi-gdb |
| `peripherals` | 列出当前平台已建模的所有外设及地址（**先跑这个确认支持到哪**） |
| `sysbus SetHookAfterPeripheralRead <外设> "<python>"` | 读该外设后执行 Python（追踪 / 打点） |
| `sysbus SetHookBeforePeripheralWrite <外设> "<python>"` | 写该外设前执行 Python |

> 命令补全：`Tab` 可提示可用 demo 与参数。

## 3. 安装（以 Windows 为例）

1. 到 [builds.renode.io](https://builds.renode.io/) 下载 **Windows 安装包**（或 portable）。
2. 安装后建议把 Renode 目录加入 **系统 PATH**，这样任意位置可 `renode`。
3. 验证：命令行敲 `renode`，出现交互式 Monitor（命令行界面）即成功。
   - Windows 安装包已自带依赖；Linux 才需要额外装 GTK2（`libgtk2.0-0` 等）。

## 4. 新手入门：第一个指令（从零跑通 Monitor）

刚下载装好 Renode，双击打开蹦出那个**黑底命令行窗口**，就是 Renode 的 **Monitor**（也叫 CLI，命令行交互界面）。下面从零开始，先给出该敲的第一行命令，再讲一类新手常踩的报错及其排查思路。

### 4.1 Monitor 的 prompt 会变，先认它

- 刚打开，prompt 是 `(monitor)` —— 此时**还没有机器**，`sysbus` / `peripherals` 这类命令还不存在。
- 一旦你 `mach create` 建了机器，prompt 会变成 `(machine-0)`（或你起的名字）。**只有进入这个状态，才能加载平台、跑固件。**
- 诊断小窍门：若敲 `sysbus ...` 报 "unknown command"，说明机器尚未创建，先 `mach create`。

### 4.2 第一个指令：最小可跑序列（一条一条回车）

```text
mach create
machine LoadPlatformDescription @platforms/cpus/stm32h743.repl
showAnalyzer sysbus.usart1            # 可选：开一个 UART 虚拟终端看 printf
sysbus LoadHEX @D:/完整路径/your.hex  # 加载固件（见 4.3/4.4；优先用 .axf 见 §6）
sysbus WriteDoubleWord 0xE000ED08 0x08000000   # HEX 必须设 VTOR；ELF 多数自动
start
```

逐条说明：

| 命令 | 干什么 / 注意 |
|---|---|
| `mach create` | 建一台机器，prompt 变 `(machine-0)` |
| `machine LoadPlatformDescription @platforms/cpus/stm32h743.repl` | 把官方 H743 平台描述加载进来（CPU/内存/外设映射）。平台库位置见 §5 |
| `showAnalyzer sysbus.usart1` | 弹出一个虚拟串口窗口，固件里的 `printf` 会打印到这里。你们板子实际接调试控制台的是哪个 UART 就改哪个（详见 §6 模板） |
| `sysbus LoadHEX @D:/.../your.hex` | 加载固件进 Flash。**路径前必须加 `@`**（见 4.3） |
| `sysbus WriteDoubleWord 0xE000ED08 0x08000000` | 把向量表基址 VTOR 指向 Flash（0x08000000）。HEX 必须手动设；`.axf` 多数自动，卡住再补 |
| `start` | 启动仿真，固件开始跑 |

> 想先看看 Renode 长啥样（不依赖你们的固件，会联网拉官方示例）：`s @scripts/single-node/stm32f4_discovery.resc`。

### 4.3 文件路径的 `@` 前缀（必看，新手第一坑）

Renode Monitor 里，**所有文件参数（`.hex` / `.axf` / `.resc` / `.repl` / `.cs`）前面必须加 `@`**，否则被当成普通字符串、无法解析成文件路径。

- ❌ 错误：`sysbus LoadHEX D:/path/your.hex`（缺 `@`）
- ✅ 正确：`sysbus LoadHEX @D:/path/your.hex`（有 `@`）

路径用**正斜杠 `/`** 最稳（Windows 也认）；反斜杠 `\` 偶尔和转义打架，建议一律用 `/`。
偷懒技巧：敲 `@` 后按 **Tab** 自动补全（从 Renode 安装目录 + 当前工作目录），能避免拼错路径。

### 4.4 典型报错解析：`Parameters did not match the signature`

初学者很容易这样输入：

```text
sysbus LoadHEX D:/你的完整路径/your.hex
```

报错：

```text
The following methods are available:
 - Void LoadHEX (ReadFilePath fileName, IInitableCPU cpu = null)
There was an error executing command 'sysbus LoadHEX D'
Parameters did not match the signature
```

**根因有两个，叠加在一起：**

1. **路径没加 `@` 前缀** —— `LoadHEX` 的函数签名第一参数是 `ReadFilePath fileName`，而 `@` 正是告诉 Monitor"后面跟的是文件"。你不加 `@`，Renode 把它当普通字符串，类型对不上 → 直接报"参数不匹配签名"。
2. **`D` 本身也不是完整路径** —— 这里只写了盘符开头，路径并未写完。

**修正（补全路径 + 加 `@`）：**

```text
sysbus LoadHEX @D:/你的完整路径/your.hex
```

> 第二个参数 `IInitableCPU cpu = null` 是可选的（默认用当前机器的 CPU），所以只给一个 `@文件` 就够了。

**想更简单？** 换用 `.axf`：`sysbus LoadELF @D:/.../your.axf` —— PC / SP / VTOR **全自动设好**，还带符号方便 GDB（格式与获取见 §6）。

### 4.5 排错自查清单

| 报错 / 现象 | 原因 | 解决 |
|---|---|---|
| `unknown command 'sysbus'` | 还在 `(monitor)`，没建机器 | 先 `mach create` + `LoadPlatformDescription` |
| `Parameters did not match the signature` | 文件参数漏了 `@`，或路径不完整 | 加 `@` + 补全完整路径（见 4.3 / 4.4） |
| `file not found` / 找不到文件 | 路径写错或漏 `@` | 用 `@` + Tab 补全确认 |
| `start` 后没动静 / 串口无输出 | HEX 没设 VTOR；或固件需时钟/外设初始化 | 补 `WriteDoubleWord 0xE000ED08 0x08000000`（HEX 必做） |
| 一跑就 HardFault / 跑飞 | 入口未设好（常见于 HEX） | 按 §6 已知坑从向量表设 SP / PC |

## 5. STM32H743 支持现状（关键）

- ✅ 官方 `platforms/cpus/stm32h743.repl` 已存在（2024-02 合入，commit `#55155`）。核心定义：

  ```text
  cpu: CPU.CortexM @ sysbus
      cpuType: "cortex-m7"
      numberOfMPURegions: 16
      nvic: nvic
  nvic: IRQControllers.NVIC @ sysbus 0xE000E000
      systickFrequency: 96_000_000
  ```

- ⚠️ **官方没有 `stm32h743.resc` demo**（只有 .repl，没有 .resc）。所以下面 §6 的 `.resc` 要**自己写**（照 f7 的模板改，很简单）。
- ⚠️ H7 片上外设模型**不是 100% 全覆盖**：UART/SPI/I2C/GPIO/TIM/RCC 一般都有，但个别高级 / 冷门外设可能 stub。先 `peripherals` 看实际建模了哪些。
- H743 vs H753：同 die，H753 多 Security/Crypto。我们就是 H743，用 `stm32h743.repl` 即可。

## 6. 跑通第一个 demo（用你们自己的 Keil 产物）

Renode 吃固件有两种格式，**都能用**：

- **`.axf` / `.elf`（推荐）**：Keil MDK 编译后**一定会在输出目录生成 `.axf`**（本质是带 DWARF 调试信息的 ELF，就在 `Objects\` 或你 *Options → Output → Select Folder for Objects* 指定的目录里）；`.hex` 反而是额外勾了 *Create HEX File* 才出的。优先用 `.axf` —— `LoadELF` 会自动设好 PC / SP / VTOR，还带符号，接 GDB 也方便。生成 .axf 的 Keil 设置见文末参考链接（已实测可行）。
- **`.hex`（Intel HEX，也能用）**：Renode 支持 `sysbus LoadHEX @file.hex`，**不强制 ELF**。但 LoadHEX 不会自动设入口，加载后需手动设 VTOR（见下方「已知坑」），必要时还要从向量表设 SP / PC。

> 第一次进 Monitor 的完整起步序列、文件 `@` 前缀规则、以及 `LoadHEX` 典型报错的排查，见 **§4 新手入门**。

最小 `stm32h743.resc`（放到 Renode 工作目录下，仿社区 f7 模板）：

```text
:name: STM32H743
:description: AHRS-Board minimal MCU sim (no external sensors yet)
using sysbus
$name?="STM32H743"

mach create $name
machine LoadPlatformDescription @platforms/cpus/stm32h743.repl

# 把你们实际接调试串口的 UART 开出来（USART3 在本项目是接 UM982，
# 这里用 usart1 当虚拟控制台，按实际改）
showAnalyzer sysbus.usart1

# 固件：用你们 Keil 出的 .axf（或自己编的 elf）
$bin ?= @D:/01_Job/Project/AHRS-Board/software/xxx.axf

macro reset """
sysbus LoadELF $bin
"""

runMacro $reset
```

启动：

```text
renode
(monitor) i @stm32h743.resc
(monitor) start
```

!!! note "已知坑：入口 / VTOR / PC-SP 设置"
    - **用 `.axf`（LoadELF）**：多数情况自动设好 PC/SP/VTOR。若卡在 reset 或一跑就飞，再手动设（社区 `hattmt/renode_devstm32`：armclang 产物有时要显式指定）。最稳写法：加载后写 VTOR 寄存器 `sysbus WriteDoubleWord 0xE000ED08 0x08000000`。
    - **用 `.hex`（LoadHEX）**：**LoadHEX 不会自动设入口，必须手动来**：
      1. 设 VTOR 指向 Flash 向量表：`sysbus WriteDoubleWord 0xE000ED08 0x08000000`
      2. 从向量表读初值（Cortex-M：0x08000000 = 初始 SP / 栈顶，0x08000004 = 复位入口）：`sysbus ReadDoubleWord 0x08000000` 与 `0x08000004`，记下值；
      3. 设 `sysbus.cpu SP <栈顶>` 与 `sysbus.cpu PC <复位入口>`。
      > 嫌手动设麻烦？**直接用 `.axf` 最省事**（自动全设好，还带符号）。
    - **排错节奏**：先拿一个**最简单的裸机 blink / printf 工程**试通，再上完整固件（FreeRTOS + 一堆外设初始化），成本低很多。

### 6.1 实战记录：真实 .axf 已跑通（补 PWR 桩 + 全套踩坑）

> 2026-08-18 实测：用 Keil 出的真实固件 `.axf`（76888 B）加载，**`Machine started`、无 FatalError、无 PWR 警告刷屏**，路线 A 最小 MCU 系统立住。下面是能直接抄的最终三件套与踩坑。

**成功日志（节选）：**

```text
Renode, version 1.16.1 (d66b0c2a-202602161036)
(monitor) i "D:\01_Job\Project\AHRS-Board\software\Renode\stm32h743.resc"
(STM32H743) start
Starting emulation...
18:58:07.7356 [INFO] Including script(s): D:\01_Job\Project\AHRS-Board\software\Renode\stm32h743.resc
18:58:07.7546 [INFO] System bus created.
18:58:16.8586 [INFO] sysbus: Loading block of 76888 bytes length at 0x8000000.
18:58:16.8709 [INFO] cpu: Guessing VectorTableOffset value to be 0x8000000.
18:58:16.8732 [INFO] cpu: Setting initial values: PC = 0x8000395, SP = 0x24002B08.
18:58:16.8732 [INFO] STM32H743: Machine started.
```

**三个文件（最终可用版，放在 `software/Renode/`）：**

`stm32h743.resc`：

```text
:name: STM32H743
:description: AHRS-Board minimal MCU sim (no external sensors yet)
using sysbus
$name?="STM32H743"

mach create $name
# 加载自定义平台：在官方 H743 基础上补了 PWR 桩（见 stm32h743_pwr.repl）
machine LoadPlatformDescription @D:/01_Job/Project/AHRS-Board/software/Renode/stm32h743_pwr.repl

# 把你们实际接调试串口的 UART 开出来（USART3 在本项目是接 UM982，
# 这里用 usart1 当虚拟控制台，按实际改）
showAnalyzer sysbus.usart1

# 固件：用 Keil 的 .axf（或自己编的 elf）
$bin ?= @D:/01_Job/Project/AHRS-Board/software/STM32H743_AHRS-Board/MDK-ARM/STM32H743_AHRS-Board/STM32H743_AHRS-Board.axf

macro reset """
sysbus LoadELF $bin
"""

runMacro $reset
```

`stm32h743_pwr.repl`（补官方缺的 PWR 桩）：

```text
using "D:/Program Files/Renode/platforms/cpus/stm32h743.repl"

pwr: Python.PythonPeripheral @ sysbus 0x58024800
    size: 0x400
    initable: true
    filename: "D:/01_Job/Project/AHRS-Board/software/Renode/stm32h743_pwr.py"
```

`stm32h743_pwr.py`（**必须纯 ASCII**，见下方坑②）：

```python
# AHRS-Board PWR stub (Python peripheral for Renode)
# Official stm32h743.repl has no PWR(0x58024800). Firmware SystemInit
# dead-waits on PWR VOSRDY ready flag -> infinite loop. This stub returns
# 0xFFFFFFFF for all reads ("all flags ready") to skip the VOSRDY dead-wait
# and let firmware run past init. Hack, not hardware-accurate; refine later.

def ReadByte(offset):
    return 0xFF

def ReadWord(offset):
    return 0xFFFF

def ReadDoubleWord(offset):
    return 0xFFFFFFFF

def WriteByte(offset, value):
    pass

def WriteWord(offset, value):
    pass

def WriteDoubleWord(offset, value):
    pass
```

!!! warning "本次踩的四个坑（按出现顺序，全是 Renode 语法细节）"
    1. **`script:` 内联不能放多 `def`** —— `Python.PythonPeripheral` 的 `script:` 是内联代码字符串，Renode 用 **IronPython（Python 2 语义）** 解析；Python 单行语句列表里 `;` 只能分隔 `small_stmt`（`return`/`pass`/赋值），而 `def` 是复合语句，不能用 `;` 跟在另一语句后 → 第二个 `def` 报 `unexpected token 'def' (Line 1, Column 36)`。**正确做法：用 `filename:` 属性指向独立 `.py` 文件**（Renode 自带样例 `platforms/cpus/imxrt1064.repl` 即用 `filename: "scripts/pydev/ticker.py"` 印证）。
    2. **`.py` 外设文件必须纯 ASCII** —— IronPython 加载 `filename:` 指向的 `.py` 时若含非 ASCII（如中文注释，`\xe6` 是 UTF-8 中文首字节）报 `Non-ASCII character '\xe6' ... but no encoding declared`。最稳 = `.py` 全 ASCII（中文注释改英文）；PEP 263 `# coding: utf-8` 声明也行但要求声明行本身 ASCII 且位于第 1/2 行，不如直接零非 ASCII 省心。
    3. **`.repl` 不支持 `#` 注释**（报 `unexpected '#'`）、不支持 `"""` 多行字符串**（报 `Unterminated string`）**。`script:` 的值也不能用 `@`（那是 Monitor 命令语法，报 `unexpected '@'`）。`.repl` 须零注释、字符串单行。
    4. **`include` / `i` 命令加载 `.resc` 不需要 `@`**（只方法参数 `LoadELF`/`LoadHEX`/`LoadPlatformDescription` 要 `@`）。实测 `i "D:\...\stm32h743.resc"`（带引号、反斜杠）也能成功——引号路径里反斜杠 OK，但 `.repl`/方法参数里仍建议一律正斜杠。

!!! tip "PWR 桩为什么能跳过死等"
    官方 `stm32h743.repl` 未建 `PWR(0x58024800)`，固件 `SystemInit` 时钟初始化死等 `PWR->VOSRDY` 就绪标志；桩对**所有读返回 `0xFFFFFFFF`**（"所有标志就绪"），固件以为 VOSRDY 已置位就跳出死等继续跑。这是 hack 不是硬件精确——后续想细修可按真实 `PWR` 寄存器（CR1/CSR1 等）让对应位返回真实值。若你用的 Renode 版本已自带 `STM32.PWR` 真实模型，可直接换 `pwr: STM32.PWR @ sysbus 0x58024800`，不必用 Python 桩。

## 7. 针对 AHRS 板的三条路线（重点）

现状：MCU 有官方 `.repl`，但**板级外设一个模型都没有**。三条递进路线：

### 路线 A — 仅 MCU 最小系统（今天就能跑）

- 只跑 §6，验证：启动 → 时钟树 → FreeRTOS 调度 → 某个 UART 的 printf 链路。
- 价值：提前确认「真实固件在 H743 上能不能起来」，暴露栈深度、HardFault、初始化顺序问题（你们栈偏紧的坑 Renode 也能复现）。
- **不碰任何外部传感器**，最快建立信心。

### 路线 B — 自建传感器 C# 模型（核心价值：板没到先验「固件 + 算法」集成）

把 IMU/磁力计/气压计做成 Renode 的 C# 寄存器级外设，挂在 I2C/SPI 总线上，**让真实驱动 `tdk_icm426xx` / `ist_ist8310` / `te_ms5611` 以为自己在跟真芯片说话**。

- 参考实现：`renode-infrastructure/.../Peripherals/Sensors/ADXL345.cs`（官方加速度计示例，结构照抄）。
- 骨架（节选）：

  ```csharp
  using Antmicro.Renode.Core;
  using Antmicro.Renode.Core.Structure.Registers;
  using Antmicro.Renode.Peripherals;
  using Antmicro.Renode.Peripherals.Sensor;

  namespace Antmicro.Renode.Peripherals.Sensor
  {
      public class ICM42688P : IBytePeripheral,
                               IProvidesRegisterCollection<ByteRegisterCollection>
      {
          private readonly ByteRegisterCollection registers;
          // 合成数据缓冲：由 Python hook / RESD 喂入
          private double[] accel = new double[3];
          private double[] gyro  = new double[3];

          public ICM42688P(IMachine machine) : base(machine)
          {
              registers = new ByteRegisterCollection... // 见 ADXL345.cs
              // WHO_AM_I @0x75 = 0x47；各数据寄存器返回合成值
              registers.DefineRegister(0x75).WithValueField(0, 8,
                  valueProviderCallback: _ => 0x47);
              // ... 角速度/加速度数据寄存器、配置寄存器 ...
          }

          public byte ReadByte(long offset)  => registers.Read(offset);
          public void WriteByte(long offset, byte value) => registers.Write(offset, value);

          // 外部喂数接口（被 Python hook 调用）
          public void FeedSample(double ax, double ay, double az,
                                 double gx, double gy, double gz) { /* ... */ }
      }
  }
  ```

- 挂载到平台（在你们的板级 `.repl` 里 `using "platforms/cpus/stm32h743.repl"` 后追加）：

  ```text
  i @ICM42688P.cs            # 运行时编译并加载 C# 模型
  icm1: Sensors.ICM42688P @ i2c1 0x68
  ```

- **数据从哪来**：直接复用 MATLAB `matlab_sim/`（现已重组为 `sim/`）里的 `ahrs_data_gen.m` 生成合成 IMU 轨迹，转成 Renode 能喂的采样序列，用 Python hook 定时 `FeedSample(...)`。这样你们**真实 C 固件的 `ins_sensor_manager` → `ins_eskf_15d` 整条 INS 流水线**就能在虚拟 H743 上跑，且输入与 MATLAB 验证同源 → 和 [MATLAB ESKF 算法验证](MATLAB_ESKF算法验证.md) 形成闭环。

!!! tip "这是 Renode 对本项目最大的意义"
    板没到，先用合成数据把「真实固件跑真实算法」这件事验了。

### 路线 C — RESD 数据表直接喂（最快验算法，不建寄存器模型）

Renode 有内置「传感器数据表」机制（RESD，CSV 式 `时间,值` 格式），可把预生成 IMU 样本直接灌给一个传感器外设，**跳过寄存器建模**，专攻算法 / 融合逻辑验证。适合先快速跑通，再补 B 的寄存器保真度。

- 命令示意：`sysbus.sensor LoadSensorSamples @imu_samples.resd`
- 数据同样可由 `ahrs_data_gen.m` 产出。

## 8. 与现有验证体系的关系

```text
        MATLAB SIL（Phase1/2 验算法等价）
                 │  gcc-SIL 已 PASS
                 ▼
        Renode PIL（真实 .axf 跑在虚拟 H743）
                 │
                 ▼
        真板 HIL（SWD + HardFault 分析）
```

- **SIL（PC, gcc）**：已建好 `sim/sil_pc/`，验 C 实现 vs 真值（见 [PC 端 SIL 实战](SIL_PC实战.md)）。
- **PIL（Renode, H743）**：本页目标，验真实固件在 H743 上的可运行性 + 集成正确性。
- **HIL（真板）**：板回后上 SWD + HardFault 分析器做整机验证（见 [板级 Bring-up 与验证清单](板级BringUp与验证清单.md)）。

> ⚠️ **D-Cache + DMA 注意**：你们在 Keil 里已修过的 `CleanDCache` / `InvalidateDCache` 一致性逻辑，在 Renode 下 **cache 不一定按硬件建模**，同样代码在 Renode 与真板行为可能不同。Renode 里跑通不代表真板 cache 问题消失，反之亦然 —— 这点要在 HIL 阶段再交叉确认。

## 9. 调试与 CI

- **GDB + VS Code**：`machine StartGdbServer 3333` 后，用 `arm-none-eabi-gdb` / `gdb-multiarch` 或 Renode 官方 VS Code 扩展（含 `launch.json` 配置）连上去单步 / 看寄存器。
- **Python hook 追踪**：`SetHookBeforePeripheralWrite` / `SetHookAfterPeripheralRead` 可在访问任意外设时跑 Python，用来打点 DMA / 总线行为、抓「驱动读了哪个寄存器」。
- **确定性 → CI**：同输入同输出，可把 Renode 跑固件 + 断言（如「串口打印 Pass」）接进自动化（参考 Antmicro `cros-ec-tester` 用 Robot Framework 的做法），板没到也能天天跑回归。

## 10. 下一步行动清单（进度同步，2026-08-18）

- [x] 装 Renode（v1.16.1），环境 OK
- [x] 写 `stm32h743.resc` + `stm32h743_pwr.repl` + `stm32h743_pwr.py`（§6.1 三件套），**直接用真实固件 `.axf` 跑通路线 A**（`Machine started`、无 FatalError、无 PWR 警告；76888 B 加载、PC=0x8000395、SP=0x24002B08）
- [ ] **路线 A 收口：确认固件真正跑到 `main()` 并出 printf**（见下方「下一步」）——`Machine started` 只代表 CPU 起来了，不等于进 main；需开对 UART 的 analyzer 看输出
- [ ] 确认 `peripherals` 列出的 H7 外设覆盖度，标记哪些本项目要用但缺模型（若 `start` 后刷 `non existing peripheral` 警告，照 §6.1 `filename:` 桩模式补）
- [ ] 评估路线 B 工作量：先建 **1 个 IMU（ICM-42688P）** 的 C# 寄存器模型，接 `ahrs_data_gen.m` 合成数据，跑通 `ins_eskf_15d` 整链
- [ ] 与 [MATLAB ESKF 算法验证](MATLAB_ESKF算法验证.md) 对齐：用同源合成数据，在 Renode 里复现 att/pos/vel 误差量级，确认「真实固件 == 参考算法」
- [ ] （板回后）HIL 阶段交叉确认 D-Cache + DMA 行为差异

### 当前下一步（路线 A 收口 → 路线 B）

1. **先验证固件真的在跑**：`start` 后开 **printf 实际重定向到的那个 UART** 的 analyzer（本项目 USART3 接的是 UM982，调试控制台大概率是 usart1/2/3 里的某一个，查固件 `fputc`/`_write`/Retarget 重定向确认），看有没有初始化 banner / 心跳打印。
   - 有输出 → 路线 A 验证完成，进入路线 B。
   - **空窗几秒无输出** → 两种可能：(a) 固件卡在别的未建模外设（但 Renode 会刷 `non existing peripheral` 警告，没刷说明不是这个）；(b) **HardFault / 跑飞**。此时开 GDB：`machine StartGdbServer 3333`，用 `arm-none-eabi-gdb` 连 `localhost:3333`，`info registers` / `bt` 看 PC 卡在哪、是不是进了 HardFault Handler。
2. **确认外设覆盖缺口**：`peripherals` 列一遍，对照本项目要用到的（SPI1/2/3/4/6、I2C1/2/3、USART3、TIM4 加热 PWM、ADC1 NTC、FDCAN、BDMA/SRAM4）打勾，缺的标出来——这是路线 B / 后续桩的清单。
3. **进入路线 B（核心价值）**：优先拿 **ICM-42688P**（SPI1，本项目主 IMU）开刀，照 §7 骨架建 C# 寄存器模型 + `ahrs_data_gen.m` 合成数据经 Python hook 定时 `FeedSample`，让真实 `ins_sensor_manager → ins_eskf_15d` 整链在虚拟 H743 上跑起来。

## 参考链接

- 官方站 / GitHub：<https://renode.io> · <https://github.com/renode/renode>
- 文档：<https://renode.readthedocs.io>（Demo、REPL 语法、RESD 传感器数据）
- STM32 平台定义（含 stm32h743.repl）：Renode 安装目录 `platforms/cpus/`
- 传感器 C# 模型参考：`renode-infrastructure/.../Peripherals/Sensors/ADXL345.cs`
- Keil / armclang 产物在 Renode 的坑：`hattmt/renode_devstm32`（GitHub）
- Keil 生成 .axf 实操（**已按此文实测可行**）：<https://blog.csdn.net/weixin_43794311/article/details/153658669>
- CAN / FDCAN 多节点示例（Antmicro 博客，用 stm32h753）：<http://www.antmicro.com/blog/2024/11/demonstrating-can-support-in-renode>
- VS Code 扩展：<http://renode.io/news/introducing-renode-vscode-extension>
