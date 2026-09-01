---
category: 生活与兴趣
tags: [复刻, 硬件, CC表, SWD, 烧录]
---

# 合宙 CC 表复刻

> 零散记录，非系统教程。

## 烧录踩坑（2026-08-23）

第一次用 SWD 烧录（之前都是串口或 USB 烧录），对固件烧录流程还不熟。实测结论：

- **ST-Link V2 可以烧录 CC 表上的 STM32G0 和 AIR32F1**（后者识别为 STM32F1）。
- 过程中发现创芯工坊的 **Power Writer**，可烧录上万种 MCU 设备，已购入，待回来测评验证。

> 连接成功后，无论 Air9000 设备还是上位机，显示的都是电路纹波随机值，可以忽略。

## 参考

- <https://blog.csdn.net/qq_46041394/article/details/146901689>
- <https://zhuanlan.zhihu.com/p/1895061368710882783>
