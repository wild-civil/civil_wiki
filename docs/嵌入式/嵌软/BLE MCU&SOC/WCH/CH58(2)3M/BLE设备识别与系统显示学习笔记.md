# BLE 设备识别与系统显示学习笔记

> 整理自 KeyGo 多产品线识别方案讨论（2026-08）。聚焦：设备识别机制、广播字节约束、Appearance 图标、系统蓝牙列表原生支持边界。

---

## 一、设备识别的三层机制（业界通用）

| 层 | 方法 | 是否需连接 | 说明 |
|---|---|---|---|
| Layer 1 | 广播层：Manufacturer Data / 16-bit 服务 UUID / 设备名 | ❌ 不需（扫描即见） | 初筛，快速过滤非自家设备 |
| Layer 2 | GATT 服务枚举（128-bit 私有 UUID） | ✅ 需连接后枚举 | 精筛，防仿冒 |
| Layer 3 | 读特征（Product Model / Model Number String 0x2A24） | ✅ 需连接 | 细分具体型号 |

**关键点**：只要标识放在广播层，就不需要连接；放 GATT 里才需连接。

---

## 二、UUID 长度硬约束（BLE 只有两种）

- **16-bit（2 字节）**：SIG 标准段 `0x1800~0x26FF` + 厂商自定义段 `0xFF00~0xFFFF`。广播占 4 字节，友好。
- **128-bit（16 字节）**：完整 UUID。广播占 18 字节（吃 58% 广播 31 字节上限），只能放 GATT 服务定义（连接后枚举）。
- **❌ BLE 没有 64-bit UUID**，不要幻想。

广播容量：Advertising Data ≤ 31 字节 + Scan Response ≤ 31 字节，合计 ≤ 62 字节。

---

## 三、Manufacturer Data（0xFF）结构

```
[0] AD length
[1] 0xFF (AD type = Manufacturer Specific)
[2-3] Company ID (2字节, SIG 分配的数字, 非字符串)
[4..] 厂商自定义数据 (N字节)
```
- Company ID 是 **SIG 分配的 16-bit 数字**（如 WCH=0x07D7、Nordic=0x0059），**不能直接填 "FYH" 字符串**。
- "FYH" 这类自有标识只能放在 Company ID 之后的**厂商自定义数据区**。

### FYH + ProductType 方案（KeyGo 锁定）
| 字段 | 字节 | 值 |
|---|---|---|
| ProductType | 1 | 0x01=KeyGo / 0x02=Lamp / 0x03=Switch |
| FYH 标识 | 3 | ASCII 'F'(0x46)'Y'(0x59)'H'(0x48) |
| 合计 | 4 | 放厂商自定义区，整条 Manufacturer Data 共 7 字节 |

**识别判据**：App 初筛看 `[FYH]==0x46,0x59,0x48` 且 `ProductType∈{1,2,3}`，**不依赖 Company ID**（换芯片时 Company ID 变也不影响）。

---

## 四、换芯片怎么办（WCH → Nordic）

- Company ID 字段 = 芯片厂 SIG 编号，换芯片自动变（WCH 0x07D7 → Nordic 0x0059）。
- **家族识别不要依赖 Company ID**。用：
  - 方案 A：Manufacturer Data 私有区写 FYH（芯片无关，但无认证）
  - 方案 B（推荐）：16-bit 私有服务 UUID `0xFF00`（烧在 GATT 定义，**与芯片厂无关**，换芯片 UUID 不变）
- 结论：**Company ID = 芯片厂的（随芯片变，忽略）；FYH + ProductType = 自己的（烧固件，芯片无关）**。

---

## 五、GAP Appearance 图标（你观察的车载汽车图标）

- Appearance 是 GAP 层独立字段，与"用什么 GATT 服务"解耦。HID 服务设备可同时设任意 Appearance（钥匙/台灯/开关图标）。
- 常见值：`0x0040` Generic Keyring、`0x0080` Remote Control、`0x0100` Generic Light、`0x0180` Generic Switch。
- **车载显示汽车图标**是车机走经典蓝牙(BR/EDR)音频/电话 profile + 系统对"车载场景"特殊 UI 分支，**不是单纯 Appearance 字段功劳**，纯 BLE 设备享不到这种特权。
- 系统支持现实：
  - **iOS**：系统蓝牙列表基本不渲染第三方 BLE 的 Appearance 图标（只显示名+电量）。
  - **Android**：部分已知 Appearance（HID/音频）可能显示小图标；钥匙/台灯/开关等小众值多回退通用图标。
- 建议：Appearance 按产品线设不同值作**辅助识别维度**（App 可读取辅助分流），但**别依赖系统画图标**。真正展示"这是我的钥匙/灯"靠自家 App UI。

---

## 六、系统蓝牙列表原生支持边界（重要）

| 数据 | iOS 系统列表 | Android 系统列表 | 自家 App |
|---|---|---|---|
| 电量 (Battery Service 0x180F) | ✅ 原生 | ✅ 原生 | ✅ |
| 温度 (Env Sensing 0x181A / 0x2A6E) | ❌ | ❌ | ✅（App 读） |
| 湿度 (0x2A6F) | ❌ | ❌ | ✅（App 读） |
| Appearance 图标（小众值） | ❌（不渲染） | ⚠️（多回退通用） | ⚠️（App 可自定义画） |

**结论**：
- iOS/Android 系统蓝牙设置**只原生显示电量**，不原生显示温度/湿度。
- 0x181A 环境传感服务加了也只会被自家 App 或 nRF Connect 等通用工具读到，系统设置不出现温度行。
- 想"不开 App 也能看温度" → 只能 App widget/通知常驻，或设备加屏幕，系统列表做不到。
- CH582M 无专用温度传感器，可用芯片内部 TSEN 读裸 die 温度（精度低、受负载影响），非环境温度；测环境温度需外接 NTC/数字温感。

---

## 七、韶音/荣耀实测观察（为什么 Unknown Service 全是 128-bit）

- 韶音 OpenRun Pro：`00001100-d102-11e1-9b23-00025b00a5a5`（基于 SIG 经典 UUID base 的派生，老设备常见）+ Google Fast Pair(0xFE2C) + Battery(0x180F) + Generic Attribute(0x1801)。
- 荣耀手环：`c5f0ad48-cc27-48fd-9f67-8dc8e8f4a9cb`、`cc353442-be58-4ea2-876e-11d8d6976366`（厂商随机 128-bit 私有 UUID）。
- "Unknown Service" 只是扫描工具没内置厂商数据库，对厂商本身是确定身份证。
- 厂商识别 = 广播初筛（Manufacturer Data / 16-bit UUID）+ 连接后枚举私有 128-bit UUID + 读 Device Information(0x180A) 的 Model Number String(0x2A24) 或私有 Product ID 特征。

---

## 八、小结（KeyGo 多产品线锁定方案）

1. 广播 Manufacturer Data：`Company ID`（随芯片变，忽略）+ `FYH`(3) + `ProductType`(1)。
2. 广播 16-bit 服务 UUID `0xFF00`（KeyGo 家族；Lamp=0xFF10 / Switch=0xFF20）作第二重初筛。
3. App 初筛：`Manufacturer Data 私有区=="FYH"` 且 `ProductType∈{1,2,3}` → 自家设备。
4. 设备名 `KeyGo-XXXXXX` 仅展示，不参与识别。
5. Appearance 按产品线设不同值辅助识别，但不依赖系统图标。
6. 温度/型号等展示放自家 App，不期待系统蓝牙列表原生渲染。
