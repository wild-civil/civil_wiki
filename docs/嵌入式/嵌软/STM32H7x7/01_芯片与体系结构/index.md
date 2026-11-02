---
title: 芯片与体系结构
date: 2026-10-10
tags: [嵌入式, STM32, STM32H7, H747, H757, 双核, 内存布局, MPU, Cache, 时钟树, 启动流程]
---

# 01 芯片与体系结构

> 所属系列：[STM32H7x7 学习系列](../index.md)
> 教程对应：第 2 章 双核介绍 · 4.4 内存布局 · 4.5 MPU · 4.6 Cache · 4.10 时钟树 · 4.27 内部 Flash 与 Option Bytes · 4.30 VMA/LMA · 4.31 启动流程
> 更新日期：{{ git_revision_date_localized }}

---

## 1. 这个块解决什么问题

外设能不能跑起来，先决条件是**知道代码和数据在哪**：H7 有 ITCM/DTCM + AXI SRAM + SRAM1~4 + Backup 共 6 块 RAM、双 Bank Flash，Cortex-M7 还带 Cache——所以 DMA 一致性、双核共享内存、Bootloader 分区、程序放 RAM 运行这些话题，全部要先落回内存布局。

**本块是后续三个块的前置**：外设实战（DMA/Cache）、显示（帧缓冲放哪）、Bootloader（分区与 VMA/LMA）。

## 2. 篇目（跟随教程主线，不超前写）

| # | 篇目 | 教程对应 | 状态 |
|---|------|----------|------|
| 01 | 内存布局（ITCM/DTCM/AXI SRAM/SRAM1~4/Backup/双 Bank Flash） | 4.4 | ⏳ 跟到 4.4 时开写 |
| 02 | MPU（区域划分、访问权限、Cache/Buffer/Shareable 属性） | 4.5 | ⏳ |
| 03 | Cache（M7 的 I/D Cache 与 DMA 一致性） | 4.6 | ⏳ |
| 04 | 时钟树（时钟源 / PLL / SYSCLK / HCLK / PCLK / Kernel Clock） | 4.10 | ⏳ |
| 05 | 启动流程与 BOOT 配置（BOOT0 / BOOT_ADD / Option Bytes / 向量表） | 4.31 + 4.27 | ⏳ |
| 06 | 双核架构（CM7/CM4、D1/D2/D3 域、HSEM/IPCC 概览） | 2 | ⏳ |
| 07 | VMA/LMA 与把程序放进 RAM 运行 | 4.30 | ⏳ |
| 08 | H747 与 H757 差异（我的板子） | — | ⏳ |

> 每篇头部标注教程出处；术语与寄存器名一律以 RM0399 为准，教程编号只做导航（教程编号有重复与跳号）。

## 3. 环境与参考基线

- 环境版本：统一记录在 [00 块首页环境基线表](../00_工具链与工程构建/index.md)（不在这里重复）
- 权威文档：**RM0399**（H745/755 & H747/757 参考手册）、**PM0253**（Cortex-M7 编程手册——MPU/Cache/异常模型）、[STM32H7 系列文档中心](https://www.st.com/en/microcontrollers-microprocessors/stm32h7-series/documentation.html)
- 板卡：STM32H757（型号待补，与教程的 H747XIH6 差异见第 08 篇）

## 4. 与其他块的边界

| 相关内容 | 归属 | 理由 |
|----------|------|------|
| 工具链 / 构建 / 调试链路 | `00_工具链与工程构建` | 工程层面 |
| 外设寄存器操作、HAL 用法 | `02_外设实战` | 应用层面 |
| `.ld` 链接脚本**语法** | `00` 块副线《启动文件与链接脚本》 | 语法 vs 内存语义（本块讲"段该放哪块内存"，副线讲"脚本怎么写"） |
| BOOT0 硬件设计（下拉/跳线） | `嵌硬`（板级） | 本块只讲"为什么必须接低" |
| Bootloader 分区方案 | `06_系统与工程实践` | 本块提供"内存地图与 VMA/LMA"前置 |