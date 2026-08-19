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
| `include path/to/x.resc` (`i`) | 加载脚本（`.resc` 或 `.py` 均可，路径**不加 `@`**） |
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

> 2026-08-18 实测：用 Keil 出的真实固件 `.axf`（76888 B）加载，**`Machine started`、无 FatalError、无 PWR 警告刷屏**，路线 A 最小 MCU 系统立住。2026-08-19 用 GDB 确认固件**真的跑进 `main()`**（见下方「收口确认」），路线 A 正式收口。下面是能直接抄的最终三件套与踩坑。

**成功日志（节选，2026-08-18 加载固件）：**

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

**收口确认（2026-08-19，GDB `arm-none-eabi-gdb` 连 `machine StartGdbServer 3333`）：**

```text
(gdb) target remote localhost:3333
Reset_Handler () at startup_stm32h743xx.s:243
(gdb) break main
Breakpoint 1 at 0x800e810: file ../Core/Src/main.c, line 110.
(gdb) break HardFault_Handler
Breakpoint 2 at 0x80003a2: HardFault_Handler. (2 locations)
(gdb) continue
Continuing.

Breakpoint 1, main () at ../Core/Src/main.c:110
110     {
```

> 命中 `main` 即证明：固件跑过了 `SystemInit` 时钟初始化（含此前卡死的 PWR `ACTVOSRDY` 死等），真正进入应用主循环，**路线 A 收口**。注意本项目固件**无 `printf`**（`ins_output` 的 AA55 帧输出当前 `uart = NULL` 未接），所以 Renode 的 UART analyzer 看不到任何打印——收口证据靠的就是 GDB 命中 `main`，不是看串口。

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
    initable: false
    filename: "D:/01_Job/Project/AHRS-Board/software/Renode/stm32h743_pwr.py"
```

`stm32h743_pwr.py`（**必须纯 ASCII**，且必须是 `request` 处理器模型，见下方坑⑤）：

```python
# AHRS-Board PWR stub (PythonPeripheral request-handler model)
# Official stm32h743.repl lacks PWR @0x58024800. Firmware SystemInit
# dead-waits on PWR VOSRDY / ACTVOSRDY flags. Return 0xFFFFFFFF for every
# read so all "ready" bits are set and the firmware runs past clock init.
# NOTE: Renode PythonPeripheral scripts are per-access handlers, NOT modules
# with ReadDoubleWord() functions. Use the global 'request' object.
if request.IsInit:
    pass
elif request.IsRead:
    request.Value = 0xFFFFFFFF
else:
    pass
```

!!! warning "本次踩的四个坑（按出现顺序，全是 Renode 语法细节）"
    1. **`script:` 内联不能放多 `def`** —— `Python.PythonPeripheral` 的 `script:` 是内联代码字符串，Renode 用 **IronPython（Python 2 语义）** 解析；Python 单行语句列表里 `;` 只能分隔 `small_stmt`（`return`/`pass`/赋值），而 `def` 是复合语句，不能用 `;` 跟在另一语句后 → 第二个 `def` 报 `unexpected token 'def' (Line 1, Column 36)`。**正确做法：用 `filename:` 属性指向独立 `.py` 文件**（Renode 自带样例 `platforms/cpus/imxrt1064.repl` 即用 `filename: "scripts/pydev/ticker.py"` 印证）。
    2. **`.py` 外设文件必须纯 ASCII** —— IronPython 加载 `filename:` 指向的 `.py` 时若含非 ASCII（如中文注释，`\xe6` 是 UTF-8 中文首字节）报 `Non-ASCII character '\xe6' ... but no encoding declared`。最稳 = `.py` 全 ASCII（中文注释改英文）；PEP 263 `# coding: utf-8` 声明也行但要求声明行本身 ASCII 且位于第 1/2 行，不如直接零非 ASCII 省心。
    3. **`.repl` 不支持 `#` 注释**（报 `unexpected '#'`）、不支持 `"""` 多行字符串**（报 `Unterminated string`）**。`script:` 的值也不能用 `@`（那是 Monitor 命令语法，报 `unexpected '@'`）。`.repl` 须零注释、字符串单行。
    4. **`include` / `i` 命令加载 `.resc` 不需要 `@`**（只方法参数 `LoadELF`/`LoadHEX`/`LoadPlatformDescription` 要 `@`）。实测 `i "D:\...\stm32h743.resc"`（带引号、反斜杠）也能成功——引号路径里反斜杠 OK，但 `.repl`/方法参数里仍建议一律正斜杠。
    5. **`Python.PythonPeripheral` 是「每次总线访问都执行的处理器」，不是「定义 `ReadDoubleWord` 函数的模块」**（2026-08-19 实测，路线 A 收口的真正根因，前四坑都解决后仍卡 7 轮就是它）——IronPython 加载 `.py` 后，Renode 把脚本当成一段**在每次读/写外设时执行的处理器**，通过全局对象 `request` 交互：`request.IsInit` / `request.IsRead` / `request.IsWrite` 判断访问类型，读时用 `request.Value = <值>` 给返回值，写时读 `request.Value`。**在模块里写 `def ReadDoubleWord(offset): return 0xFFFFFFFF` 永远不会被调用**，所以读恒定返回 0、固件死等就绪标志不退出。正确写法就是上面的 `.py` 模板（`if request.IsRead: request.Value = 0xFFFFFFFF`）。官方样例 `platforms/pydev/flipflop.py`、`counter.py` 即此模型。
    - ⚠️ **误诊复盘**：曾误以为是 `initable` 门控（`initable: true` 未 `EnsureInit` 前读返回 0），并据此试过 `sysbus.pwr EnsureInit`——但本机 Renode 1.16.1 里 `PythonPeripheral` 没有 `Init` 方法（叫 `EnsureInit` 但调了也无用）。真正问题是脚本模型理解错，**与 `initable` 无关**；最终 `.repl` 写 `initable: false` 仅作显式声明，加载即激活。

!!! tip "PWR 桩为什么能跳过死等"
    官方 `stm32h743.repl` 未建 `PWR(0x58024800)`，固件 `SystemInit` 时钟初始化死等 `PWR->VOSRDY` 就绪标志；桩对**所有读返回 `0xFFFFFFFF`**（"所有标志就绪"），固件以为 VOSRDY 已置位就跳出死等继续跑。这是 hack 不是硬件精确——后续想细修可按真实 `PWR` 寄存器（CR1/CSR1 等）让对应位返回真实值。若你用的 Renode 版本已自带 `STM32.PWR` 真实模型，可直接换 `pwr: STM32.PWR @ sysbus 0x58024800`，不必用 Python 桩。

### 6.2 PB1 心跳可视化与 Renode LED 模型局限（2026-08-19 实测）

固件 `main.c:420-422` 自带 PB1 心跳：`if ((loop_count++ % 1000) == 0) HAL_GPIO_TogglePin(LED_STATUS_GPIO_Port, LED_STATUS_Pin);`（`LED_STATUS = PB1`，约 1 Hz 翻转）。**无需改固件即可在 Renode 里看「板子在 blink」**。

**`.repl` 接法（已验证正确）：**

```text
status_led: Miscellaneous.LED @ gpioPortB 1
```

`peripherals` 树里显示为 `gpioPortB` 的**子外设** `└── status_led (LED) Address: 1`，证明接法 100% 正确（官方 `nucleo_h753zi.repl` 同款语法 `GreenLED: Miscellaneous.LED @ gpioPortB 0`）。

!!! warning "两个查询 / 模型坑（2026-08-19 实测）"
    - **坑⑥：LED 是子外设，monitor 须用全路径查** —— 裸 `status_led State` 报 `No such command or device`；正确写法是 `gpioPortB.status_led State`，`watch` 也必须带引号 + 刷新毫秒：`watch "gpioPortB.status_led State" 500`（漏引号报 `Bad parameters`）。
    - **坑⑦：Renode 1.16.1 的 `STM32_GPIOPort` 不会把引脚输出翻转传播给挂在其下的 `LED` 子外设** —— 即使固件真在翻转 PB1，`gpioPortB.status_led State` 也**始终 `False`**。实测：手动 `sysbus WriteDoubleWord 0x58020414 0x2/0x0` 写 ODR（此时 PB1 还是输入模式，更不可能翻）、以及固件运行时，LED 都不翻。这是 Renode 该版本 **GPIO→LED 传播建模的短板**，**不是 `.repl` 写错**，也**不影响路线 A 收口**（见下方「心跳的硬证明」）。

**心跳的硬证明（不依赖 LED 模型，推荐）：** 直接看 GPIOB 输出寄存器 ODR 的 bit1 翻转。

GPIOB 寄存器偏移速查（base `0x58020400`）：

| 寄存器 | 偏移 | 说明 |
|---|---|---|
| MODER | 0x00 | 引脚模式（0b01=输出，HAL_GPIO_Init 设） |
| OTYPER | 0x04 | 输出类型 |
| OSPEEDR | 0x08 | 速度 |
| PUPDR | 0x0C | 上下拉 |
| IDR | 0x10 | 输入数据 |
| **ODR** | **0x14** | 输出数据（PB1 = bit1） |
| **BSRR** | **0x18** | 置位/复位（HAL_GPIO_TogglePin 走它；低 16 位 BS、高 16 位 BR） |

Renode monitor 操作：

```text
start                              # 让固件跑（配置 PB1 为输出 + 进循环）
watch "sysbus ReadDoubleWord 0x58020414" 300
```

盯着返回值 bit1（即 `值 & 0x2`）：在 `0x…0` 与 `0x…2` 之间跳 → 固件确实在翻转 PB1 = 心跳铁证。

**实测结论（2026-08-19）**：`ReadDoubleWord 0x58020414` 在 **`0x00000080` ↔ `0x00000082`** 之间跳变（bit1 翻转）→ **固件心跳确认，路线 A 彻底坐实**。LED 恒 False 即上方坑⑦，可忽略，改用 ODR bit1 翻转即可。

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
- [x] **路线 A 收口：GDB 确认固件跑到 `main()`**（2026-08-19）——`Machine started` 只代表 CPU 起来了；本项目固件无 `printf`，所以靠 GDB 命中 `Breakpoint 1, main () at main.c:110` 确认，而非看串口。已证固件跑过 PWR 死等进入主循环。踩坑 7 轮的真正根因 = `Python.PythonPeripheral` 是 `request` 处理器模型（非 `def ReadDoubleWord` 模块），见 §6.1 坑⑤。
- [x] **路线 A 冒烟测试通过**（2026-08-19 上午，用户贴 GDB 实测）：`continue` 反复命中 `main.c:299`（`ins_sensor_manager_poll`）、全程无 `HardFault_Handler`，连上时 PC 在 `HAL_ADC_PollForConversion`（已跑过 PWR 死等、在循环里）。`RW_IRAM2 outside ELF segments` 为良性警告（DTCM 段，Renode LoadELF 已整体载入）。固件 `main.c:420-422` 自带 PB1 心跳（`HAL_GPIO_TogglePin(LED_STATUS=PB1)`），故 LED 可视化无需改固件。
- [x] **PB1 心跳 / 心跳可视化确认（2026-08-19）**：固件自带 PB1 心跳无需改；`.repl` 接 `status_led: Miscellaneous.LED @ gpioPortB 1`（`peripherals` 已证挂在 PB1，见 §6.2 坑⑥）。但 Renode 1.16.1 的 `STM32_GPIOPort` **不会把引脚输出传播给挂在其下的 `LED`** → `gpioPortB.status_led State` 恒 `False`（坑⑦，非文件错，见 §6.2）。改用 **ODR 寄存器 bit1 翻转**作硬证明：`watch "sysbus ReadDoubleWord 0x58020414" 300`，实测返回值在 **`0x00000080` ↔ `0x00000082`** 跳变（bit1 翻转）→ **固件心跳确认**。LED 不亮可忽略。
- [x] **外设覆盖缺口已核对**（2026-08-19，交叉核对 `Core/Src` HAL handle 与 Renode `peripherals` 清单，非凭记忆）：SPI1/2/3/6 未建模（仅 spi4）、I2C 从机(IST8310/BMP581/MS5611)未挂（控制器已建）、USART3/TIM4/ADC1/FDCAN1 直接可用。缺口表见本节末「外设覆盖缺口表」。路线 B 第一刀 = SPI1+ICM-42688P（ESKF 核心源，最难）或先 I2C 从机（平缓）。
- [x] **路线 B·I2C 从机建模（mag/baro `valid=1`，2026-08-19）**：平缓第一刀。三个 I2C 从机用 `Mocks.DummyI2CSlave + Python 钩` 落地（`i2c_slaves.py` + `.repl` 三行 + `.resc` 三个 `setup_*`），喂静态合成数据让 IST8310/BMP581/MS5611 的 init 与 read 都成功。验证脚本 `gdb_i2c_check.gdb` 断三个 `valid=1` 行。坑⑧（I2C 从机 `DataReceived`+`EnqueueResponseBytes` 机制、写事务不 enqueue 防 FIFO 污染）见 §12。待用户在 Renode 实测确认。
- [ ] **（下一刀）路线 B·SPI IMU 建模**：建 **ICM-42688P**（SPI1）的 C# 寄存器模型（或 Python SPI 桩），接 `ahrs_data_gen.m` 合成数据，让 `ins_eskf_15d` 整链真正跑融合——Renode 仿真的核心价值点。
- [ ] 与 [MATLAB ESKF 算法验证](MATLAB_ESKF算法验证.md) 对齐：用同源合成数据，在 Renode 里复现 att/pos/vel 误差量级，确认「真实固件 == 参考算法」
- [ ] （板回后）HIL 阶段交叉确认 D-Cache + DMA 行为差异

### 当前下一步（路线 A 已收口 → 进入路线 B）

> **路线 A 已于 2026-08-19 收口**：GDB `continue` 命中 `Breakpoint 1, main () at main.c:110`，证明固件跑过 `SystemInit`（含此前卡死的 PWR 死等）进入主循环；同日再跑**冒烟测试**，`continue` 反复命中 `main.c:299`（`ins_sensor_manager_poll`）、全程无 `HardFault_Handler`，确认循环持续运转。本项目固件无 `printf`（`uart = NULL`），故收口证据是 GDB 命中、而非串口打印。

1. **（已用 GDB 完成，记录备查）验证固件进 main + 冒烟测试**：`machine StartGdbServer 3333` + `arm-none-eabi-gdb` 连 `localhost:3333`，`break main` / `break main.c:299` / `break HardFault_Handler` / `continue`；反复命中 `main.c:299` 且无 HardFault = 固件活着。本项目无 `printf`，UART analyzer 看不到输出属正常。深度验证脚本见 `software/Renode/gdb_depth_check.gdb`。
1.5. **（已完成）PB1 心跳可视化 / 心跳硬证明**：固件 `main.c:420-422` 已有 `HAL_GPIO_TogglePin(LED_STATUS=PB1)` 心跳（零固件改动）；`.repl` 已加 `status_led: Miscellaneous.LED @ gpioPortB 1`（接法正确，见 §6.2 坑⑥）。但 Renode 1.16.1 的 GPIO→LED 不传播输出 → `status_led State` 恒 False（坑⑦，非文件错）。**改用 ODR bit1 翻转作心跳硬证明**：`watch "sysbus ReadDoubleWord 0x58020414" 300` 看 bit1 跳变，实测 `0x80↔0x82` → 固件心跳确认。详见 §6.2。
2. **确认外设覆盖缺口**：`peripherals` 列一遍，对照本项目要用到的（SPI1/2/3/4/6、I2C1/2/3、USART3、TIM4 加热 PWM、ADC1 NTC、FDCAN、BDMA/SRAM4）打勾，缺的标出来——这是路线 B / 后续桩的清单。（已完成，缺口表见本节末。）
3. **路线 B·I2C 从机（平缓第一刀，已完成建模）**：IST8310/BMP581/MS5611 用 `Mocks.DummyI2CSlave + Python 钩` 建模，`valid=1` 机制验证见 §12、验证脚本 `gdb_i2c_check.gdb`。待 Renode 实测确认。
4. **路线 B·SPI IMU（下一刀，核心价值）**：建 **ICM-42688P**（SPI1，本项目主 IMU）寄存器模型（C# 或 Python SPI 桩）+ `ahrs_data_gen.m` 合成数据，让真实 `ins_sensor_manager → ins_eskf_15d` 整链在虚拟 H743 上跑融合。

### 外设覆盖缺口表（已核对，2026-08-19）

交叉核对 `Core/Src` 真实 HAL handle（`hspi*`/`hi2c*`/`huart*`/`htim*`/`hadc*`/`hfdcan*`）与 Renode `peripherals` 清单所得。路线 B（传感器在环）须补的即下表「Renode 模型」为 ✗ 的行。

| 总线 | 设备 | Renode 模型 | 路线 B 动作 |
| --- | --- | --- | --- |
| **SPI1** | ICM-42688P（主 IMU） | ✗（仅 spi4 建模） | **实例化 SPI1（`STM32H7_SPI`@0x40013000）+ ICM-42688P 寄存器模型（核心）** |
| SPI2 | FRAM | ✗ | 实例化 SPI2 + FRAM 桩 |
| SPI3 | 底板通信（slave） | ✗ | 自验证非必需，可后补 |
| SPI4 | BMI088 | ✓ 控制器 | 挂 BMI088 模型 |
| SPI6 | IIM-42652 + RM3100 | ✗ | 实例化 SPI6（+BDMA/SRAM4）+ 模型 |
| I2C1 | IST8310 | ✓控制器 / ✗从机 | 挂 IST8310 从机 |
| I2C2 | BMP581 | ✓控制器 / ✗从机 | 挂 BMP581 从机 |
| I2C3 | MS5611 | ✓控制器 / ✗从机 | 挂 MS5611 从机 |
| USART3 | UM982 | ✓ | 直接可用 |
| TIM4 | 加热 PWM | ✓ | 直接可用 |
| ADC1 | NTC（3ch） | ✓（`adcM1S2`@0x40022000 = ADC12） | 直接可用 |
| FDCAN1 | 输出帧 | ✓ | 直接可用 |

> ESKF 的 accel/gyro 核心来源 = SPI1 的 ICM-42688P；磁力计/气压计走 I2C（控制器已建模、只缺从机，Renode 里 I2C 传感器例子更多）。路线 B 第一刀二选一：① 直接攻 SPI1+ICM（最高价值、最难）；② 先做 I2C 从机让 mag/baro `valid`（更平缓、学习曲线友好）。

## 11. 操作速查卡（复盘用，照抄即可）

> 路线 A 全链路「从零跑通 → GDB 收口 → 心跳确认」的完整命令序列。文件见 `software/Renode/`（`stm32h743.resc` / `stm32h743_pwr.repl` / `stm32h743_pwr.py`）。

**A. 启动仿真（Renode Monitor）：**

```text
i "D:/01_Job/Project/AHRS-Board/software/Renode/stm32h743.resc"
machine StartGdbServer 3333
start
```

**B. GDB 收口（另一个终端）：**

```text
arm-none-eabi-gdb D:/01_Job/Project/AHRS-Board/software/STM32H743_AHRS-Board/MDK-ARM/STM32H743_AHRS-Board/STM32H743_AHRS-Board.axf -x D:/01_Job/Project/AHRS-Board/software/Renode/gdb_depth_check.gdb
```

GDB 里反复 `continue`：反复命中 `main.c:299`（`ins_sensor_manager_poll`）、命中 `ins_output_publish`、全程**不碰 `HardFault_Handler`** = 固件活着。

**C. 心跳硬证明（Renode Monitor，不依赖 LED 模型）：**

```text
watch "sysbus ReadDoubleWord 0x58020414" 300
```

返回值 bit1（`值 & 0x2`）在 `0x…0` ↔ `0x…2`（实测 `0x80 ↔ 0x82`）跳 = 固件在 blink = 心跳确认。

**D. 常见踩坑一句话索引：** 见 §6.1（坑①~⑤：script: 内联 def / .py 非 ASCII / .repl `#` 注释 / `i` 不要 `@` / `PythonPeripheral` 是 `request` 处理器）、§6.2（坑⑥：LED 子外设须 `gpioPortB.status_led` 全路径查；坑⑦：Renode GPIO→LED 不传播，LED 恒 False 可忽略，改用 ODR bit1）。

**E. 若 `start` 后刷一堆 WARNING（`non existing peripheral` / `Unknown slave` / `Unhandled write` / `DCacheCleanByMVAToPoCAddress`）：** 全部正常，是「最小 MCU 仿真」必有现象——固件在认真初始化 7 个传感器 + UM982 + SPI3，但 Renode 还没建模它们 → 全扑空、`valid=0`、ESKF 被跳过（循环能干净跑的原因）。`DCacheClean*` 那行反而是好事：证明你们修的 D-Cache 一致性代码在跑。这些 WARNING 不表示仿真坏，传感器模型是路线 B 才补。

**F. 路线 B·I2C 从机验证（mag/baro `valid=1`，见 §12）：**

```text
arm-none-eabi-gdb D:/01_Job/Project/AHRS-Board/software/STM32H743_AHRS-Board/MDK-ARM/STM32H743_AHRS-Board/STM32H743_AHRS-Board.axf -x D:/01_Job/Project/AHRS-Board/software/Renode/gdb_i2c_check.gdb
```

GDB 自动连 `localhost:3333` 并断在 `main`；再 `continue` 跑进主循环第一次 `ins_sensor_manager_poll`：依次命中 `ist_ist8310.c:83` / `bosch_bmp581.c:88` / `te_ms5611.c:93`（三个 `s->valid = 1;` 行）= I2C 从机建模成功、传感器在环机制跑通。若其中某个断点**没命中**，说明对应传感器 init 失败（`SM_ERR_*` 置位 → poll 跳过 read）→ 查 Renode monitor 是否还刷 `Unknown slave at address XX`（从机没挂上）或 WHO_AM_I/CHIP_ID 回值不对。

## 12. 路线 B·I2C 从机建模（平缓第一刀，2026-08-19）

> 目的：先把**磁力计/气压计**做成「在环」，让固件真实驱动读到的 `valid=1`，验证整条「传感器在环」机制跑通。I2C 控制器 Renode 已建模（`i2c1/2/3` 为 `STM32F7_I2C`），只缺从机；且 I2C 从机可用 **`Mocks.DummyI2CSlave` + Python 钩** 平缓落地（不用写 C#）。SPI IMU（ICM-42688P 等）建模更难，留作下一刀。

### 12.1 固件侧协议（读真实代码，非凭记忆）

三个驱动都走 `HAL_I2C_Mem_Read` / `HAL_I2C_Mem_Write`（即「先写寄存器地址 1 字节、再读/写 N 字节」）。`valid` 在各自 `*_read()` 里置 1，且 `ins_sensor_manager_poll` **只在 init 成功（无 `SM_ERR_*`）时才调用 read** —— 所以要让 init 与 read 都成功。

| 传感器 | 总线/地址 | init 关键读 | read 关键读（置 valid） |
| --- | --- | --- | --- |
| IST8310 | i2c1 / 0x0E(14) | WHO_AM_I(0x00) 须 =0x10 | STAT1(0x02) bit0=DRDY；DATAX..Z(0x03) 读 6 字节（小端） |
| BMP581 | i2c2 / 0x47(71) | CHIP_ID(0x01) 须 =0x50 | TEMP_DATA(0x20) 3 字节 + PRESS_DATA(0x1D) 3 字节（小端有符号） |
| MS5611 | i2c3 / 0x77(119) | PROM 8 字（0xA0\|i<<1，各 2 字节大端） | ADC(0x00) 读 3 字节（D1/D2，大端），一阶补偿出 P/T |

> 注意：固件启动实打的从机地址正是 **14 / 71 / 119**（之前 WARNING 里 `Unknown slave at address 14/71/119`），与上面吻合。

### 12.2 Renode I2C 从机机制（官方 `echo-i2c-peripheral.py` + 文档确认）

```text
# .repl 里挂从机（地址可写 0x 十六进制）
ist8310: Mocks.DummyI2CSlave @ i2c1 0x0E
bmp581: Mocks.DummyI2CSlave @ i2c2 0x47
ms5611: Mocks.DummyI2CSlave @ i2c3 0x77

# .resc 里加载 Python（i2c_slaves.py 内部自执行接线，无需再调 monitor 命令）
include "D:/01_Job/Project/AHRS-Board/software/Renode/i2c_slaves.py"
```

Python 钩原理（坑⑧）：`DummyI2CSlave` 在**写相位**触发 `DataReceived`，读相位从 FIFO 取 `EnqueueResponseByte(s)` 入队的数据。handler 签名 `write(self, data)`，`data` 直接是 master 发来的字节列表（官方 `echo-i2c-peripheral.py` 同款）。

- 读事务：master 先写 **1 字节寄存器地址** → `DataReceived([reg])`，`len(data)==1` → 按 `reg` 查表 `EnqueueResponseBytes(该寄存器响应)`。
- 写事务：master 写 **≥2 字节**（reg + 数据）→ `len(data)>1` → **忽略、不 enqueue**。

> **关键技巧（防 FIFO 污染）**：每个从机响应表按寄存器号给**精确长度**的字节，且写事务一律不 enqueue。这样每次读事务前 FIFO 是空的、读相位精确抽走所需字节，不会出现「上一次读的残留字节被下一次读先抽走」的错位。若想偷懒 enqueue 超长，反而会污染后续读——别这么做。

!!! warning "坑⑨：用 `include` 加载 `.py` 的语法陷阱（2026-08-19 实测，路线 B 当场踩）"
    - **(a) `include` 不加 `@`** —— 实测 `include "@D:/.../i2c_slaves.py"` 报 `File does not exist: @D:/.../i2c_slaves.py`：`include`（/`i`）把参数当脚本路径，**不会**像 `LoadELF`/`LoadPlatformDescription` 那样把 `@` 当作「这是文件」标记；`@` 被当成路径字面量的一部分 → 自然找不到。正确写法：`include "D:/.../i2c_slaves.py"`（引号可省，但**绝不能有 `@`**）。`include` 既能加载 `.resc` 也能直接加载 `.py`（Renode 自带测试 `Renesas_DA14592.robot` 即 `include "${echo_i2c_peripheral}"` 加载 `.py`）。
    - **(b) Renode 1.16.1 的 `include` 加载 `.py` 不会把顶层函数暴露成 monitor 命令** —— 实测 `.include "x.py"` 能执行文件、定义函数，但 `.resc` 里再写 `setup_ist8310 "..."` 调它 → 报 `No such command or device: setup_ist8310`（与自带测试的版本行为不同）。**正确做法：让 `.py` 在模块顶层直接调用接线函数（自执行）**，`include` 跑文件时即完成 `DataReceived` 挂钩，`.resc` 里**不要再调**任何 monitor 命令。取外设用 `monitor.Machine[path]`（官方 `echo-i2c-peripheral.py` 同款 API：`dummy = monitor.Machine[path]`），并 `dummy.DataReceived += I2CRegisterSlave(dummy, reg_map).write` 挂钩；本项目 `i2c_slaves.py` 已改为自执行 + `monitor.Machine`/`self.GetPeripheral` 双兜底。

!!! warning "坑⑩：I2C 回包必须是 `IEnumerable<byte>`，不能传 Python `list[int]`（2026-08-19 实测）"
    - **现象**：固件 bring-up 跑一会儿后 Renode 抛 `Error in IEnumeratorOfTWrapper.Current. Could not cast: System.Byte in System.Int32`，栈顶在 `DummyI2CSlave.EnqueueResponseBytes` → `Misc.EnqueueRange[T]`。`Could not cast` 来自 `EnqueueRange<byte>` 遍历 `data` 时对每个元素做 `byte` 强转失败。
    - **根因**：`DummyI2CSlave.EnqueueResponseBytes(IEnumerable<byte> bs)` 形参是 `IEnumerable<byte>`；而我原来传的是 `list(resp)`（Python `list[int]`），IronPython 把它 marshal 成 `IEnumerable<int>`。一旦固件读到命中 `reg_map` 的已知寄存器（WHO_AM_I / CHIP_ID / PROM 等）触发 `EnqueueResponseBytes` 就崩；扫描未命中寄存器时 `resp==[]` 不 enqueue 故先不崩 —— 所以「正常运行一会儿才崩」。
    - **修复**：把回包包成 `bytearray`（`IEnumerable<byte>`）并 `& 0xFF` 兜底：`self.dummy.EnqueueResponseBytes(bytearray(b & 0xFF for b in resp))`。**任何传给 `EnqueueResponseBytes` 的数据都必须是 `bytes`/`bytearray`，绝不可以是 Python `list`。**

!!! warning "坑⑪：Renode 不建模 DWT CYCCNT → `ins_delay_us` 死循环 + 刷屏 WARNING（2026-08-19 实测）"
    - **现象**：仿真跑起来后 monitor 持续刷 `ReadDoubleWord from non existing peripheral at 0xE0001004`（约每 30ms 一次，同 PC）。`0xE0001004` = Cortex-M **DWT->CYCCNT**（周期计数器，偏移 0x004）。这是固件 `ins_time_us()`（`Core/Src/ins_port.c`）读 `DWT->CYCCNT` 做微秒时间戳。
    - **根因**：Renode 1.16.1 的 Cortex-M 模型**不实现 DWT 单元**，读 `0xE0001004` 落到 sysbus 无外设 → WARNING，且返回值恒为 0。这有两个后果：
        1. **刷屏**（仅噪声，固件活着——30ms 节奏说明主循环在跑，不是紧循环）。
        2. **潜在死循环**：`ins_delay_us()` 用 `while ((DWT->CYCCNT - s) < t)` 忙等；`CYCCNT` 恒 0 → `(0-0)<t` 永真 → **死循环**。`te_ms5611.c` 读路径（触发 ADC 后 `ins_delay_us(dl)`，`dl=odly[osr]` 非 0）一旦 I2C 从机接通走到这里就会**卡死**，正好挡在 `te_ms5611.c:93` 的 `valid=1` 断点之前。
    - **修复（固件侧 `AHRS_RENODE_SIM` 开关，`d582a31`）**：仿真构建下 `ins_time_us` 改 `HAL_GetTick()*1000`（ms→us）、`ins_delay_us` 改 `HAL_Delay((us+999)/1000)`（向上取整到 ms）。SysTick 在 Renode 中**已建模**，所以二者都正常工作；正常（非仿真）构建走原 DWT 分支，**零改动**。**Keil 用法**：Project→Options→C/C++→Define 追加 `AHRS_RENODE_SIM`（逗号分隔），重新 Build 出 .axf 再载入 Renode。修后 `0xE0001004` 警告彻底消失（sim 分支不再碰 DWT）。
    - **替代方案（不改固件，需重载 Renode 平台）**：在 `.repl` 里 `dwt_cyccnt: Python.PythonPeripheral @ sysbus 0xE0001004`（size 4，script 定义 `ReadDoubleWord` 自增 counter、`WriteDoubleWord` 置位），让 CYCCNT 递增即可同时消除警告与死循环。该方案对 Renode Python 外设 API 有依赖、未实测，作为不改固件的备选。

### 12.3 文件清单（software/Renode/）

- `i2c_slaves.py` —— `I2CRegisterSlave` 通用类（按 `reg_map` 回数据）+ 三个 `reg_map` + **模块顶层 `_wire()` 自执行**把三从机挂到 `sysbus.i2c1.ist8310` / `sysbus.i2c2.bmp581` / `sysbus.i2c3.ms5611`。**纯 ASCII**（IronPython 对 `#`/中文注释 `Non-ASCII` 报错，见 §6.1 坑②）。加载即生效，无需 monitor 命令。
- `stm32h743_pwr.repl` —— 末尾新增三行 `Mocks.DummyI2CSlave @ i2cN 0x..`（**`.repl` 不支持顶层 `#`**，见 §6.2 坑③）。
- `stm32h743.resc` —— `LoadPlatformDescription` 之后 `include "D:/.../i2c_slaves.py"`（`.py` 自执行接线，无需 monitor 命令；`#` 注释在 `.resc` 里合法，但 `include` 路径**绝不加 `@`**）。
- `gdb_i2c_check.gdb` —— 断 `main` + 三个 `valid=1` 行（ist_ist8310.c:83 / bosch_bmp581.c:88 / te_ms5611.c:93）+ `HardFault_Handler`，自动 `target remote localhost:3333`。

### 12.4 验证判定

- ✅ PASS：GDB `continue` 后依次命中三个 `valid=1` 行，且全程不碰 `HardFault_Handler` → I2C 从机建模成功、传感器在环机制跑通。
- ❌ 某断点未命中：对应传感器 init 失败（`SM_ERR_*` 置位 → poll 跳过 read）→ 查 Renode monitor 是否还刷 `Unknown slave at address XX`（从机没挂上 / 总线名错），或 WHO_AM_I/CHIP_ID 回值不对（改 `i2c_slaves.py` 的 `reg_map`）。

> 当前 `i2c_slaves.py` 给的是**静态合成数据**（仅让 `valid=1`），非时变；mag/baro 数值是合理量级（如 BMP581 25℃/1000hPa）。后续若要喂真实运动学合成数据，可把 `reg_map` 换成由 Python 定时 `EnqueueResponseBytes` 驱动的时变序列（参照路线 B SPI IMU 的 `ahrs_data_gen.m` 思路）。


## 参考链接

- 官方站 / GitHub：<https://renode.io> · <https://github.com/renode/renode>
- 文档：<https://renode.readthedocs.io>（Demo、REPL 语法、RESD 传感器数据）
- STM32 平台定义（含 stm32h743.repl）：Renode 安装目录 `platforms/cpus/`
- 传感器 C# 模型参考：`renode-infrastructure/.../Peripherals/Sensors/ADXL345.cs`
- Keil / armclang 产物在 Renode 的坑：`hattmt/renode_devstm32`（GitHub）
- Keil 生成 .axf 实操（**已按此文实测可行**）：<https://blog.csdn.net/weixin_43794311/article/details/153658669>
- CAN / FDCAN 多节点示例（Antmicro 博客，用 stm32h753）：<http://www.antmicro.com/blog/2024/11/demonstrating-can-support-in-renode>
- VS Code 扩展：<http://renode.io/news/introducing-renode-vscode-extension>
