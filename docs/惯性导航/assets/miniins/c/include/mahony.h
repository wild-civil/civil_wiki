#ifndef MAHONY_H
#define MAHONY_H
/* mahony.h - Mahony 互补滤波（PI 反馈），C 移植版
 *
 * 对标 miniins core/mahonyupdate.m（M-A）。⚠️ 本文件**依赖 NED+FRD 约定**，
 * 与 MATLAB 版（ENU + PSINS 机体系）的差异全在"参考向量取值"上：
 *   · 重力：NED 的 z 轴朝下 → 体系"上"方向 = −Cbn(3,:)'      （ENU 版是 +）
 *   · 地磁：水平参考指向磁北 = [mh·cos(dec); mh·sin(dec); …]（东偏为正）
 *   · 地球自转：wnie = [wie·cosL; 0; −wie·sinL]              （ENU 版 z 为正）
 * 误差项结构 e = 预测×实测、PI 反馈、右乘 rv2q 更新，与 MATLAB 版逐行同构。
 */
#include "ins_types.h"
#include "ins_math.h"

typedef struct {
    quat   q;          /* 姿态四元数（体→导航） */
    dcm    C;          /* 姿态阵（q 的阵形式，每步同步） */
    v3     exyzInt;    /* PI 积分项（稳态 = 陀螺零偏） */
    real_t Kp, Ki;     /* 比例 / 积分增益 */
    v3     wnie;       /* 地球自转（NED，由纬度算） */
    real_t dec;        /* 磁偏角（rad，东偏为正） */
    real_t g0;         /* 重力常量（准静态门控判据） */
    real_t tk;         /* 累计时间 */
} ahrs_t;

/* 初始化：att0=[roll;pitch;yaw](rad)、lat=纬度(rad)、dec=磁偏角(rad) */
void ahrs_init(ahrs_t *a, v3 att0, real_t Kp, real_t Ki, real_t lat, real_t dec);

/* 单步更新：wm/ts=角增量(rad)、vm/ts=比力(m/s²)、mag=体磁测量、use_mag=0 时忽略磁 */
void ahrs_update(ahrs_t *a, v3 wm, v3 vm, v3 mag, real_t ts, int use_mag);

#endif
