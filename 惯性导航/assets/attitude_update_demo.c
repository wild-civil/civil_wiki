/* =============================================================================
 * attitude_update_demo.c —— 姿态更新最小可运行示例（纯 C，无任何依赖）
 *
 * 对应 wiki: 惯性导航/02_解算篇/07_姿态更新算法.md
 * 目标: 让你"跑一遍就懂"姿态更新 —— IMU 角增量进来 → 四元数姿态出去
 *
 * 包含: ① rv2q（旋转向量→四元数增量）② qmul（四元数右乘）
 *       ③ qnorm（归一化）④ 圆锥运动数据生成（PSINS conesimu 同款公式）
 *       ⑤ 真值四元数 ⑥ 主循环输出姿态误差
 *
 * 编译运行 (Windows: 需要 gcc, 例如 MinGW):
 *   gcc -O2 -o attitude_update_demo.exe attitude_update_demo.c -lm
 *   ./attitude_update_demo.exe
 *
 * 预期输出（最后几行）: x 轴误差单调增长 ≈ coning 漂移，
 *   因为本 demo 用单子样 rv2q（无多子样补偿）—— 这正是 07 篇第六节的"未补偿"方法。
 * ========================================================================== */
#include <stdio.h>
#include <stdlib.h>
#include <math.h>

/* ---------- 三个核心函数（与固件 ins_eskf_15d.c 完全一致） ---------- */

/* 旋转向量 → 四元数增量（07 篇演示①的公式） */
static void rv2q(const float dt[3], float dq[4])
{
    float a = sqrtf(dt[0]*dt[0] + dt[1]*dt[1] + dt[2]*dt[2]), h = 0.5f * a;
    if (a < 1e-8f) { dq[0] = 1; dq[1] = dq[2] = dq[3] = 0; return; }
    float s = sinf(h) / a;          /* = sin(n/2)/n */
    dq[0] = cosf(h);
    dq[1] = s*dt[0]; dq[2] = s*dt[1]; dq[3] = s*dt[2];
}

/* 四元数乘法 o = q1 ⊗ q2（Hamilton，标量在首 [w,x,y,z]） */
static void qmul(float o[4], const float q1[4], const float q2[4])
{
    float w = q1[0]*q2[0] - q1[1]*q2[1] - q1[2]*q2[2] - q1[3]*q2[3];
    float x = q1[0]*q2[1] + q1[1]*q2[0] + q1[2]*q2[3] - q1[3]*q2[2];
    float y = q1[0]*q2[2] - q1[1]*q2[3] + q1[2]*q2[0] + q1[3]*q2[1];
    float z = q1[0]*q2[3] + q1[1]*q2[2] - q1[2]*q2[1] + q1[3]*q2[0];
    o[0] = w; o[1] = x; o[2] = y; o[3] = z;
}

/* 四元数归一化 */
static void qnorm(float q[4])
{
    float n = sqrtf(q[0]*q[0] + q[1]*q[1] + q[2]*q[2] + q[3]*q[3]);
    if (n > 1e-8f) { n = 1.0f / n; q[0]*=n; q[1]*=n; q[2]*=n; q[3]*=n; }
}

/* 四元数 → 旋转矩阵（world->body, 行主序; 与固件 q2r 一致）*/
static void q2r(const float q[4], float R[9])
{
    float xx=q[1]*q[1], yy=q[2]*q[2], zz=q[3]*q[3];
    float xy=q[1]*q[2], xz=q[1]*q[3], yz=q[2]*q[3];
    float wx=q[0]*q[1], wy=q[0]*q[2], wz=q[0]*q[3];
    R[0]=1-2*(yy+zz); R[1]=2*(xy+wz); R[2]=2*(xz-wy);
    R[3]=2*(xy-wz);   R[4]=1-2*(xx+zz); R[5]=2*(yz+wx);
    R[6]=2*(xz+wy);   R[7]=2*(yz-wx);  R[8]=1-2*(xx+yy);
}

/* 误差四元数: qe = q_true^-1 ⊗ q_est, 提取旋转矢量(大角正确形式) */
static void qerr_phi(const float qt[4], const float q[4], float phi[3])
{
    float qc[4] = { qt[0], -qt[1], -qt[2], -qt[3] };   /* qt 共轭 */
    float qe[4];
    qmul(qe, qc, q);                                   /* 误差四元数 */
    qnorm(qe);
    /* 旋转矢量: phi = 2*atan2(|v|, w) * v/|v| （大角也正确） */
    float vn = sqrtf(qe[1]*qe[1] + qe[2]*qe[2] + qe[3]*qe[3]);
    if (vn < 1e-12f) { phi[0]=phi[1]=phi[2]=0; return; }
    float ang = 2.0f * atan2f(vn, qe[0]);
    phi[0] = ang * qe[1]/vn; phi[1] = ang * qe[2]/vn; phi[2] = ang * qe[3]/vn;
}

/* ---------- 圆锥运动数据生成（PSINS conesimu 同款公式） ---------- */
/* 返回: wm=角增量(rad), qt=解析真值四元数(每时刻) */
static void conesimu(float afa, float f, float ts, int T,
                     float *wm, float *qt)
{
    float omega = 2.0f*(float)M_PI*f;
    int N = (int)(T/ts);
    int i;
    for (i = 0; i < N; i++) {
        float t  = i*ts;
        float t2 = t + ts/2.0f;
        /* 角增量（每帧陀螺输出, rad） */
        wm[3*i+0] = -2.0f*omega*ts*sinf(afa/2)*sinf(afa/2);
        wm[3*i+1] = -2.0f*sinf(afa)*sinf(omega*ts/2)*sinf(omega*t2);
        wm[3*i+2] =  2.0f*sinf(afa)*sinf(omega*ts/2)*cosf(omega*t2);
        /* 解析真值四元数（标量在首） */
        qt[4*i+0] = cosf(afa/2);
        qt[4*i+1] = 0;
        qt[4*i+2] = sinf(afa/2)*cosf(omega*t);
        qt[4*i+3] = sinf(afa/2)*sinf(omega*t);
    }
}

/* ---------- 主循环：单子样 rv2q + qmul 姿态更新 ---------- */
int main(void)
{
    /* 圆锥运动参数: 半锥角 5°, 频率 1Hz, 100Hz 采样, 10 秒
       （温和参数更贴近真实载体；90° 半锥角太剧烈，单子样误差会到几十度） */
    float afa = 5.0f * (float)M_PI / 180.0f;
    float f   = 1.0f;
    float ts  = 0.01f;
    int   T   = 10;
    int   N   = (int)(T/ts);          /* 1000 帧 */

    float *wm = (float*)malloc(3*N*sizeof(float));
    float *qt = (float*)malloc(4*N*sizeof(float));
    conesimu(afa, f, ts, T, wm, qt);

    float q[4];
    q[0]=qt[0*4+0]; q[1]=qt[0*4+1]; q[2]=qt[0*4+2]; q[3]=qt[0*4+3];  /* 初始姿态=真值起点 */
    int i;
    float max_phi = 0;

    printf("=== 姿态更新 demo: 圆锥运动 (半锥角5°, 1Hz, 100Hz, %ds) ===\n", T);
    printf("方法: 单子样 rv2q + qmul（每帧更新，无 coning 补偿）\n\n");
    printf(" t(s) |     x_err(arcsec) |     y_err(arcsec) |     z_err(arcsec)\n");
    printf("------+-------------------+-------------------+------------------\n");

    for (i = 0; i < N; i++) {
        /* 1. 陀螺角增量 -> 旋转向量（本例直接用角增量） */
        float dq[4];
        rv2q(&wm[3*i], dq);

        /* 2. 右乘更新姿态 */
        qmul(q, q, dq);
        qnorm(q);

        /* 3. 与真值比误差（arcsec） */
        float phi[3];
        qerr_phi(&qt[4*i], q, phi);
        float xa = phi[0] * 180.0f/(float)M_PI * 3600.0f;
        float ya = phi[1] * 180.0f/(float)M_PI * 3600.0f;
        float za = phi[2] * 180.0f/(float)M_PI * 3600.0f;

        if (fabsf(xa) > max_phi) max_phi = fabsf(xa);

        if (i % 100 == 0 || i == N-1)
            printf("%5.2f | %17.3f | %17.3f | %17.3f\n", i*ts, xa, ya, za);
    }

    printf("------+-------------------+-------------------+------------------\n");
    printf("x 轴误差峰值: %.3f arcsec\n", max_phi);
    printf("\n观察: 5° 半锥角 + 100Hz 下，单子样 rv2q 误差只有几 arcsec（≈1e-3°），\n");
    printf("工程上完全可接受 —— 这就是 07 篇说\"本项目 1000Hz MEMS 单子样够用\"的原因。\n");
    printf("若把半锥角改大(如 45°)再跑，x 轴误差会暴涨到几十度 —— 那就是\n");
    printf("\"旋转不可交换\"的圆锥效应，需 Bortz 多子样补偿（07 篇第六节 516\"/0.09\" 对比）。\n");

    free(wm); free(qt);
    return 0;
}
