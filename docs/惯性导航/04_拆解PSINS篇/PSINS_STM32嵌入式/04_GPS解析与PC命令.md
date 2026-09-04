# GPS 解析与 PC 命令：UBX 协议、小端拼接与命令系统

> 配套源码: [usart.c](../../assets/PSINS_STM32F4xx_Keil4_V2.1/scr/usart.c) / [main.cpp](../../assets/PSINS_STM32F4xx_Keil4_V2.1/scr/main.cpp) (PCCMD) / [stm32f4xx_it.c](../../assets/PSINS_STM32F4xx_Keil4_V2.1/scr/stm32f4xx_it.c) (中断) / [mcu_init.h](../../assets/PSINS_STM32F4xx_Keil4_V2.1/scr/mcu_init.h) (结构体)
> 所属层级: 嵌入式落地篇 · 驱动层 + 衔接层
> 前置依赖: [00 总览与架构](00_总览与架构.md) / [01 中断驱动与数据流](01_中断驱动与数据流.md)
> 学习目标: 读完后你应能回答：
> 1. UBX-NAV-PVT 帧从 `0xB5` 开始到校验和结束共多少字节？payload offset 和 `Rx2_data` index 的换算关系是什么？
> 2. `Rx2_data[30]` 对应 payload 第几字节？存的是什么物理量？
> 3. GPS 速度的 `velD / -1000.0` 为什么除以负数？
> 4. PCCMD 结构体怎么用 4 字节实现"选模式 + 退模式"两种命令？
> 5. GPS_Delay 是怎么算出来的？为什么减 0.25/0.5/0.75？

!!! tip "本篇为什么重要"
    这一篇是**坐标系争议的终结篇**。在 [00 总览第七节](00_总览与架构.md) 中，我们逐行验证了算法层是 ENU。本篇从字节级验证 GPS 驱动层的分量顺序——**结论是：GPS 速度和位置的分量顺序与算法层期望完全匹配，没有 bug**。

!!! warning "修正声明"
    00 篇第七节 7.3 节曾认为 GPS 位置数组存在"经纬度互换 bug"。经本篇字节级重新核对 UBX-NAV-PVT 协议后确认：**payload offset 24 = lon，offset 28 = lat**，代码读取方式正确。00 篇的结论需要修正，本篇 7.4 节给出正确分析。

!!! note "前置阅读链接"
    - 坐标系完整结论：[00 总览 §七](00_总览与架构.md)
    - 传感器原理：[03 传感器原理](../../01_基础篇/03_传感器原理.md)
    - C/C++ 桥接 `*(CVect3*)` 强转：留坑 → [06 C与CPP桥接](06_C与CPP桥接.md)

---

## 一、GPS 数据接收流程

### 1.1 硬件链路

```
u-blox GPS模块 ──USART2(115200,8N1)──► STM32 ──► Rx2_data[120] 缓冲区
                                                └─► GPS_PVT_Decode()
```

| 配置项 | 值 | 源码 |
|---|---|---|
| 波特率 | 115200 | [mcu_init.c L268](../../assets/PSINS_STM32F4xx_Keil4_V2.1/scr/mcu_init.c) |
| 数据格式 | 8N1 (8 bit, 无校验, 1 停止位) | [mcu_init.c L269-273](../../assets/PSINS_STM32F4xx_Keil4_V2.1/scr/mcu_init.c) |
| 触发方式 | RXNE 中断（每字节） | [mcu_init.c L277](../../assets/PSINS_STM32F4xx_Keil4_V2.1/scr/mcu_init.c) |
| GPS 输出 | UBX-NAV-PVT, 4 Hz (250ms/帧) | u-center 配置 |
| 接收缓冲区 | `Rx2_data[120]` + `Rx2_data1[120]` | [mcu_init.c L6](../../assets/PSINS_STM32F4xx_Keil4_V2.1/scr/mcu_init.c) |

### 1.2 USART2 中断接收（帧同步）

[stm32f4xx_it.c L252-294](../../assets/PSINS_STM32F4xx_Keil4_V2.1/scr/stm32f4xx_it.c)：

```c
void USART2_IRQHandler(void)   // GPS input IRQ, 每字节触发
{
    if(USART_GetITStatus(USART2, USART_IT_RXNE) != RESET)
    {
        USART_ClearITPendingBit(USART2, USART_IT_RXNE);
        temp = USART_ReceiveData(USART2);

        Rx2_data1[Length2] = temp;
        Length2++;

        // 帧头检测
        if((Length2 == 1) && (Rx2_data1[0] != 0xb5)) { Rx2_data1[0]=0; Length2=0; }
        if((Length2 == 2) && (Rx2_data1[1] != 0x62)) { Rx2_data1[0]=Rx2_data1[1]=0; Length2=0; }

        // 帧长检测
        if(Length2 == 100)
        {
            if(Rx2_data1[2]==0x01 && Rx2_data1[3]==0x07)  // Class=0x01, ID=0x07 = NAV-PVT
            {
                memcpy(Rx2_data, Rx2_data1, 100);  // 复制到正式缓冲区
                Rx2_complete = 1;                    // 通知 TIM2 中断
            }
            Length2 = 0;
        }
    }
}
```

帧同步三步走：

| 步骤 | 检查内容 | 失败处理 |
|---|---|---|
| ① 帧头首字节 | `Rx2_data1[0] == 0xB5` | 丢弃，Length 归零 |
| ② 帧头次字节 | `Rx2_data1[1] == 0x62` | 丢弃，Length 归零 |
| ③ 帧长+类型 | `Length == 100` 且 `[2]=0x01, [3]=0x07` | 复制到 `Rx2_data`，置 `Rx2_complete=1` |

!!! note "为什么用两个缓冲区？"
    `Rx2_data1` 是"接收缓冲区"——ISR 持续往里写字节；`Rx2_data` 是"解析缓冲区"——只有帧完全接收并通过校验后才 `memcpy` 过去。这样**解析过程不会和接收过程冲突**。

### 1.3 TIM2 中断触发解析

`Rx2_complete` 在 TIM2 中断里被检测（[stm32f4xx_it.c L206-212](../../assets/PSINS_STM32F4xx_Keil4_V2.1/scr/stm32f4xx_it.c)）：

```c
if(Rx2_complete == 1)
{
    Rx2_complete = 0;
    GPS_OK_flag = 1;
    GPS_Delay = MCU_ms_cnt*10 - PPS_cnt;  // GPS 时间延迟 (100μs 单位)
    GPS_PVT_Decode();
}
```

---

## 二、UBX-NAV-PVT 协议结构

u-blox 接收器输出的 UBX-NAV-PVT 帧共 100 字节：

```
偏移  字节    内容
────────────────────────────────────
 0    0xB5    同步字 1
 1    0x62    同步字 2
 2    0x01    Class = NAV
 3    0x07    ID = PVT
 4-5  len     Payload 长度 = 92 (小端 u16)
─────────────────────── Payload (92 字节) ───────────────────────
 6    [0]     iTOW (U4, ms)
 ...
30    [24]    lon (I4, 1e-7 deg) ← 经度
34    [28]    lat (I4, 1e-7 deg) ← 纬度
42    [36]    hMSL (I4, mm)      ← 海平面高度
 ...
54    [48]    velN (I4, mm/s)   ← 北速度
58    [52]    velE (I4, mm/s)   ← 东速度
62    [56]    velD (I4, mm/s)   ← 地速度
 ...
────────────────────────────────────
98    CK_A    校验和 A
99    CK_B    校验和 B
```

!!! note "Rx2_data index → payload offset 换算"
    `payload_offset = Rx2_data_index - 6`
    
    因为 `Rx2_data[0..5]` 是同步字(2B) + Class/ID(2B) + 长度(2B) = 帧头 6 字节，payload 从 `Rx2_data[6]` 开始。

---

## 三、GPS_PVT_Decode() 逐字段解析

[usart.c L7-52](../../assets/PSINS_STM32F4xx_Keil4_V2.1/scr/usart.c) 的完整解析：

### 3.1 小端序 32 位拼接

```c
// 例：iTOW (payload offset 0)
GPS_ITOW = (Rx2_data[9]<<24) + (Rx2_data[8]<<16) + (Rx2_data[7]<<8) + Rx2_data[6];
//                    ↑               ↑               ↑              ↑
//                 byte3(H)       byte2          byte1          byte0(L)
```

UBX 协议所有多字节整数都是**小端序（Little-Endian）**：低字节在低地址。`Rx2_data[6]` 是最低字节，`Rx2_data[9]` 是最高字节。

!!! warning "小端 vs 大端"
    UBX 用**小端**：`(b3<<24)|(b2<<16)|(b1<<8)|b0`，低地址存低位。
    MPU9250 用**大端**：`(H<<8)|L`，低地址存高位。
    两者的拼接方向**相反**，初学者容易混淆。

### 3.2 完整字段映射表

| UBX 字段 | payload offset | Rx2_data index | 类型 | 标度 | 存储位置 | 物理量 |
|---|---|---|---|---|---|---|
| iTOW | 0 | 6-9 | U4 LE | 原值 (ms) | `GPS_ITOW` | GPS 时间戳 |
| lon | 24 | 30-33 | I4 LE | ×DEG1/1e7 | `GPS_Pos[1]` | 经度 (rad) |
| lat | 28 | 34-37 | I4 LE | ×DEG1/1e7 | `GPS_Pos[0]` | 纬度 (rad) |
| hMSL | 36 | 42-45 | I4 LE | /1000 | `GPS_Pos[2]` | 海拔高度 (m) |
| hAcc | 40 | 46-49 | U4 LE | /1000 | `GPS_hAcc` | 水平精度 (m) |
| vAcc | 44 | 50-53 | U4 LE | /1000 | `GPS_vAcc` | 垂直精度 (m) |
| velN | 48 | 54-57 | I4 LE | /1000 | `GPS_Vn[1]` | 北速度 (m/s) |
| velE | 52 | 58-61 | I4 LE | /1000 | `GPS_Vn[0]` | 东速度 (m/s) |
| velD | 56 | 62-65 | I4 LE | /-1000 | `GPS_Vn[2]` | 天速度 (m/s) |
| gSpeed | 60 | 66-69 | I4 LE | /1000 | `GPS_gSpeed` | 地速 (m/s) |
| headMot | 64 | 70-73 | U4 LE | /1e5 | `GPS_Mot` | 航向角 (rad) |
| sAcc | 68 | 74-77 | U4 LE | /1000 | `GPS_sAcc` | 速度精度 (m/s) |
| headAcc | 72 | 78-81 | U4 LE | /1e5 | `GPS_headAcc` | 航向精度 (rad) |
| pDOP | 76 | 82-83 | U2 LE | /100 | `GPS_pDOP` | 精度衰减因子 |
| fixType | 20 | 26 | U1 | &0x07 | `GPS_fixType` | 定位类型 (0=无,2=2D,3=3D) |
| flags | 21 | 27 | U1 | &0x01 | `GPS_flags` | 定位标志 |
| numSV | 23 | 29 | U1 | 原值 | `GPS_numSV` | 可见卫星数 |

### 3.3 速度解析详解

```c
// usart.c L13-18
// velE → GPS_Vn[0] (东速度)
GPS_temp = ((Rx2_data[61]<<24)+(Rx2_data[60]<<16)+(Rx2_data[59]<<8)+(Rx2_data[58]));
gps_Data_value.GPS_Vn[0] = GPS_temp / 1000.0;     // mm/s → m/s

// velN → GPS_Vn[1] (北速度)
GPS_temp = ((Rx2_data[57]<<24)+(Rx2_data[56]<<16)+(Rx2_data[55]<<8)+(Rx2_data[54]));
gps_Data_value.GPS_Vn[1] = GPS_temp / 1000.0;     // mm/s → m/s

// velD → GPS_Vn[2] (天速度 = -地速度)
GPS_temp = ((Rx2_data[65]<<24)+(Rx2_data[64]<<16)+(Rx2_data[63]<<8)+(Rx2_data[62]));
gps_Data_value.GPS_Vn[2] = GPS_temp / -1000.0;    // mm/s → m/s, 取负
```

!!! note "velD / -1000.0 为什么除以负数？"
    UBX 协议的 `velD` 是**地速（Down）**，正值表示向下。而 PSINS 用的是 ENU（天向为正，Up）。所以要把 velD 取负变成 vU（天速度）：
    
    $$v_U = -v_D = \frac{\text{velD}}{-1000.0} \quad [\text{m/s}]$$
    
    除以 `-1000.0` 等价于除以 `1000.0` 再取负，一步到位。

### 3.4 位置解析详解

```c
// usart.c L20-25
// lat → GPS_Pos[0] (纬度)
GPS_temp = ((Rx2_data[37]<<24)+(Rx2_data[36]<<16)+(Rx2_data[35]<<8)+(Rx2_data[34]));
gps_Data_value.GPS_Pos[0] = GPS_temp * DEG1 / 10000000.0;  // 1e-7 deg → rad

// lon → GPS_Pos[1] (经度)
GPS_temp = ((Rx2_data[33]<<24)+(Rx2_data[32]<<16)+(Rx2_data[31]<<8)+(Rx2_data[30]));
gps_Data_value.GPS_Pos[1] = GPS_temp * DEG1 / 10000000.0;  // 1e-7 deg → rad

// hMSL → GPS_Pos[2] (高度)
GPS_temp = ((Rx2_data[45]<<24)+(Rx2_data[44]<<16)+(Rx2_data[43]<<8)+(Rx2_data[42]));
gps_Data_value.GPS_Pos[2] = GPS_temp / 1000.0;              // mm → m
```

其中 `DEG1 = π/180`（[usart.c L3](../../assets/PSINS_STM32F4xx_Keil4_V2.1/scr/usart.c)），把角度转弧度。

> 注意：这里用的是 `hMSL`（payload offset 36，海平面高度），不是 `height`（offset 32，椭球高）。两者差一个大地水准面起伏（geoid undulation），在中国约 -20 ~ +60 m。

---

## 四、坐标系验证（GPS 解析 vs 算法层期望）

### 4.1 速度分量匹配

| GPS_Vn index | 存的值 | CVect3 成员 (强转后) | 算法层期望 | 是否匹配 |
|---|---|---|---|---|
| `GPS_Vn[0]` | velE (东速度) | `gvn.i` | `vE` (东) | ✅ |
| `GPS_Vn[1]` | velN (北速度) | `gvn.j` | `vN` (北) | ✅ |
| `GPS_Vn[2]` | -velD = vU (天速度) | `gvn.k` | `vU` (天) | ✅ |

### 4.2 位置分量匹配

| GPS_Pos index | 存的值 | CVect3 成员 (强转后) | 算法层期望 | 是否匹配 |
|---|---|---|---|---|
| `GPS_Pos[0]` | lat (纬度, rad) | `gpos.i` | `lat` (纬度) | ✅ |
| `GPS_Pos[1]` | lon (经度, rad) | `gpos.j` | `lon` (经度) | ✅ |
| `GPS_Pos[2]` | hMSL (海拔, m) | `gpos.k` | `h` (高度) | ✅ |

!!! success "结论：GPS 驱动层分量顺序与算法层 ENU 约定完全匹配"
    `GPS_Vn[0,1,2] = [vE, vN, vU]` → `CVect3(i,j,k)` 完全对齐。
    `GPS_Pos[0,1,2] = [lat, lon, h]` → `CVect3(i,j,k)` 完全对齐。

!!! warning "修正 00 篇第七节 7.3-7.4 节"
    00 篇曾错误地认为 GPS 位置存在"经纬度互换 bug"。经本篇字节级核对 UBX-NAV-PVT 协议，确认：
    
    - payload offset 24 = **lon**（经度），代码存入 `GPS_Pos[1]` → `CVect3.j = lon` ✅
    - payload offset 28 = **lat**（纬度），代码存入 `GPS_Pos[0]` → `CVect3.i = lat` ✅
    - payload offset 48 = **velN**（北速度），代码存入 `GPS_Vn[1]` → `CVect3.j = vN` ✅
    - payload offset 52 = **velE**（东速度），代码存入 `GPS_Vn[0]` → `CVect3.i = vE` ✅
    
    **速度和位置的分量顺序均正确，不存在"经纬度互换" bug。** 00 篇的 7.3-7.5 节相关结论应以此为准修正。

### 4.3 航迹角初始化验证

[main.cpp L117](../../assets/PSINS_STM32F4xx_Keil4_V2.1/scr/main.cpp)：

```c
kf.Init(CSINS(a2qua(CVT3(0.0, 0.0, atan2(-gvn.i, gvn.j))), gvn, gpos));
```

代入已核实的 gvn.(i,j) = (vE, vN)：

$$
\text{yaw} = \arctan2(-v_E, v_N)
$$

正北 (vE=0, vN>0) → yaw=0；正东 (vE>0, vN=0) → yaw=−π/2。与 `vn2att` 公式（[PSINS.cpp L695](../../assets/PSINS_STM32F4xx_Keil4_V2.1/Psinscore/PSINS.cpp)）一致 ✅。

---

## 五、PC 命令系统：PCCMD 结构体

### 5.1 结构体定义

[main.cpp L8-10](../../assets/PSINS_STM32F4xx_Keil4_V2.1/scr/main.cpp)：

```c
struct PCCMD {
    u16 cmd1, cmd2;
} *pcmd = (PCCMD*)&PC_cmd;
```

`PC_cmd` 是 32 字节的全局数组（[mcu_init.c L24](../../assets/PSINS_STM32F4xx_Keil4_V2.1/scr/mcu_init.c)），通过 USART1 中断接收填充。

`pcmd` 是一个**指针强转**——把 `PC_cmd` 数组的首地址解释为 `PCCMD*`，即把前 4 字节当作两个 `u16`：

```
PC_cmd[0..1] → pcmd->cmd1  (前 2 字节, 小端 u16)
PC_cmd[2..3] → pcmd->cmd2  (后 2 字节, 小端 u16)
PC_cmd[4..31] → 未使用
```

!!! note "语法详解（留坑 → [06 C与CPP桥接](06_C与CPP桥接.md)）"
    `*(PCCMD*)&PC_cmd` 的含义：取 `PC_cmd` 数组首地址 `&PC_cmd`，强转为 `PCCMD*` 类型指针，然后通过 `pcmd->cmd1/cmd2` 访问。本质是**同一块内存的不同类型解释**，C/C++ 中最常用的"零拷贝"桥接手法。

### 5.2 命令体系

| 命令 | 写入方式 | 触发动作 | 帧头 |
|---|---|---|---|
| `cmd2 = 0x1111` | PC 发 4 字节 `0x11 0x11 0x00 0x00` | 进入 Mahony 模式 | `outFrame.head = 0x56aa55aa` |
| `cmd2 = 0x2222` | PC 发 4 字节 `0x22 0x22 0x00 0x00` | 进入 SINSGPS 静态模式 | `outFrame.head = 0x57aa55aa` |
| `cmd2 = 0x3333` | PC 发 4 字节 `0x33 0x33 0x00 0x00` | 进入 SINSGPS 动态模式 | `outFrame.head = 0x58aa55aa` |
| `cmd2 = 0x4444` | PC 发 4 字节 `0x44 0x44 0x00 0x00` | 进入 GPS 配置透传模式 | — |
| `cmd1 = 0xa5a5` | PC 发 2 字节 `0xa5 0xa5` | 退出当前模式，回 switch | — |

### 5.3 主循环 dispatch

[main.cpp L13-28](../../assets/PSINS_STM32F4xx_Keil4_V2.1/scr/main.cpp)：

```c
int main(void)
{
    mcu_init();                                   // 初始化所有硬件
    pcmd->cmd1 = 0; pcmd->cmd2 = 0x1111;          // 默认进入 Mahony 模式
    while(1) {
        switch(pcmd->cmd2) {
            case 0x1111: pcmd->cmd2=0; outFrame.head=0x56aa55aa; Mahony_main(); break;
            case 0x2222: pcmd->cmd2=0; outFrame.head=0x57aa55aa; SINSGPS_static_main(); break;
            case 0x3333: pcmd->cmd2=0; outFrame.head=0x58aa55aa; SINSGPS_moving_main(); break;
            case 0x4444: pcmd->cmd2=0; GPSCFG_main(); break;
        }
    }
}
```

执行流程：
1. `mcu_init()` 后中断已在后台运行
2. 默认 `cmd2 = 0x1111` → 直接进入 Mahony 模式
3. 各模式内部 `while(1)` 循环，每轮检查 `cmd1 == 0xa5a5` 是否要求退出
4. 退出后回到外层 `switch(pcmd->cmd2)`，等 PC 发新命令

!!! note "cmd2 清零的含义"
    进入模式后 `pcmd->cmd2 = 0` 立即清零，防止退出本模式后重复进入。下次进入需要 PC 重新发命令。

### 5.4 GPS 配置透传模式（GPSCFG）

[main.cpp L129-135](../../assets/PSINS_STM32F4xx_Keil4_V2.1/scr/main.cpp)：

```c
void GPSCFG_main(void)
{
    USART1_Configuration(1);  // 切换 USART1 到 115200 (GPS 配置波特率)
    while(1) {
        if(pcmd->cmd1 == 0xa5a5) { pcmd->cmd1=0; break; }
    }
}
```

此模式下：
- USART1 波特率从 460800 切到 115200
- USART2（GPS）收到的数据透传到 USART1（PC）——在 [stm32f4xx_it.c L256-264](../../assets/PSINS_STM32F4xx_Keil4_V2.1/scr/stm32f4xx_it.c) 的 USART2 ISR 中实现
- PC 通过 USART1 发的命令也透传到 USART2（GPS）——在 [stm32f4xx_it.c L304](../../assets/PSINS_STM32F4xx_Keil4_V2.1/scr/stm32f4xx_it.c) 的 USART1 ISR 中实现

> 用途：用 u-blox 的 u-center 软件配置 GPS 模块（改输出频率、改协议、改波特率等）。

---

## 六、GPS 延迟补偿

### 6.1 PPS 时间戳

[stm32f4xx_it.c L164-171](../../assets/PSINS_STM32F4xx_Keil4_V2.1/scr/stm32f4xx_it.c)：

```c
void EXTI0_IRQHandler(void)   // PPS 下降沿中断, 1 Hz
{
    PPS_cnt = MCU_ms_cnt * 10 + TIM2->CNT;  // PPS 时刻 (100μs 单位)
}
```

`PPS_cnt` 精确记录了 GPS 秒脉冲到达时刻，单位 100 μs。

### 6.2 延迟计算

[stm32f4xx_it.c L210](../../assets/PSINS_STM32F4xx_Keil4_V2.1/scr/stm32f4xx_it.c)：

```c
GPS_Delay = MCU_ms_cnt * 10 - PPS_cnt;  // 单位 100μs
```

`MCU_ms_cnt` 是当前系统时间（ms），乘 10 得 100μs 单位，减去 PPS 时刻就是 GPS 数据从 PPS 到被处理的延迟。

### 6.3 输出层延迟修正

[usart.c L100-106](../../assets/PSINS_STM32F4xx_Keil4_V2.1/scr/usart.c)：

```c
outFrame.GPS_delay = GPS_Delay / 10000.0;  // 100μs → s
if(outFrame.GPS_delay < 1.0)
{
    if(outFrame.GPS_delay > 0.75) outFrame.GPS_delay -= 0.75;
    else if(outFrame.GPS_delay > 0.5) outFrame.GPS_delay -= 0.5;
    else if(outFrame.GPS_delay > 0.25) outFrame.GPS_delay -= 0.25;
}
```

为什么减 0.25 / 0.5 / 0.75？

GPS 以 4 Hz 输出（每 250 ms 一帧），`GPS_Delay` 通常在 0 ~ 250 ms 范围内。但有时候接收到的帧属于**上一个 250 ms 周期**，需要减去一个或多个 250 ms：

| 原始延迟范围 | 减去 | 结果 | 含义 |
|---|---|---|---|
| 0 ~ 0.25 s | 0 | 0 ~ 0.25 s | 当前周期帧 |
| 0.25 ~ 0.5 s | 0.25 | 0 ~ 0.25 s | 上一周期帧 |
| 0.5 ~ 0.75 s | 0.5 | 0 ~ 0.25 s | 上上周期帧 |
| 0.75 ~ 1.0 s | 0.75 | 0 ~ 0.25 s | 上上上周期帧 |

> 这是一个粗糙的"GPS 帧龄"估计，用于 `kf.posGNSSdelay` / `kf.vnGNSSdelay`（[main.cpp L112](../../assets/PSINS_STM32F4xx_Keil4_V2.1/scr/main.cpp)），让 KF 知道 GPS 数据有多"旧"。

---

## 七、航向角处理

```c
// usart.c L27-33
GPS_temp = ((Rx2_data[73]<<24)+(Rx2_data[72]<<16)+(Rx2_data[71]<<8)+(Rx2_data[70]));
gps_Data_value.GPS_Mot = GPS_temp / 100000.0;     // 1e-5 deg → deg
if(gps_Data_value.GPS_Mot > 180.0)
    gps_Data_value.GPS_Mot -= 360.0;                // 180~360 → -180~0
gps_Data_value.GPS_Mot *= DEG1;                    // deg → rad
```

UBX 的 `headMot` 是 0~360° 的地理航向（正北=0，顺时针）。代码把 180~360° 映射到 -180~0°，然后转弧度。但这个值在 `main.cpp` 中**没有被使用**——SINS 动态模式的 yaw 初始化用的是 `atan2(-gvn.i, gvn.j)` 而不是 GPS 航向角。

---

## 八、H743 移植要点

### 8.1 需要改的

| 项目 | F4 原工程 | H743 移植 | 说明 |
|---|---|---|---|
| USART 外设 | USART2 (PA2/PA3) | 可沿用或换 LPUART | H743 有更多 USART 资源 |
| DMA 透传 | 无（字节级中断） | 可改 DMA 接收 | 释放中断负载 |
| 校验和检查 | **未实现**（仅检查 Class/ID） | 建议加 CRC 校验 | 防止偶发误码导致位置跳变 |

!!! warning "原工程未做 UBX 校验和验证"
    UBX 帧末尾有 `CK_A`/`CK_B` 两个校验字节，但代码只检查了 `Class=0x01, ID=0x07`，**没有校验 checksum**。如果 GPS 数据有误码，可能会解析出错误的位置/速度。H743 移植时建议补上校验。

### 8.2 不需要改的

| 项目 | 说明 |
|---|---|
| UBX-NAV-PVT 协议 | u-blox 固有协议，与 MCU 无关 |
| 小端拼接逻辑 | 与 GPS 模块约定，不变 |
| 标度转换公式 | 1e-7 deg, mm/s 等不变 |
| GPS 延迟补偿逻辑 | PPS + MCU_ms_cnt 机制不变 |
| PCCMD 命令体系 | 纯软件协议，不变 |

---

??? note "自测题"
    1. `Rx2_data[30]` 对应 payload 第几字节？存的是什么物理量？
    2. GPS 速度解析中，为什么 `velD / -1000.0` 要除以负数？
    3. PCCMD 结构体只有 4 字节（两个 u16），但 PC_cmd 数组有 32 字节。多出来的字节有用吗？
    4. GPS_Delay 的单位是什么？为什么在输出时要减 0.25/0.5/0.75？
    5. GPSCFG 模式下 USART1 波特率从 460800 切到 115200，为什么？

??? note "参考答案"
    1. payload offset = 30 - 6 = 24，对应 UBX-NAV-PVT 的 `lon`（经度），I4 小端，1e-7 deg。
    2. velD 是地速度（Down，向下为正），而 PSINS 用 ENU（Up 为正）。除以 -1000 等于取负再除以 1000，把 vD 转成 vU。
    3. 没有直接用途。PCCMD 只用了前 4 字节，剩余 28 字节是预留的缓冲空间。USART1 ISR 用 `ii` 计数器循环填充 32 字节，但只通过 pcmd 指针访问前 4 字节。
    4. 原始单位是 100μs（因为 `MCU_ms_cnt*10` 和 `PPS_cnt` 都是 100μs 单位）。减 0.25/0.5/0.75 是因为 GPS 4Hz 输出（250ms 周期），如果收到的帧延迟超过 250ms，说明是上一个周期的旧数据，需要减去整数个周期。
    5. 因为 u-blox GPS 模块默认配置波特率是 9600 或 115200，而正常运行时的 USART1 输出波特率是 460800。GPSCFG 模式需要和 u-center 软件通信，所以切回 115200。

---

## 参考资料

- [u-blox UBX-NAV-PVT 接口说明](https://www.u-blox.com/en/docs/UBX-13003221) — UBX-NAV-PVT 报文 payload 偏移、lon/lat/velN/velE/velD 字段定义
- [u-blox NEO-M8 接口手册](https://www.u-blox.com/sites/default/files/products/documents/u-bloxM8-Manual(UBX-13003221).pdf) — u-blox M8 系列 GNSS 模块通信协议
- [严恭敏教授 CSDN 博客](https://blog.csdn.net/yan_gong_min) — PSINS 工程中 GPS 数据字节序处理与坐标系约定
- [STM32F4xx 参考手册 RM0090 — USART 章节](https://www.st.com/resource/en/reference_manual/dm00031020-stm32f405-415-stm32f407-417-stm32f427-437-and-stm32f429-439-advanced-arm-based-32-bit-mcus-stmicroelectronics.pdf) — USART2 接收中断、DMA 配置参考
- [PSINS 官网（严恭敏教授）](http://www.psins.org.cn/) — GPS_Pos=[lat,lon,h] / GPS_Vn=[vE,vN,vU] 约定来源

---

**参考体系**：[00 总览与架构](00_总览与架构.md) / [01 中断驱动与数据流](01_中断驱动与数据流.md) / 配套源码 [usart.c](../../assets/PSINS_STM32F4xx_Keil4_V2.1/scr/usart.c) / [main.cpp](../../assets/PSINS_STM32F4xx_Keil4_V2.1/scr/main.cpp) / [stm32f4xx_it.c](../../assets/PSINS_STM32F4xx_Keil4_V2.1/scr/stm32f4xx_it.c)
