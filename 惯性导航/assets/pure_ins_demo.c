/*
 * pure_ins_demo.c — 纯惯导完整闭环最小实现（M2 → M3 的桥）
 *
 * 从 IMU 原始数据（角增量 + 比力）→ 完整 9 态解算（姿态四元数 + 速度 + 位置），
 * 静止基座 60 min 仿真，注入三类误差（陀螺零偏 / 加计零偏 / 初始失准角），
 * 输出误差增长曲线，并在结尾对照 09 篇解析解（牛小骥讲义式 68）。
 *
 * 对应篇章：
 *   - 06 机械编排：比力 → 速度 → 位置 的积分递推
 *   - 07 姿态更新：rv2q + qmul 右乘递推
 *   - 08 初始对准：初始失准角（对准残差）
 *   - 09 误差传播：位置误差 = 初始失准角舒勒振荡 + 陀螺零偏线性发散
 *
 * 编译运行：
 *   gcc -O2 -o pure_ins_demo.exe pure_ins_demo.c -lm
 *   ./pure_ins_demo.exe
 *
 * 约定（重要，防坑）：
 *   - 坐标系：NED（北东地），z 轴向下
 *   - 重力向量 g^n = [0,0,+g]（D 轴向下为正）
 *   - 速度微分方程：v̇^n = C_b^n f^b + g^n（比力 + 重力，见 06 篇式 18）
 *   - 静止水平时加计读数 f^b = [0,0,-g]（抵消重力）
 *   - 四元数存储序 [w,x,y,z]（与固件 ins_math.h 一致）
 */
#include <stdio.h>
#include <math.h>
#include <stdlib.h>
#ifdef _WIN32
#include <windows.h>   /* SetConsoleOutputCP：控制台切 UTF-8，中文/数学符号正常显示 */
#endif

/* ========== 四元数工具（与固件 ins_math.h 逐字一致） ========== */

/* 旋转向量 → 四元数增量（固件 rv2q） */
static void rv2q(const double rv[3], double q[4])
{
    double a = sqrt(rv[0]*rv[0] + rv[1]*rv[1] + rv[2]*rv[2]);
    double h = 0.5 * a;
    if (a < 1e-12) { q[0]=1; q[1]=0; q[2]=0; q[3]=0; return; }
    double s = sin(h) / a;
    q[0] = cos(h); q[1] = s*rv[0]; q[2] = s*rv[1]; q[3] = s*rv[2];
}

/* Hamilton 四元数乘法（固件 qmul） */
static void qmul(double qo[4], const double q1[4], const double q2[4])
{
    double w = q1[0]*q2[0] - q1[1]*q2[1] - q1[2]*q2[2] - q1[3]*q2[3];
    double x = q1[0]*q2[1] + q1[1]*q2[0] + q1[2]*q2[3] - q1[3]*q2[2];
    double y = q1[0]*q2[2] - q1[1]*q2[3] + q1[2]*q2[0] + q1[3]*q2[1];
    double z = q1[0]*q2[3] + q1[1]*q2[2] - q1[2]*q2[1] + q1[3]*q2[0];
    qo[0]=w; qo[1]=x; qo[2]=y; qo[3]=z;
}

/* 四元数归一化（固件 qnorm） */
static void qnorm(double q[4])
{
    double n = sqrt(q[0]*q[0] + q[1]*q[1] + q[2]*q[2] + q[3]*q[3]);
    if (n > 1e-12) { q[0]/=n; q[1]/=n; q[2]/=n; q[3]/=n; }
}

/* 四元数 → body→nav 旋转矩阵 C_b^n（v_n = C_b^n v_b）。
 * 注意：固件 q2r 输出的是 nav→body（world→body），转比力要转置；
 * 这里直接给 C_b^n（body→nav），避免新人踩方向坑。 */
static void q2Cbn(const double q[4], double C[9])
{
    double w=q[0], x=q[1], y=q[2], z=q[3];
    C[0]=1-2*(y*y+z*z); C[1]=2*(x*y-z*w);   C[2]=2*(x*z+y*w);
    C[3]=2*(x*y+z*w);   C[4]=1-2*(x*x+z*z); C[5]=2*(y*z-x*w);
    C[6]=2*(x*z-y*w);   C[7]=2*(y*z+x*w);   C[8]=1-2*(x*x+y*y);
}

/* 误差四元数 → 旋转矢量（大角正确形式 atan2，07 篇已修） */
static void qerr_phi(const double qt[4], const double q[4], double phi[3])
{
    double qc[4] = { qt[0], -qt[1], -qt[2], -qt[3] };  /* qt 共轭 */
    double qe[4];
    qmul(qe, qc, q);
    qnorm(qe);
    double vn = sqrt(qe[1]*qe[1] + qe[2]*qe[2] + qe[3]*qe[3]);
    if (vn < 1e-12) { phi[0]=0; phi[1]=0; phi[2]=0; return; }
    double ang = 2.0 * atan2(vn, qe[0]);       /* 旋转角 rad */
    phi[0] = ang*qe[1]/vn; phi[1] = ang*qe[2]/vn; phi[2] = ang*qe[3]/vn;
}

/* ========== 常量与参数（与 09 篇 sins_error_compare 同款） ========== */
#define G     9.8e0        /* 重力加速度 m/s^2 */
#define RE    6371e3       /* 地球平均半径 m */
#define WIE   7.292115e-5  /* 地球自转角速度 rad/s */
#define DEG   (M_PI/180.0)

int main(void)
{
#ifdef _WIN32
    /* Windows 中文乱码修复：源码 UTF-8、控制台默认 GBK(936)。
     * 方案：程序内把控制台切到 UTF-8 显示（Win10+ 现代终端均支持）。
     * 注意：不能用编译 flag -fexec-charset=GBK——本源码含 φ₀/ωₛ/− 等
     * Unicode 数学符号，GBK 无法表示（报 Illegal byte sequence）。 */
    SetConsoleOutputCP(CP_UTF8);
#endif
    /* —— 仿真参数 —— */
    double ts  = 0.1;                    /* 采样周期 10 Hz */
    double T   = 3600.0;                 /* 60 min */
    int    N   = (int)(T / ts);
    double bg  = 0.01 * DEG / 3600.0;    /* 东向陀螺零偏 0.01 deg/h → rad/s */
    double ba  = 10e-5;                  /* 北向加计零偏 10 mGal → m/s^2 */
    double phi0 = 5.0/60.0 * DEG;        /* 初始俯仰失准角 5' → rad */
    double ws  = sqrt(G/RE);             /* 舒勒角频率 */
    double Ts  = 2*M_PI/ws;              /* 舒勒周期 */

    /* —— 真值：静止水平，q_true = [1,0,0,0]，v=0，p=0 —— */
    const double qt[4] = { 1, 0, 0, 0 };

    /* —— 解算初值：带失准角（08 篇对准残差）。
     * 注入绕 -E(东)轴偏 φ0=5'：按讲义 φ_E 约定（正失准角→北向虚假加速度），
     * 等效讲义 φ_E = +5'（见下 qerr_phi 提取后取反显示） */
    double rv0[3] = { 0, -phi0, 0 };
    double q[4];  rv2q(rv0, q); qnorm(q);

    /* —— 解算状态 —— */
    double vn[3] = { 0, 0, 0 };               /* 速度误差（真实为 0） */
    double pn[3] = { 0, 0, 0 };               /* 位置误差（真实为 0） */

    printf("=== 纯惯导完整闭环 demo（静止基座, NED）===\n");
    printf("参数: %.0f Hz 采样 | %d s | 陀螺零偏 %.2f deg/h | 加计零偏 %.0f mGal | 初始失准角 %.0f'\n",
          1/ts, N, bg/DEG*3600, ba/1e-5, phi0/DEG*60);
    printf("舒勒周期 T_s = %.1f min（09 篇第五节的负反馈自稳定）\n", Ts/60);
    printf("\n t(min) | 失准角E(arcsec) | 速度N(m/s) | 位置N(km) | 位置E(km)\n");
    printf("--------+------------------+------------+-----------+-----------\n");

    double max_pos = 0;
    for (int i = 0; i < N; i++) {
        double t = i * ts;

        /* 1. 姿态更新（06/07 篇完整版）：
         *    ω_nb^b = ω_ib^b - C_b^n·ω_in^n
         *    - ω_ib^b：陀螺测量。静止时测地球自转 ω_ie（纬度 0 北向分量），
         *      由**真实姿态**决定 → 固定读数 [ω_ie,0,0]（加东向零偏）
         *      （新手常写死/或用解算矩阵投影——正确是固定读数，测量不受估计影响！）
         *    - ω_in^n = ω_ie^n + ω_en^n：n 系相对惯性系的转动
         *      · ω_ie^n = [ω_ie, 0, 0]（纬度 0 简化）
         *      · ω_en^n = [0, -v_N/R, 0]（北向速度让 n 系绕东轴转——舒勒反馈！
         *        符号：解算速度 v_N 偏大 → ω_in,E 减小 → 姿态被拉回）
         *    - 若省略 ω_in^n：姿态会以 ω_ie 速率漂移，且没有舒勒负反馈（发散） */
        double C[9]; q2Cbn(q, C);
        double wm[3] = { WIE*ts, bg*ts, 0 };    /* 固定读数 (ω_ib+零偏)·dt */
        double win_n[3] = { WIE, -vn[0]/RE, 0 };/* ω_in^n @纬度0（含舒勒反馈） */
        double win_b[3] = { 0, 0, 0 };          /* ω_in^b = C_n^b·ω_in^n */
        for (int r = 0; r < 3; r++)
            win_b[r] = C[0*3+r]*win_n[0] + C[1*3+r]*win_n[1] + C[2*3+r]*win_n[2];
        double wnb[3] = { wm[0]/ts - win_b[0], wm[1]/ts - win_b[1], wm[2]/ts - win_b[2] };
        /* 注意！wnb 是角速度(rad/s)，rv2q 要吃角增量(rad)——必须 ×ts！
         * 新手常犯：直接 rv2q(wnb)，等效把每帧旋转放大 1/ts 倍，
         * 舒勒周期会从 84.4min 缩到 84.4/√(1/ts)min（10Hz → 26.7min），
         * 位置误差幅度相应缩小 —— 典型"看起来像发散/振荡都对但数值不对"的坑 */
        double dphi[3] = { wnb[0]*ts, wnb[1]*ts, wnb[2]*ts };
        double dq[4]; rv2q(dphi, dq);
        qmul(q, q, dq); qnorm(q);

        /* 2. 比力投影（06 篇）：真实加计读数固定 [0,0,-G]（静止抵消重力，
         *    由真实姿态决定 → 不受解算影响），加北向零偏，C_b^n 转到导航系 */
        double fb[3] = { 0, ba, -G };
        double fn[3] = { 0, 0, 0 };
        for (int r = 0; r < 3; r++)
            fn[r] = C[r*3+0]*fb[0] + C[r*3+1]*fb[1] + C[r*3+2]*fb[2];

        /* 3. 速度更新（06 篇式 18）：v̇^n = C_b^n f^b + g^n */
        double gn[3] = { 0, 0, G };
        vn[0] += (fn[0] + gn[0]) * ts;
        vn[1] += (fn[1] + gn[1]) * ts;
        vn[2] += (fn[2] + gn[2]) * ts;

        /* 4. 位置更新（06 篇）：位置 = 速度积分（静止基座简化，无曲率项） */
        pn[0] += vn[0] * ts;
        pn[1] += vn[1] * ts;
        pn[2] += vn[2] * ts;

        /* 5. 误差提取（大角正确形式）——按讲义约定显示 φ_E = -提取值
         *    （注入 -φ0 使解算偏 -E 轴，讲义正失准角 → 北向虚假加速度） */
        double phi[3]; qerr_phi(qt, q, phi);

        if (i % 3000 == 0 || i == N-1) {
            printf("%6.1f | %16.2f | %10.3f | %9.3f | %9.3f\n",
                t/60, -phi[1]/DEG*3600, vn[0], pn[0]/1000, pn[1]/1000);
        }
        if (fabs(pn[0]) > max_pos) max_pos = fabs(pn[0]);
    }
    printf("--------+------------------+------------+-----------+-----------\n");

    /* ========== 解析解对照（09 篇式 68，北向位置误差） ========== */
    double t60 = T;
    double sint = sin(ws*t60), cost = cos(ws*t60);
    /* ① 初始失准角舒勒振荡: R*phi0*(1-cos) */
    double r_phi0 = RE * phi0 * (1 - cost);
    /* ④ 加计零偏有界振荡: (1-cos)/ws^2 * ba */
    double r_ba   = ba / (ws*ws) * (1 - cost);
    /* ⑤ 陀螺零偏线性发散: R*dw*(sin/ws - t) */
    double r_dwE  = RE * bg * (sint/ws - t60);
    double r_ana  = r_phi0 + r_ba + r_dwE;
    double r_num  = pn[0];

    printf("\n=== 解析解对照（09 篇式 68，北向位置误差 @60min）===\n");
    printf("  初始失准角舒勒振荡项  = %10.1f m（R·φ₀·(1−cos ωₛt)，有界）\n", r_phi0);
    printf("  加计零偏有界振荡项    = %10.1f m（(1−cos)/ωₛ²·δf，有界）\n", r_ba);
    printf("  陀螺零偏线性发散项    = %10.1f m（R·δω·(sin/ωₛ−t)，线性无界）\n", r_dwE);
    printf("  解析解合计            = %10.1f m\n", r_ana);
    printf("  数值解（本 demo）     = %10.1f m\n", r_num);
    printf("  差值                  = %10.2f m (%.2f%%)\n", r_num-r_ana, fabs(r_num-r_ana)/fabs(r_ana)*100);

    printf("\n=== 观察要点 ===\n");
    printf("1. 位置N 前 40 min 单调上升（舒勒振荡上升段），42 min 后回落——不是线性！\n");
    printf("2. 但陀螺零偏项让整个振荡的\"中心线\"持续下移（线性发散 1.35 km@60min）\n");
    printf("3. 对比 09 篇 sins_error_compare.png：蓝色舒勒峰 + 红色陀螺线性项\n");
    printf("4. 陀螺零偏 0.01 deg/h → 60 min 位置误差 %.0f m ≈ %.2f 海里（\"1 小时 1 海里\"）\n",
        r_dwE, r_dwE/1852.0);
    printf("5. 把 bg 改成 0.1 deg/h 再跑：线性项 ×10 = 13.5 km，30 min 就爆表——消费级陀螺\n");
    printf("   为什么必须外部辅助（GNSS/气压计），M3 组合导航就是来\"修正\"这条发散的\n");

    /* 运行结束前等待按键，避免双击 exe 时窗口一闪而过看不到结果
     * 中文乱码已由 main 开头 SetConsoleOutputCP(CP_UTF8) 解决（见上注释） */
    #ifdef _WIN32
        system("pause");
    #else
        printf("\nPress Enter to exit...\n");
        getchar();
    #endif

    return 0;
}
