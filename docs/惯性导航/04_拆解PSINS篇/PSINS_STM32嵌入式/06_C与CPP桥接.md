# C 与 C++ 桥接：extern、强转与内存布局

> 配套源码: [main.cpp](../../assets/PSINS_STM32F4xx_Keil4_V2.1/scr/main.cpp) / [main.h](../../assets/PSINS_STM32F4xx_Keil4_V2.1/scr/main.h) / [mcu_init.h](../../assets/PSINS_STM32F4xx_Keil4_V2.1/scr/mcu_init.h) / [PSINS.h](../../assets/PSINS_STM32F4xx_Keil4_V2.1/Psinscore/PSINS.h)
> 所属层级: 嵌入式落地篇 · 衔接层
> 前置依赖: [00 总览与架构](00_总览与架构.md) / [02 传感器驱动 MPU9250](02_传感器驱动_MPU9250.md) / [04 GPS解析与PC命令](04_GPS解析与PC命令.md)
> 学习目标: 读完后你应能回答：
> 1. 为什么要用 C/C++ 混合？不全用 C++ 行不行？
> 2. `extern "C"` 在头文件里起什么作用？去掉会怎样？
> 3. `*(CVect3*)mpu_Data_value.Gyro` 为什么能编译通过且运行正确？
> 4. `->` 和 `.` 有什么区别？什么时候用哪个？
> 5. `struct PCCMD *pcmd=(PCCMD*)&PC_cmd` 这一行发生了什么？

!!! tip "本篇为什么重要"
    这一篇回答你在学代码时最常遇到的**语法困惑**。前面 5 篇都反复出现 `*(CVect3*)`、`->`、`extern`、`_cnt` 等语法，本篇一次性把背后的原理讲透。读完后再看 `main.cpp` 的每一行，不会再有"这什么意思"的卡顿。

---

## 一、为什么要 C/C++ 混合

本工程编译时，Keil 把 `.c` 文件按 C 编译、`.cpp` 文件按 C++ 编译，最终链接到一起。混合的原因：

| 层 | 语言 | 为什么 |
|---|---|---|
| 驱动层 `scr/*.c` | C | 中断服务函数、寄存器操作、SPL 标准库都是 C 接口 |
| 算法层 `Psinscore/*.cpp` | C++ | 需要类、运算符重载、继承（`CSINS` 继承 `CIMU`）来复用 MATLAB PSINS 的数学结构 |
| 衔接层 `scr/main.cpp` | C++ | 需要调用 C++ 算法类（`CMahony`, `CKFApp`），同时通过 `extern` 访问 C 全局变量 |

> **为什么不全用 C++？** 因为 STM32 标准外设库（SPL）、CMSIS、中断向量表启动文件全是 C 链接约定的。如果用 C++ 写中断函数，函数名会被 mangling（如 `TIM2_IRQHandler` → `_Z17TIM2_IRQHandlerv`），启动文件 `.s` 里的中断向量表就找不到符号了。

---

## 二、`extern "C"` 机制

### 2.1 C++ Name Mangling

C++ 编译器会对函数名做"修饰"（name mangling），把参数类型编码到符号名里：

| 函数 | C 符号名 | C++ 符号名 (GCC/ARM) |
|---|---|---|
| `void Init_MPU9250(void)` | `Init_MPU9250` | `_Z14Init_MPU9250v` |
| `void Delay(uint32_t)` | `Delay` | `_Z5Delayj` |

如果 C 文件定义了 `Init_MPU9250`，C++ 文件要调用它，编译器去找 `_Z14Init_MPU9250v` ——找不到，链接报错。

### 2.2 `extern "C"` 的作用

`extern "C"` 告诉 C++ 编译器："这些函数/变量用 C 链接约定（不 mangling）"。

[mcu_init.h L10-12](../../assets/PSINS_STM32F4xx_Keil4_V2.1/scr/mcu_init.h)：

```c
#ifdef __cplusplus
 extern "C" {
#endif

// 此处的声明对 C++ 编译器用 C 链接约定
void Delay(__IO uint32_t nTime);
void mcu_init(void);
void Init_MPU9250(void);
// ...

#ifdef __cplusplus
}
#endif
```

| 编译器 | `__cplusplus` | 效果 |
|---|---|---|
| C 编译器（编译 .c） | 未定义 | `extern "C"` 块被跳过，正常声明 |
| C++ 编译器（编译 .cpp） | 已定义 | 函数声明被包裹在 `extern "C"` 里，不 mangle |

> **效果**：C++ 文件 `main.cpp` 调用 `Init_MPU9250()` 时，符号名保持 C 风格 `Init_MPU9250`，和 C 文件 `mpu9250.c` 里定义的符号名一致，链接器能找到。

### 2.3 全局变量桥接

C 文件定义全局变量，C++ 文件用 `extern` 引用。

[mcu_init.c L18-24](../../assets/PSINS_STM32F4xx_Keil4_V2.1/scr/mcu_init.c)（C 文件定义）：
```c
MPU_AD_value    mpu_AD_value;     // 定义
MPU_Data_value  mpu_Data_value;   // 定义
GPS_Data_value  gps_Data_value;    // 定义
Out_Frame       outFrame;          // 定义
u8  PC_cmd[32];                   // 定义
```

[main.h L10-11](../../assets/PSINS_STM32F4xx_Keil4_V2.1/scr/main.h)（被 C++ 的 `main.cpp` include）：
```c
extern MPU_AD_value    mpu_AD_value;     // 引用
extern MPU_Data_value  mpu_Data_value;   // 引用
extern GPS_Data_value  gps_Data_value;    // 引用
extern Out_Frame       outFrame;          // 引用
```

> `extern` = "这个变量在别处定义了，我只声明它的存在"。变量只有一份实体（在 `mcu_init.c` 里），两个语言都能访问。

---

## 三、指针强转：`*(CVect3*)` 的原理

### 3.1 内存布局对齐

这是整个桥接的核心手法。先看两边的内存布局：

**C 层：`double[3]` 数组**

[mcu_init.h L21-28](../../assets/PSINS_STM32F4xx_Keil4_V2.1/scr/mcu_init.h) 的 `MPU_Data_value`：
```c
typedef struct {
    double Accel[3];   // 24 bytes: [0]=Accel_x, [1]=Accel_y, [2]=Accel_z
    double Temp;        // 8 bytes
    double Gyro[3];     // 24 bytes: [0]=Gyro_x, [1]=Gyro_y, [2]=Gyro_z
    double Mag[3];      // 24 bytes
    // ...
} MPU_Data_value;
```

`mpu_Data_value.Gyro` 是一个 `double[3]`，首地址 = `&mpu_Data_value` + 32 字节偏移。

**C++ 层：`CVect3` 类**

[PSINS.h L270-273](../../assets/PSINS_STM32F4xx_Keil4_V2.1/Psinscore/PSINS.h)：
```cpp
class CVect3 {
public:
    double i, j, k;    // 24 bytes: i=x, j=y, k=z
    // ... 构造函数、运算符重载 ...
};
```

`CVect3` 只有三个 `double` 成员，**没有虚函数**（无 vtable 指针），**没有继承**（无基类子对象）。

### 3.2 内存对齐验证

| 类型 | 偏移 0-7 | 偏移 8-15 | 偏移 16-23 | 总大小 |
|---|---|---|---|---|
| `double[3]` | `arr[0]` | `arr[1]` | `arr[2]` | 24 bytes |
| `CVect3` | `i` | `j` | `k` | 24 bytes |

**内存布局完全一致**。所以把 `double[3]` 的首地址强转为 `CVect3*`，解引用后 `i = arr[0]`, `j = arr[1]`, `k = arr[2]`，物理上正确。

### 3.3 强转代码

[main.cpp L45](../../assets/PSINS_STM32F4xx_Keil4_V2.1/scr/main.cpp)：

```c
wm = (*(CVect3*)mpu_Data_value.Gyro * glv.dps - eb) * TS;
```

逐步拆解：

| 步骤 | 代码 | 类型 | 含义 |
|---|---|---|---|
| ① 取地址 | `mpu_Data_value.Gyro` | `double*` | 数组名退化为指针，指向首元素 |
| ② 强转 | `(CVect3*)mpu_Data_value.Gyro` | `CVect3*` | 把 `double*` 当作 `CVect3*` |
| ③ 解引用 | `*(CVect3*)mpu_Data_value.Gyro` | `CVect3` | 取出整个 `CVect3` 对象（值拷贝） |
| ④ 乘法 | `... * glv.dps` | `CVect3` | 调用 `CVect3::operator*(double)` |
| ⑤ 减法 | `... - eb` | `CVect3` | 调用 `CVect3::operator-(CVect3)` |
| ⑥ 再乘 | `... * TS` | `CVect3` | 再次调用 `operator*(double)` |
| ⑵ 赋值 | `wm = ...` | `CVect3` | 调用 `operator=(CVect3)` |

> **核心**：步骤②③把 C 数组"当作"C++ 对象来用，零拷贝、零开销。之后所有运算都是 C++ 的运算符重载，和纯 C++ 代码写 `CVect3 v(1,2,3) * 2` 没有任何区别。

!!! note "为什么没有虚函数才能这样强转？"
    如果 `CVect3` 有虚函数，C++ 会在对象首部插入一个 vtable 指针（4 或 8 字节）。此时 `double[3]` 的首字节对应的是 vtable 指针，`i/j/k` 的偏移会后移。强转后 `i` 会读到垃圾数据。所以**只有 POD (Plain Old Data) 类才能安全强转**。

---

## 四、`->` 和 `.` 的区别

| 操作符 | 用于 | 语法 | 等价写法 |
|---|---|---|---|
| `.` | 对象（实例） | `obj.member` | 直接访问 |
| `->` | 指针 | `ptr->member` | `(*ptr).member` |

```c
CVect3 v(1, 2, 3);       // 对象
CVect3 *pv = &v;          // 指针

v.i        // ✅ 对象用 .
pv->i      // ✅ 指针用 ->
(*pv).i    // ✅ 解引用后用 .
pv.i       // ❌ 编译错误：指针不能用 .
v->i       // ❌ 编译错误：对象不能用 ->
```

### 4.1 本工程中的用法

```c
// 对象用 .
mahony.Update(wm, vm, TS);    // mahony 是对象

// 指针用 ->
pcmd->cmd1 = 0;                // pcmd 是指针
pcmd->cmd2 = 0x1111;
```

---

## 五、PCCMD 指针强转

### 5.1 代码

[main.cpp L8-10](../../assets/PSINS_STM32F4xx_Keil4_V2.1/scr/main.cpp)：

```c
struct PCCMD {
    u16 cmd1, cmd2;
} *pcmd = (PCCMD*)&PC_cmd;
```

### 5.2 逐步拆解

| 步骤 | 代码 | 含义 |
|---|---|---|
| ① 定义结构体 | `struct PCCMD { u16 cmd1, cmd2; }` | 4 字节：cmd1(2B) + cmd2(2B) |
| ② 定义指针 | `*pcmd` | 声明 `PCCMD*` 类型的指针变量 |
| ③ 取地址 | `&PC_cmd` | 取 `PC_cmd` 数组的首地址，类型 `u8(*)[32]` |
| ④ 强转 | `(PCCMD*)&PC_cmd` | 把 `u8(*)[32]` 转成 `PCCMD*` |
| ⑤ 初始化 | `pcmd = ...` | 让 pcmd 指向 PC_cmd 数组的起始位置 |

### 5.3 内存映射

`PC_cmd` 是 `u8[32]` 数组（[mcu_init.c L24](../../assets/PSINS_STM32F4xx_Keil4_V2.1/scr/mcu_init.c)）。通过 USART1 中断填充（[stm32f4xx_it.c L305](../../assets/PSINS_STM32F4xx_Keil4_V2.1/scr/stm32f4xx_it.c)）：

```c
PC_cmd[ii++] = temp;  // 逐字节写入
```

强转后的映射：

```
PC_cmd 字节:  [0]   [1]   [2]   [3]   [4] ... [31]
               ↓     ↓     ↓     ↓
pcmd 字段:   cmd1_lo cmd1_hi cmd2_lo cmd2_hi  (未用)
               └── cmd1 ──┘  └── cmd2 ──┘
```

假设 PC 发送 `0x11 0x11 0x00 0x00`（4 字节），STM32 小端解析：

- `cmd1 = 0x0011`（低字节在前）
- `cmd2 = 0x0000` → 不对！

等等，再看代码：

```c
case 0x1111:  // cmd2 要等于 0x1111
```

如果 PC 发 `0x00 0x00 0x11 0x11`：
- `cmd1 = 0x0000`
- `cmd2 = 0x1111` → 匹配！

> 实际上 PC 端发送的 4 字节中，前 2 字节是 `cmd1`，后 2 字节是 `cmd2`。要进入 Mahony 模式，PC 需要发 `0x00 0x00 0x11 0x11`（或等价的其他序列使 cmd2=0x1111）。

### 5.4 为什么不直接 `u16 PC_cmd[2]`？

因为 USART1 中断是**逐字节接收**的，`u8 PC_cmd[32]` 是最自然的缓冲区类型。用结构体指针强转后，前 4 字节自动解释为两个 `u16`，无需手动拼接。

---

## 六、`_cnt` / `_flag` / `_value` 命名约定

本工程的变量命名有几条隐含规则：

| 后缀 | 含义 | 示例 |
|---|---|---|
| `_cnt` | 计数器/状态机状态 | `MAG_cnt`(0→1→2→0循环), `MS5611_cnt`(1→5循环) |
| `_flag` | 布尔标志位（实际用 u8） | `GAMT_OK_flag`, `GPS_OK_flag`, `Bar_OK_flag` |
| `_value` | 数据结构体实例 | `mpu_AD_value`, `mpu_Data_value`, `gps_Data_value` |
| `_complete` | 接收完成标志 | `Rx2_complete` |
| `_data` / `Data` | 原始数据 | `GPS_temp`, `D1_Pres`, `D2_Temp` |

> 这是严老师的编码风格约定，不是 C 语言标准。但掌握后读代码更流畅。

---

## 七、`GAMT_OK_flag = 0` 再赋值为 0 的解释

这是你之前问过的问题。代码：

```c
if(GAMT_OK_flag == 0) continue;   // flag 为 0 → 跳过本轮
GAMT_OK_flag = 0;                  // 取走 flag，开始处理
```

| 时刻 | `GAMT_OK_flag` | 谁改的 | 含义 |
|---|---|---|---|
| TIM2 中断置位 | 0→1 | 中断 | "新数据准备好了，请处理" |
| 主循环检测 | ==1 | — | 通过 if 检查，不 continue |
| 主循环取走 | 1→0 | 主循环 | "我收到了，正在处理" |
| 下一轮 | ==0 | — | continue 跳过，等下一次中断 |

> **关键**：`GAMT_OK_flag = 0` 不是"把 0 再设成 0"，而是"从 1 变成 0"——**取走标志**。这就像快递柜取件：短信通知（flag=1）→ 取件（flag→0）→ 下次没通知就不取（continue）。

---

## 八、H743 移植要点

### 8.1 桥接机制不需要改

所有 `extern "C"`、`extern` 变量、`*(CVect3*)` 强转、PCCMD 强转都与 MCU 平台无关，**零修改直接复用**。

### 8.2 需要注意的

| 项目 | 说明 |
|---|---|
| 编译器选项 | 确保 `.cpp` 用 C++ 编译、`.c` 用 C 编译 |
| 结构体对齐 | `MPU_Data_value` 和 `CVect3` 的内存布局必须在 H743 上也一致（同为 8-byte aligned double） |
| `__packed` | 如果往 `Out_Frame` 里加了新字段，加 `__packed` 防 padding |
| `extern "C"` | 所有 C 头文件必须保留 `extern "C"` 块 |

---

??? note "自测题"
    1. 如果 `CVect3` 有一个虚函数 `virtual void foo()`，`*(CVect3*)double_array` 还能正常工作吗？为什么？
    2. `extern "C"` 块里声明的函数，C++ 编译器会做 name mangling 吗？
    3. `pcmd->cmd2` 和 `(*pcmd).cmd2` 有区别吗？
    4. 为什么 `MPU_Data_value` 用 `double` 而不是 `float`？和 `CVect3` 的成员类型有关吗？
    5. 如果 USART1 收到 `0xa5 0xa5`，pcmd->cmd1 等于多少？会触发什么动作？

??? note "参考答案"
    1. 不能。虚函数会在对象首部插入 vtable 指针（4 或 8 字节），导致 i/j/k 的偏移后移。强转后 i 会读到 vtable 指针而不是数组第一个元素。
    2. 不会。`extern "C"` 的作用就是告诉 C++ 编译器用 C 链接约定（不做 mangling）。
    3. 完全等价。`->` 是 `(*ptr).member` 的语法糖。
    4. 因为 `CVect3` 的成员是 `double i, j, k`。如果用 `float`，内存布局不匹配（float 是 4 字节，double 是 8 字节），强转后 i 会读到错误的值。类型必须严格一致。
    5. `pcmd->cmd1 = 0xa5a5`（小端序：0xa5 是低字节，0xa5 是高字节）。触发当前模式的退出：`if(pcmd->cmd1 == 0xa5a5) break;`。

---

## 参考资料

- [ISO C++ FAQ: Mixing C and C++](https://isocpp.org/wiki/faq/mixing-c-and-cpp) — extern "C"、name mangling、链接约定的官方说明
- [POD（Plain Old Data）类型与内存布局](https://en.cppreference.com/w/cpp/named_req/PODType) — CVect3 作为 POD 的内存连续性、对齐要求，保证 *(CVect3*)arr 强转合法
- [C++ 对象内存模型（vtable 与成员布局）](https://en.cppreference.com/w/cpp/language/object) — 虚函数对对象首部内存的影响，解释为何带 vtable 的类不能强转
- [ARM AAPCS 调用约定手册](https://developer.arm.com/documentation/ihi0042/latest/) — ARM 工具链下 double 8 字节对齐规则
- [PSINS 官网（严恭敏教授）](http://www.psins.org.cn/) — CVect3 / CQuat / CMat3 类定义与全局变量 glv 来源

---

**参考体系**：[00 总览与架构](00_总览与架构.md) / [02 传感器驱动 MPU9250](02_传感器驱动_MPU9250.md) / [04 GPS解析与PC命令](04_GPS解析与PC命令.md) / [05 串口输出帧](05_串口输出帧.md) / 配套源码 [main.cpp](../../assets/PSINS_STM32F4xx_Keil4_V2.1/scr/main.cpp) / [PSINS.h](../../assets/PSINS_STM32F4xx_Keil4_V2.1/Psinscore/PSINS.h) / [mcu_init.h](../../assets/PSINS_STM32F4xx_Keil4_V2.1/scr/mcu_init.h)
