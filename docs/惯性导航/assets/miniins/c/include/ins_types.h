#ifndef INS_TYPES_H
#define INS_TYPES_H
/* =========================================================================
 * ins_types.h - Mini-INS C 移植版（固件方向）基础类型
 *
 * ⚠️ 机体系约定（D0 拍板，2026-08-29）：**NED + FRD（航空惯例）**
 *   - 导航系 n = NED：x 北(N)、y 东(E)、z 地(D)
 *   - 机体系 b = FRD：x 前(F)、y 右(R)、z 下(D)
 *   - 姿态角 att = [roll; pitch; yaw]（绕 x / y / z），yaw=0 朝北、yaw 增 = 右转（向东）
 *   - Cbn 为**体→导航**姿态阵：v_n = Cbn · v_b
 *
 * ⚠️ 与 MATLAB miniins 的差异（PSINS 约定：ENU + 机体系 x右 y前 z上、
 *   att=[pitch;roll;yaw]）：四元数/DCM 的**代数**完全一致（本文件与 ins_math.c
 *   可直接对拍），差异只出现在两处"约定相关"的地方：
 *     ① att↔DCM 转换（哪个角绕哪个轴）→ a2dcm / dcm2att 按 NED 写；
 *     ② 参考向量取值（重力/地磁/地球自转在 NED 下的分量）→ 见 mahony.c。
 *   固件与 MATLAB 之间的换算只需一个固定适配阵（上电初始化算一次，不进热路径）。
 *
 * 精度：默认 double（对拍用）；固件可 -DINS_REAL=float 切单精度跑同一套测试。
 * ========================================================================= */
#include <math.h>

#ifndef INS_REAL
#define INS_REAL double
#endif
typedef INS_REAL real_t;

typedef struct { real_t x, y, z; } v3;          /* 三维向量 */
typedef struct { real_t w, x, y, z; } quat;     /* 四元数，标量在前 [w x y z] */
typedef struct { real_t m[3][3]; } dcm;         /* 3×3 姿态阵（体→导航） */

#endif
