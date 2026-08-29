#ifndef INS_MATH_H
#define INS_MATH_H
/* ins_math.h - 四元数 / 姿态阵 / 向量 基础运算（与机体系约定无关，可 1:1 对拍 MATLAB）
 *
 * 约定相关函数只有两个：a2dcm / dcm2att（按 NED+FRD 写，见 ins_types.h 顶部说明）。
 * 其余（q2dcm / dcm2q / qmul / rv2q / qmulv ...）是纯代数，两种约定下逐位一致。
 */
#include "ins_types.h"

/* ---- 构造 ---- */
quat q_make(real_t w, real_t x, real_t y, real_t z);
v3   v_make(real_t x, real_t y, real_t z);

/* ---- 向量 ---- */
v3    cross3(v3 a, v3 b);
real_t dot3(v3 a, v3 b);
v3    add3(v3 a, v3 b);
v3    sub3(v3 a, v3 b);
v3    scale3(v3 a, real_t s);
real_t norm3(v3 a);
v3    unit3(v3 a);

/* ---- 四元数 ---- */
quat q_mul(quat a, quat b);      /* Hamilton 积 a⊗b */
quat q_conj(quat q);
quat q_norm(quat q);
quat rv2q(v3 rv);                /* 旋转矢量 → 四元数 */
v3   qmulv(quat q, v3 v);        /* 用 q 旋转向量（体→导航） */

/* ---- 姿态阵 ---- */
dcm  q2dcm(quat q);              /* 四元数 → Cbn（体→导航） */
quat dcm2q(dcm C);               /* Cbn → 四元数（w>0 归一） */
v3   mv3(dcm C, v3 v);           /* C   · v（体→导航） */
v3   tmv3(dcm C, v3 v);          /* C'  · v（导航→体） */
v3   drow(dcm C, int i);         /* 取第 i 行（0 基）作为向量 */

/* ---- 约定相关：NED+FRD 欧拉角（att = [roll; pitch; yaw]）---- */
dcm  a2dcm(v3 att);              /* Cbn = Rz(yaw)·Ry(pitch)·Rx(roll) */
v3   dcm2att(dcm C);             /* 逆变换，|pitch|<80° 稳定 */

/* ---- 地球 ---- */
v3   wnie_ned(real_t lat);       /* 地球自转在 NED 的分量 [wie·cosL; 0; −wie·sinL] */
real_t glv_wie(void);
real_t glv_g0(void);

#endif
