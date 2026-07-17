# 嵌入式开发

这里记录我的嵌入式开发学习笔记，重点聚焦 **BLE MCU / SoC** 的学习与项目实践。

## 学习路线图

```mermaid
graph LR
    A[BLE MCU 学习] --> B[国产路线: 沁恒 CH58x]
    A --> C[Nordic 路线: nRF52/53]
    B --> D[CH582M 实战]
    C --> E[nRF52840 / nRF5340 进阶]
    D --> F[项目实践]
    E --> F
```

## 当前进度

| 平台 | 芯片 | 状态 | 备注 |
|------|------|------|------|
| 沁恒 WCH | CH582M | 🚧 学习中 | RISC-V + BLE 5.3 |
| Nordic | nRF52840 / nRF5340 | ⏳ 计划中 | ARM Cortex-M + BLE 5.3/5.4 |

## 笔记目录

- [CH582M 特性与概览](BLE%20MCU/CH582M%20特性与概览.md)

---

> 💡 **学习资源**
> - 沁恒官网：[https://www.wch.cn](https://www.wch.cn)
> - Nordic DevZone：[https://devzone.nordicsemi.com](https://devzone.nordicsemi.com)
> - BLE 核心规范：[Bluetooth SIG](https://www.bluetooth.com/specifications/)
