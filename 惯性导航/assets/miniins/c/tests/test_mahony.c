/* test_mahony.c - Mahony 单步更新对拍（流式）
 *
 * 输入行（12 列）：code, v1..v11
 *   code=0 初始化：att0(3)=[roll;pitch;yaw], Kp, Ki, lat, dec, 0,0,0,0
 *   code=1 更新步：wm(3), vm(3), mag(3), ts, use_mag
 * 输出行（7 列，每个 code=1 一行）：q(4), exyzInt(3)
 *
 * 用法：test_mahony <in.csv> <out.csv>
 */
#include <stdio.h>
#include "mahony.h"

int main(int argc, char **argv)
{
    const char *fin  = (argc > 1) ? argv[1] : "tv_mahony_in.csv";
    const char *fout = (argc > 2) ? argv[2] : "out_mahony.csv";
    FILE *fi = fopen(fin, "r");
    FILE *fo = fopen(fout, "w");
    if (!fi || !fo) { fprintf(stderr, "open fail\n"); return 1; }

    ahrs_t a;
    int inited = 0;
    double f[12];
    while (fscanf(fi, "%lf,%lf,%lf,%lf,%lf,%lf,%lf,%lf,%lf,%lf,%lf,%lf",
                  &f[0], &f[1], &f[2], &f[3], &f[4], &f[5], &f[6], &f[7],
                  &f[8], &f[9], &f[10], &f[11]) == 12) {
        int code = (int)f[0];
        if (code == 0) {                                  /* 初始化 */
            v3 att0 = v_make((real_t)f[1], (real_t)f[2], (real_t)f[3]);
            ahrs_init(&a, att0, (real_t)f[4], (real_t)f[5], (real_t)f[6], (real_t)f[7]);
            inited = 1;
        } else if (code == 1 && inited) {                 /* 单步更新 */
            v3 wm  = v_make((real_t)f[1],  (real_t)f[2],  (real_t)f[3]);
            v3 vm  = v_make((real_t)f[4],  (real_t)f[5],  (real_t)f[6]);
            v3 mag = v_make((real_t)f[7],  (real_t)f[8],  (real_t)f[9]);
            ahrs_update(&a, wm, vm, mag, (real_t)f[10], (int)f[11]);
            fprintf(fo, "%.17g,%.17g,%.17g,%.17g,%.17g,%.17g,%.17g\n",
                    (double)a.q.w, (double)a.q.x, (double)a.q.y, (double)a.q.z,
                    (double)a.exyzInt.x, (double)a.exyzInt.y, (double)a.exyzInt.z);
        }
    }
    fclose(fi); fclose(fo);
    return 0;
}
