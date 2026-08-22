# 板级 Bring-up 与验证清单（AHRS 航姿板）

> 用途：样片（打样）回来后的「上电 → 点亮 → 逐传感器验证 → 融合输出 → 收口」全流程清单。
> 用法：板子在路上时把**第 1 节**先备好；样片一到，按 2→10 节**逐项打勾**。
> 适用：本项目 STM32H743VIH6 航姿解算板（TFBGA100，有源 24MHz 晶振）。

!!! note "前置结论（来自本项目验证讨论）"
    - **SIL 已在 PC 跑通**：8 路 init 全过、4000 步 0 NaN/Inf、AA55 帧 CRC 全对 → 固件「驱动解析 → ESKF → 协议帧」逻辑闭环已验。
    - 本清单只补 SIL **覆盖不到**的部分：**真硅的 D-Cache/DMA 一致性、SPI 时序、1000 Hz 实时性、电源/焊接/SI**。
    - 顺序原则：**先保活（电源/时钟/SWD），再逐传感器 init，再融合，最后联调 SPI3/FDCAN**。

---

## 1. 上电前准备（板子在路上就能做）

- [ ] **复查板厂文件**：BOM、坐标、丝印、封装（TFBGA100 0.8mm 间距）、极性元件（电解/钽电容、二极管、UM982 模块方向）。
- [ ] **工具就位**：
  - 调试器：ST-Link V3（或 Nucleo 板载 ST-Link 飞线到本板 SWD）。
  - 仪器：万用表、示波器、逻辑分析仪（抓 SPI3/DRDY）、USB-UART 转接（UM982 460800）。
  - 限流直流电源（上电防短路用）。
- [ ] **软件就位**：
  - Keil uVision 工程（15 个手写源已补齐，可全量编译/链接，产物 `.axf`/`.bin`）。
  - ST-Link 驱动 / OpenOCD 备选烧录通道。
- [ ] **资料打印在手边**：
  - 引脚映射表（《引脚映射表_整合版.md》§C）。
  - 《航姿板-底板_SPI3通信协议.md》v2（68B 常驻帧）。
  - 本清单 + SIL 结果基线（姿态真值/CRC 全对）。

---

## 2. 第一次上电（最危险，慢动作）

- [ ] **目视检查**：虚焊、连锡、反向、缺件；尤其 TFBGA100 四角与中心地焊球。
- [ ] **短路测试**：万用表二极管档测 VCC↔GND，确认无短路（**短路绝不上电**）。
- [ ] **限流上电**：电源设 3.3V、限流 ~100mA，缓慢上电，观察电流。
- [ ] **测各电源轨**：
  - 数字 3.3V（MCU / 传感器 IO）
  - VCORE 1.2V（MCU 内核，由内部 LDO 出）
  - 传感器供电（IMU/MAG/BARO 的 3.3V 或 1.8V，依各自 LDO）
  - UM982 供电（3.3V 或 5V，依模块要求）
- [ ] **复位 / BOOT0 电平**正常（BOOT0=0 进用户闪存）。
- [ ] **摸温**：上电 10s 内芯片明显发烫 → 立即断电排查。

> 一切正常才进入调试；任何异常先回到短路/电源/焊接排查，不要急着烧程序。

---

## 3. 连通调试器（SWD）

- [ ] 接 SWDIO / SWCLK / NRST / GND（注意本板 SWD 引脚，见引脚映射表）。
- [ ] Keil → `Options for Target` → `Debug` → 选 `ST-Link Debugger` → `Settings` → 确认识别到芯片（H743 器件 ID）。
  - 能识别 = MCU 上电正常 + **HSE 24MHz 有源晶振起振** + 内核跑起来了。
  - 识别不到 → 查电源 / 晶振 / NRST / 焊接 / SWD 接线。
- [ ] 先**只读不烧**，连上后看芯片温度/ID 稳定，再继续。

---

## 4. 第一次下载与启动

- [ ] Keil `Download`（或 ST-Link Utility / OpenOCD）烧 `.axf`。
- [ ] **不要直接 Run**：先在 `main()` 入口设断点，单步确认 `SystemInit` → 时钟树 → `MPU_Config` → D-Cache 使能 通过。
- [ ] 跑起来后看是否进入 `HardFault_Handler`（抓法见 [验证策略总览 §L2 / Keil Simulator](#) 与下方第 9 节）。
- [ ] 若 HardFault，优先查：栈溢出（加 `startup` 里 `Stack_Size`）、未初始化指针、除零、非对齐访问。

---

## 5. 固件层验证（逐传感器 init）

SIL 已验逻辑，这里验**真硅总线**。对照 SIL 的 `err_mask`，每路 init 后打印 WHOAMI/PROM：

| 总线 | 器件 | 验证点 | 期望 |
|---|---|---|---|
| SPI1 | ICM-42688P | 读 `0x75` WHOAMI | `0x47` |
| SPI6 | IIM-42652 | 读 `0x75` WHOAMI | `0x6D` |
| SPI4 | BMI088 | accel `0x00`=`0x1E`；gyro `0x00`=`0x0F` | 两值都对 |
| I2C1 | IST8310 | 读 `0x00` WAI | `0x10` |
| I2C2 | BMP581 | 读 `0x01` CHIP_ID | `0x50` |
| I2C3 | MS5611 | 读 PROM 8 字（无 WHOAMI，靠非全 0/全 FF） | 合理系数 |
| SPI2 | FRAM | **暂未驱动**（仅预留总线上下文） | — |
| USART3 | UM982 | 收到 `$GNRMC` / `$GNGGA`（460800） | 正常 NMEA |

- [ ] 每路失败 → 查对应总线：SPI 片选/时钟极性(CPOL/CPHA)、I2C 上拉/地址/速率、UART 波特率/接线/电平。

---

## 6. 融合与输出验证

- [ ] **静置板子**：ESKF 输出姿态应稳定（roll/pitch≈0，yaw 缓慢漂移），无 NaN/Inf（串口或 AA55 帧里看）。
- [ ] **缓慢转动板子**：姿态跟随运动，无跳变、无发散。
- [ ] **SPI3 从机输出**：底板（或逻辑分析仪）读 68B 常驻帧，`CRC16-CCITT` 通过；`DRDY=PC5` 有脉冲。
  - 前提：`.ioc` 已把 SPI3 改为 **SLAVE + Mode3**（用户已于 2026-08-17 在 CubeMX 改好，Keil 显示 `SPI_MODE_SLAVE` + `SPI_PHASE_2EDGE`）。
- [ ] **FDCAN**：若有 CAN 收发器，验 AA55 帧能发出（FDCAN 路径在固件中保留为备份）。

---

## 7. 本项目特有查缺（来自已知坑）

- [ ] **D-Cache / DMA 一致性（必查）**：
  - `unicore_um982.c` 的 `d->dma_buf` 由 `DMA2_Stream6` 写入，CPU 在 IDLE 中断里读；`main.c` 的 `MPU_Config` 只有 4GB 默认区、**无专划 non-cacheable DMA 区**。
  - 若 D-Cache 开启且 `dma_buf` 落在可缓存 RAM → CPU 可能读到陈旧 NMEA 数据。
  - 解法（二选一，详见第 8 节）：①MPU 划 non-cacheable 区专放 DMA 缓冲；②IDLE IRQ 读 `dma_buf` 前加 `SCB_InvalidateDCache_by_Addr()`。
- [ ] **SPI3 主从方向**：已从 SLAVE 实现；板回确认 `MISO(PC11)` 出数（本板出 → 底板入）。不出数先查 `.ioc` 的 SLAVE+Mode3 是否生效。
- [ ] **SPI6 BDMA / SRAM4**：IIM-42652+RM3100 走 APB4，当前驱动是**轮询**（`HAL_SPI_TransmitReceive`），未用 BDMA；将来上 DMA 才需补 SRAM4(0x38000000) 区与 BDMA 配置。
- [ ] **1000 Hz 实时性 / 栈深度**：ESKF+浮点，默认栈可能偏紧；若 HardFault，先加 `startup` 里 `Stack_Size`。
- [ ] **加热 PWM（PD14/TIM4_CH3）+ NTC（PA1/2/3）**：`ins_thermal` 的 NTC 参数（10k/B3950/10k/45℃）为占位，需按实物标定。
- [ ] **底板 SPI3 主机侧 68B 帧解析**：航姿板从机已就绪；若另做底板固件，需按协议文档实现主机解析。

---

## 8. 实操：如何确认是否踩到 D-Cache 一致性坑

- [ ] 上电跑 UM982，对比「DMA 收到的原始 NMEA 字节」与「CPU 解析到的字符串」是否一致。
- [ ] 偶发丢字节 / 错位 / 校验失败 → 高度疑似缓存一致性。
- [ ] 在 `um982_uart_irq_handler` 读 `dma_buf` **之前**加：
  ```c
  SCB_InvalidateDCache_by_Addr((uint32_t*)d->dma_buf, sizeof(d->dma_buf));
  ```
  再加回比一次：若加上就正常 → 确认是缓存问题，把该行固化。
- [ ] 更彻底的做法：MPU 划一块 non-cacheable 区专放 `dma_buf` 与 `board_spi3_slave` 的 `g_dma_buf`，从根上避开。

---

## 9. L2 指令级仿真（不依赖板子，现在就能做）

- [ ] **⚠️ Keil 内置 Simulator（Use Simulator）对 STM32H7 不可用（2026-08-17 实测纠正）**：`Use Simulator` 会抛 `error 65: access violation at 0x5802480C`（PWR/RCC 未建模）；`MAP` 命令只能屏蔽报错，之后 `SystemClock_Config` 的 `while(时钟未 ready){}` 因读到全 0 而**死循环**（CPU 空转、按钮变灰、卡在 system_stm32h7xx.c）。**结论：此路走不通，不要把时间耗在调 Keil Simulator 上。**
- [ ] L2 指令级仿真（二选一，替代 Keil Simulator）：
  - **（推荐）真板回来后 SWD + HardFault 分析器**：最可信，直接抓真芯片上的软件崩（空指针/栈溢出/坏函数指针）。
  - **Renode** 建模 STM32H743 跑真 `.elf`（对 H7 建模比 Keil Sim 完整，但仍需建模 SPI/I2C 等 7 外设，工作量较大）。
- [ ] 软件/算法/协议层验证已由 **gcc-SIL**（见 [SIL_PC实战](SIL_PC实战.md)）覆盖并通过，无需仿真器。

---

## 10. 收尾

- [ ] 全过 → 进入 HIL / 与底板联调（SPI3 主机侧、CAN 闭环）。
- [ ] 任何异常 → 记日志，区分：
  - **逻辑错**（应回 SIL 复现/修）→ 算法/协议层。
  - **硬件错**（时序/电源/SI/缓存）→ 真硅层，对照本节第 7、8 节。
- [ ] 把本次 bring-up 的「踩坑与对策」回填本清单，作为下版硬件的预习。

---

## 附：普适 STM32H7 Bring-up 速查（脱离本项目也适用）

1. **电源 → 时钟 → SWD → 闪存 → 外设** 严格分层，前一层不稳不进后一层。
2. **先保活，再保功能**：能连 SWD、能烧录、能跑到 main，比任何传感器读数都重要。
3. **D-Cache 是 H7 头号隐形坑**：凡 DMA 缓冲被 CPU 读，要么放 non-cacheable 区，要么读前 `SCB_InvalidateDCache_by_Addr`，写后 `SCB_CleanDCache_by_Addr`。
4. **HardFault 先查栈**：H7 默认栈不一定够 1000Hz+浮点+RTOS，优先加 `Stack_Size`。
5. **每个外设先 WHOAMI/PROM 再功能**：能读到正确 ID 才说明总线（CS/地址/速率/极性）基本对。
