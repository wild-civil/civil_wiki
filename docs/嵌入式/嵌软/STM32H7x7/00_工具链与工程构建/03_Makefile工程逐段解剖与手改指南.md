---
title: Makefile 工程逐段解剖与手改指南
date: 2026-10-09
tags: [嵌入式, STM32, STM32H7, 工具链, Makefile, CubeMX, binutils, 双核, 手改指南]
---

# Makefile 工程逐段解剖与手改指南

> 芯片：STM32H747 / H757（双核 CM7 + CM4，工程含 `Makefile/CM7/`、`Makefile/CM4/` 两套）
> 教程对应：**1.1 什么是 Makefile** · **1.5 makefile 中的 .mk 文件** · **1.6 编译产物（hex / elf / bin）** · **1.7 程序编译优化选项** · 8.5 把 LVGL 加入编译 · 18 调试技巧
> 所属块：[00 工具链与工程构建](../index.md)｜上一篇：[02 环境搭建与工具链排错](02_环境搭建与工具链排错.md)
> 更新日期：{{ git_revision_date_localized }}

---

## 一句话结论

CubeMX 生成的 Makefile 看着几百上千行，**真正需要读懂的只有 5 个区**：工具链变量、文件清单（源文件/头文件/宏）、编译与链接选项、链接脚本、目标规则。所有手改都发生在"接线层"；而模块内容（LVGL、Modbus、BSP…）应该按教程 1.5 的做法**外置成 `.mk`**——这样 CubeMX 重新生成代码时，要补回的只有几行接线。

## 1. 拿到工程先做三件事

**① 看目录结构**（教程工程的组织方式）：

```
Makefile/CM7/Makefile      ← CM7 主编译规则（编译 / 链接 / 生成 hex、bin）
Makefile/CM7/*.mk          ← 各模块的"文件清单"（lvgl.mk、usb_modbus.mk、bsp_log.mk…）
Makefile/CM4/Makefile      ← CM4 同样一套
Core/  Drivers/  Middlewares/  BSP/  ...
```

**② 列出这个 Makefile 定义了哪些目标**（不同 CubeMX 版本模板不同，先看自己有什么）：

```powershell
Select-String -Path .\Makefile -Pattern '^[A-Za-z_][A-Za-z0-9_.-]*:' | ForEach-Object { $_.Line }
```

**③ 试构建并记录产物**：`make all`（首次单线程）→ 看结尾的 `arm-none-eabi-size` 输出 → 检查 `build/*.elf` 非 0（对应 02 篇 SOP）。

## 2. 逐段解剖（按 CubeMX 模板顺序）

### 2.1 头部注释

模板最前面是生成信息（芯片型号、CubeMX 版本、生成日期）。**这是重生成的观测点**：注释里的日期变了，说明整份 Makefile 被重写过一次（第 4 节的覆盖矩阵就靠它判断）。

### 2.2 工具链变量

| 变量 | 典型值 | 说明 |
|------|--------|------|
| `TARGET` | 工程名 | 产物命名 `$(TARGET).elf / .hex / .bin` |
| `BUILD_DIR` | `build` | 所有 `.o` / 产物集中放这里（见 2.6 的同名坑） |
| `AS` `CC` `LD` `CP` `SZ` | `arm-none-eabi-*` | 汇编 / 编译 / 链接 / objcopy / size |
| `CPU` | `-mcpu=cortex-m7` 或 `-mcpu=cortex-m4` | **双核工程两个 Makefile 的关键差异之一**，决定了给哪个核出机器码 |
| `FPU` | `-mfpu=fpv5-d16 -mfloat-abi=hard` | M7 有双精度 FPU；CM4 侧是单精度版本 |

> ⚠️ 双核工程里 CM4 的 Makefile 若误用 `-mcpu=cortex-m7`（或反之），能编译但运行必炸——对不上号时先查这两行。

### 2.3 优化与调试开关（对应教程 1.7）

```makefile
DEBUG = 1
OPT = -Og
```

- `DEBUG = 1` 时配 `-Og -g3`：面向调试、断点单步体验好；发布版把 `OPT` 改成 `-O2`（速度）或 `-Os`（体积）——各等级的含义、取舍见教程 1.7 与 [GCC 优化选项文档](https://gcc.gnu.org/onlinedocs/gcc/Optimize-Options.html)。
- 改优化等级后**必须全量重编**（`rm -rf build/`）：`.o` 与优化等级不匹配时，链接结果不可信。
- 部分模板用 `ifeq ($(DEBUG),1)` 分支自动切换——**以你生成的文件为准**（`Select-String -Path .\Makefile -Pattern "OPT|DEBUG"`）。

### 2.4 文件清单：手改的主战场

| 变量 | 内容 | 加东西时改哪 |
|------|------|--------------|
| `C_SOURCES` | 所有 `.c` 路径（可跨目录，靠 `vpath` 找） | **加 `.c` 就加一行** |
| `ASM_SOURCES` | `.s` 启动文件 | 一般不动 |
| `C_INCLUDES` | 每条都带 `-I` 前缀 | 加头文件搜索路径 |
| `C_DEFINES` / `AS_DEFINES` | 宏定义（`-Dxxx`） | 条件编译开关 |
| `LDSCRIPT` | `.ld` 链接脚本路径 | 改内存布局/分区时改 |

**接线（教程 1.5 的核心做法）**：模块清单外置成 `.mk`，主 Makefile 只留"接线"——

```makefile
# ① 靠前 include，先拿到变量
include lvgl.mk
include bsp_log.mk

# ② 在 C_SOURCES / C_INCLUDES 里展开
C_SOURCES = ... $(LVGL_SOURCES) $(BSP_LOG_SOURCES) ...
C_INCLUDES = ... $(LVGL_INCLUDES) $(BSP_LOG_INCLUDES) ...
```

```makefile
# bsp_log.mk（模块自己的清单，变量名带 -I 前缀）
BSP_LOG_INCLUDES := -I../../BSP/Log
BSP_LOG_SOURCES  := ../../BSP/Log/bsp_log.c
```

> ⚠️ 教程 1.5 点名的坑：`XXX_INCLUDES` 里已经带了 `-I`，主 Makefile 只能写 `$(XXX_INCLUDES)`，**不能再加 `-I`**，否则展开成 `-I-I../../BSP/Log`，编译直接找不到头文件。
>
> 📌 路径是相对**执行 make 的目录**（`Makefile/CM7/`），所以模块路径通常写成 `../../BSP/...`。

### 2.5 编译 / 汇编 / 链接标志

| 变量 | 典型内容 | 关键点 |
|------|----------|--------|
| `CFLAGS` | `-Wall -fdata-sections -ffunction-sections -MMD -MP`（是否带 MMD 见下） | `-ffunction-sections` 是链接期裁剪的前提 |
| `ASFLAGS` | `$(CPU) $(FPU) -x assembler-with-cpp` | 启动文件要过预处理，所以用 asm-with-cpp |
| `LDFLAGS` | `-T$(LDSCRIPT) -Wl,-Map=$(BUILD_DIR)/$(TARGET).map,--cref -Wl,--gc-sections -specs=nano.specs -specs=nosys.specs` | `--gc-sections` 丢掉未引用段；`-Map` 生成 map 文件；`nano.specs` 用 newlib-nano 省 Flash |

> ⚠️ **头文件依赖要实测**：若 `CFLAGS` 里没有 `-MMD -MP`（`.d` 依赖文件机制），**改 `.h` 不会触发重编**——症状是"改了头文件，行为没变"，此时必须手动删 `build/`。检查：`Select-String -Path .\Makefile -Pattern 'MMD|MF'`；没有就自己加（见第 3 节配方 4）。

### 2.6 目标规则（构建逻辑本体）

模板用三条规则把所有东西串起来（以你生成的文件为准）：

```makefile
# 对象文件：把 C_SOURCES 摊平到 BUILD_DIR 下
OBJECTS = $(addprefix $(BUILD_DIR)/,$(notdir $(C_SOURCES:.c=.o)))
vpath %.c $(sort $(dir $(C_SOURCES)))

all: $(BUILD_DIR)/$(TARGET).elf $(BUILD_DIR)/$(TARGET).hex $(BUILD_DIR)/$(TARGET).bin

$(BUILD_DIR)/%.o: %.c Makefile | $(BUILD_DIR)
	$(CC) -c $(CFLAGS) -Wa,-a,-ad,-alms=$(BUILD_DIR)/$(notdir $(<:.c=.lst)) $< -o $@

$(BUILD_DIR)/$(TARGET).elf: $(OBJECTS) Makefile
	$(CC) $(OBJECTS) $(LDFLAGS) -o $@
	$(SZ) $@            # 打印 text/data/bss

$(BUILD_DIR)/%.hex: $(BUILD_DIR)/%.elf | $(BUILD_DIR)
	$(HEX) $< $@        # = objcopy -O ihex

$(BUILD_DIR)/%.bin: $(BUILD_DIR)/%.elf | $(BUILD_DIR)
	$(BIN) $< $@        # = objcopy -O binary -S

clean:
	$(RM) -rf $(BUILD_DIR)
```

要点：

1. **`notdir` 摊平 + `vpath`**：所有 `.o` 堆在 `build/` 一层。代价是**不同目录下的同名 `.c` 会互相覆盖**（两个 `bsp_log.c` → 同一个 `bsp_log.o`，链接器只看到后者）——报 `multiple definition` 或行为诡异时先查重名。
2. **`Makefile` 是每个 `.o` 的依赖**：改 Makefile 会触发全量重编（这是好事）。
3. `clean` 用 `rm` → Windows 上的坑见 [02 篇坑 1](02_环境搭建与工具链排错.md)。
4. `flash` / `debug` 目标**不一定存在**（取决于模板版本）：用第 1 节的方法列出目标确认；没有就自己加（见配方 4）。

## 3. 手改配方（四件事，最小 diff）

**配方 1：加一个源文件**

```makefile
# 方式 A（临时验证）：直接加进 C_SOURCES
C_SOURCES += ../../BSP/DHT11/bsp_dht11.c
C_INCLUDES += -I../../BSP/DHT11
```
长期做法走教程 1.5 的 `.mk` 外置（第 2.4 节的接线）。

**配方 2：发行版构建**

```makefile
DEBUG = 0
OPT = -Os          # 或 -O2；体积敏感（OTA/Bootloader）用 -Os
```
改完 `rm -rf build/` 全量重编，对比 size 输出的 text+data。

**配方 3：加三方库（LVGL 为例，对照教程 8.5）**

三样缺一不可：`*_SOURCES`（要编的 .c）、`*_INCLUDES`（头文件路径，含 `lv_conf.h` 所在目录）、宏（如 `-DLV_CONF_INCLUDE_SIMPLE`）。按教程做法写成 `lvgl.mk`，主 Makefile 只接线。

**配方 4：补烧录目标 + 头文件依赖（可选，一次加好）**

```makefile
# 头文件依赖（改 .h 触发重编；先确认模板里没有再加）
CFLAGS += -MMD -MP

# 烧录：二选一（把路径/器件改成你的实际值）
flash: all
	STM32_Programmer_CLI -c port=SWD -w $(BUILD_DIR)/$(TARGET).hex -v --start

# 或走 OpenOCD（与 04 篇的 Cortex-Debug 同源；接口/目标脚本按你的探针与型号改）
flash-openocd: all
	openocd -f interface/cmsis-dap.cfg -f target/stm32h7x_dual_bank.cfg \
	  -c "set DUAL_CORE 1" -c init -c "reset halt" \
	  -c "program $(BUILD_DIR)/$(TARGET).elf verify" -c "reset run" -c shutdown
```

编译产物的含义（elf / hex / bin / map 各自能干什么、什么时候用哪个）教程 1.6 已经讲透，本文不重复——**补两个它没说的判断点**：

- 判断 Flash 占用看 `size` 的 **text + data**（或 `.bin` 大小），不要看 `.elf` / `.hex` 文件大小（含符号与文本编码）；
- `.bin` 不带地址，烧录必须给起始地址（`0x08000000`；Bootloader 分区场景按分区方案给）。

## 4. 重新生成覆盖矩阵（待实测 → 填表）

CubeMX 改完 `.ioc` 重新 Generate Code 后，哪些手改会丢？**下表按"生成物 / 非生成物"分类，实测定稿**：

| 文件 | 来源 | 重生成后 | 对策 |
|------|------|----------|------|
| `Makefile/CM7/Makefile` | CubeMX 生成 | ❓被覆盖（待实测） | 把必须补回的"接线行"固定成清单（见下） |
| `Makefile/CM7/*.mk` | 手写 | ✅ 保留（非生成物，CubeMX 不碰） | 稳定资产，模块清单都放这里 |
| `Core/Src/*.c`、`Core/Inc/*.h` | CubeMX 生成 | ✅ 仅 `/* USER CODE BEGIN/END */` 区内保留 | 业务代码永远写在保护区内 |
| `Drivers/`、`Startup`、`.ld` | CubeMX 生成 | ❓被覆盖（待实测；`.ld` 有 USER CODE 区？） | 改 `.ld` 前后 `git diff` |
| `.vscode/`、`BSP/` | 手写 | ✅ 保留 | — |

> 📌 **接线行清单**（重生成后的固定补回动作，10 行以内）：`include *.mk` 若干行 + `C_SOURCES`/`C_INCLUDES` 里的 `$(XXX_SOURCES)` / `$(XXX_INCLUDES)` 引用 + 自定义 `flash` 目标 + `CFLAGS += -MMD -MP`。
>
> 📌 **让 git 帮你做这件事**：`.ioc` 与工程一起提交——重新生成后 `git diff` 一眼就能看出被覆盖了什么、要补回什么（这也是本系列用文本工程的理由之一）。

## 5. 报错 → Makefile 定位口令

| 报错 | 大概率原因 | 先看哪 |
|------|-----------|--------|
| `Nothing to be done for 'all'` | 目标已存在且比源文件新（残留 0 字节产物） | `build/` 是否有旧文件（02 篇坑 2） |
| `input file 'xxx.elf' is empty` | 上次失败残留 | 同上，删 `build/` |
| `No rule to make target 'xxx.o'` | `C_SOURCES` 里的路径写错 / `vpath` 找不到 | 该行路径是否相对 `Makefile/CM7/` |
| `multiple definition of ...` | 同名 `.c` 摊平后 `.o` 覆盖 | 是否有重名源文件（2.6 要点 1） |
| `ld: ... .ARM.extab ... non constant or forward reference` | `.ld` 语法 vs binutils 版本 | 02 篇第 3 节 |
| 改了 `.h` 行为没变 | 没有 `-MMD` 依赖机制 | 2.5 节实测项 |

## 6. 待实测清单（跑完回填本文）

- [ ] 主 Makefile 重生成后：`include *.mk` 与 `$(XXX_SOURCES)` 是否还在？（决定"接线行清单"多长）
- [ ] `CFLAGS` 是否自带 `-MMD -MP`？
- [ ] 模板有没有 `flash` / `debug` 目标？用什么工具？
- [ ] `DEBUG/OPT` 是 `ifeq` 分支还是两个独立变量？
- [ ] `.ld` 被重生成时是否保留手改（有无 USER CODE 区）？
- [ ] `size` 的 text+data 与 `.bin` 大小差多少（验证"bin 接近真实固件"）

## 7. 关联与参考文献

- 上一篇：[02 环境搭建与工具链排错](02_环境搭建与工具链排错.md)｜下一篇：[04 调试与烧录链路（Cortex-Debug 从零配置）](04_调试与烧录链路.md)
- [01 CubeMX 五种工程形态对比](01_CubeMX五种工程形态对比.md)｜[块首页](../index.md)（篇目清单 + 环境基线表）

**参考文献**

- [GNU Make 手册](https://www.gnu.org/software/make/manual/)——变量赋值（`=` / `:=` / `+=`）、自动变量（`$@` `$<`）、模式规则、`vpath`、`include` 语义
- [GCC 优化选项（-O 等级与 -g）](https://gcc.gnu.org/onlinedocs/gcc/Optimize-Options.html) · [GCC 调试信息选项](https://gcc.gnu.org/onlinedocs/gcc/Debugging-Options.html)
- [GNU binutils — ld 链接脚本语法](https://sourceware.org/binutils/docs/ld/) · [GNU objcopy（`-O ihex` / `-O binary`）](https://sourceware.org/binutils/docs/binutils/objcopy.html)
- [UM1718：STM32CubeMX 用户手册（工程生成与重生成行为）](https://www.st.com/resource/en/user_manual/um1718-stm32cubemx-for-stm32-configuration-and-initialization-c-code-generation-stmicroelectronics.pdf)
- 教程：[1.1 什么是 Makefile](https://i1ggz3h8own.feishu.cn/wiki/QHU6wyUkuiYeajknjHccwiJunag#PV5SdvtifoHtpdxxa0GchsUQnVe) · [1.5 makefile 中的 .mk 文件](https://i1ggz3h8own.feishu.cn/wiki/QHU6wyUkuiYeajknjHccwiJunag#KqTqdW396oAc6yxSLYMc2tN6nEb) · [1.6 编译产物](https://i1ggz3h8own.feishu.cn/wiki/QHU6wyUkuiYeajknjHccwiJunag#DfZ0dXR6UoIsPOxJoK0chB6LnVe) · [1.7 优化选项](https://i1ggz3h8own.feishu.cn/wiki/QHU6wyUkuiYeajknjHccwiJunag#Bm6Hd25CRoDRlixFWOAc3sann5d)