#ifndef TRIAD_H
#define TRIAD_H
/* triad.h - TRIAD 双矢量定姿（Wahba 确定解），C 移植版
 *
 * 对标 miniins core/triad.m（M-A）。**算法本体与机体系约定无关**：
 * 只需调用方按自己所用导航系给出参考向量（NED 下：天向 = [0;0;−1]，
 * 磁北 = [mH·cos(dec); mH·sin(dec); … ]），函数内部不做任何约定假设。
 */
#include "ins_types.h"
#include "ins_math.h"

/* ib1/ib2：体系观测（第 1 列优先级高，如加计方向；第 2 列如磁）
 * in1/in2：导航系参考（与 ib 一一对应）
 * 返回：体→导航姿态四元数 */
quat triad(v3 ib1, v3 ib2, v3 in1, v3 in2);

#endif
