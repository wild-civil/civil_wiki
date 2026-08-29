#include "mahony.h"

/* 准静态门控阈值（与 miniins mahonyupdate.m 一致）：
 *   |‖f‖−g| ≤ 0.05 全信加计(λ=1)；≥ 0.2 全不信(λ=0)；中间线性过渡 */
#define GATE_LO 0.05
#define GATE_HI 0.20

void ahrs_init(ahrs_t *a, v3 att0, real_t Kp, real_t Ki, real_t lat, real_t dec)
{
    a->q       = dcm2q(a2dcm(att0));
    a->C       = q2dcm(a->q);
    a->exyzInt = v_make(0, 0, 0);
    a->Kp      = Kp;
    a->Ki      = Ki;
    a->wnie    = wnie_ned(lat);
    a->dec     = dec;
    a->g0      = glv_g0();
    a->tk      = 0;
}

void ahrs_update(ahrs_t *a, v3 wm, v3 vm, v3 mag, real_t ts, int use_mag)
{
    /* ① 比力方向（加计"投票"的原始信息） */
    v3    f   = scale3(vm, (real_t)1.0 / ts);
    real_t nmf = norm3(f);
    v3    acc = (nmf > 0) ? scale3(f, (real_t)1.0 / nmf) : v_make(0, 0, 0);

    /* ② 准静态门控 λ */
    real_t nm1 = (real_t)fabs(nmf - a->g0);
    real_t lam;
    if (nm1 <= GATE_LO)      lam = 1;
    else if (nm1 >= GATE_HI) lam = 0;
    else                     lam = (GATE_HI - nm1) / (GATE_HI - GATE_LO);

    /* ③④ 误差向量 e（公式 6.2）：天向项 + 磁向项 */
    v3 e = v_make(0, 0, 0);
    if (lam > 0) {
        /* NED：z 轴朝下 → 体系"上"方向 = −第 3 行（ENU 版此处为正号） */
        v3 down_b = drow(a->C, 2);
        v3 up_b   = scale3(down_b, -1);
        e = scale3(cross3(up_b, acc), lam);
    }
    if (use_mag && norm3(mag) > 0) {
        v3 m  = unit3(mag);
        v3 mn = mv3(a->C, m);                       /* 体磁 → 导航系（NED） */
        real_t mh = (real_t)sqrt(mn.x*mn.x + mn.y*mn.y);
        mn.x = mh * (real_t)cos(a->dec);            /* 磁北：北分量 */
        mn.y = mh * (real_t)sin(a->dec);            /* 磁北：东偏 dec */
        v3 mp = tmv3(a->C, mn);                     /* 预测体磁（只含磁航向） */
        e = add3(e, cross3(mp, m));
    }

    /* ⑤ PI 反馈（公式 6.3）：积分项稳态吸收陀螺零偏 */
    a->exyzInt = add3(a->exyzInt, scale3(e, a->Ki * ts));
    v3 eb = add3(scale3(e, a->Kp), a->exyzInt);

    /* ⑥ 姿态更新（公式 6.4）：陀螺积分 − 地球自转 − PI 反馈 */
    v3 wie_b = tmv3(a->C, a->wnie);                 /* 导航系地球自转 → 体系 */
    v3 phim  = sub3(wm, scale3(add3(wie_b, eb), ts));
    a->q = q_norm(q_mul(a->q, rv2q(phim)));         /* 右乘体轴增量 */
    a->C = q2dcm(a->q);
    a->tk += ts;
}
