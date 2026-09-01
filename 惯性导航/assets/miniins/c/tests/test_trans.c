/* test_trans.c - trans 系列对拍：读 CSV 测试向量，输出结果 CSV
 *
 * 输入行（11 列）：code, v1..v10
 *   code=1 q2dcm   : q(4)                  → 输出 9（DCM，行优先）
 *   code=2 dcm2q   : C(9)                  → 输出 4（q，w>0）
 *   code=3 rv2q    : rv(3)                 → 输出 4
 *   code=4 qmul    : qa(4), qb(4)          → 输出 4
 *   code=5 a2dcm   : att(3)=[roll;pitch;yaw] → 输出 9
 *   code=6 dcm2att : C(9)                  → 输出 3
 * 输出行（10 列）：code, o1..o9（不足补 0）
 *
 * 用法：test_trans <in.csv> <out.csv>
 */
#include <stdio.h>
#include "ins_math.h"

int main(int argc, char **argv)
{
    const char *fin  = (argc > 1) ? argv[1] : "tv_trans_in.csv";
    const char *fout = (argc > 2) ? argv[2] : "out_trans.csv";
    FILE *fi = fopen(fin, "r");
    FILE *fo = fopen(fout, "w");
    if (!fi || !fo) { fprintf(stderr, "open fail: %s / %s\n", fin, fout); return 1; }

    double f[11];
    while (fscanf(fi, "%lf,%lf,%lf,%lf,%lf,%lf,%lf,%lf,%lf,%lf,%lf",
                  &f[0], &f[1], &f[2], &f[3], &f[4], &f[5], &f[6],
                  &f[7], &f[8], &f[9], &f[10]) == 11) {
        int code = (int)f[0];
        double o[9] = {0, 0, 0, 0, 0, 0, 0, 0, 0};
        int n = 0;

        if (code == 1) {                                   /* q2dcm */
            quat q = q_norm(q_make((real_t)f[1], (real_t)f[2], (real_t)f[3], (real_t)f[4]));
            dcm C = q2dcm(q);
            for (int i = 0; i < 3; i++) for (int j = 0; j < 3; j++) o[i*3+j] = C.m[i][j];
            n = 9;
        } else if (code == 2) {                            /* dcm2q */
            dcm C;
            for (int i = 0; i < 3; i++) for (int j = 0; j < 3; j++) C.m[i][j] = (real_t)f[1 + i*3 + j];
            quat q = dcm2q(C);
            o[0] = q.w; o[1] = q.x; o[2] = q.y; o[3] = q.z; n = 4;
        } else if (code == 3) {                            /* rv2q */
            v3 rv = v_make((real_t)f[1], (real_t)f[2], (real_t)f[3]);
            quat q = rv2q(rv);
            o[0] = q.w; o[1] = q.x; o[2] = q.y; o[3] = q.z; n = 4;
        } else if (code == 4) {                            /* qmul */
            quat a = q_make((real_t)f[1], (real_t)f[2], (real_t)f[3], (real_t)f[4]);
            quat b = q_make((real_t)f[5], (real_t)f[6], (real_t)f[7], (real_t)f[8]);
            quat q = q_mul(a, b);
            o[0] = q.w; o[1] = q.x; o[2] = q.y; o[3] = q.z; n = 4;
        } else if (code == 5) {                            /* a2dcm (NED+FRD) */
            v3 att = v_make((real_t)f[1], (real_t)f[2], (real_t)f[3]);
            dcm C = a2dcm(att);
            for (int i = 0; i < 3; i++) for (int j = 0; j < 3; j++) o[i*3+j] = C.m[i][j];
            n = 9;
        } else if (code == 6) {                            /* dcm2att (NED+FRD) */
            dcm C;
            for (int i = 0; i < 3; i++) for (int j = 0; j < 3; j++) C.m[i][j] = (real_t)f[1 + i*3 + j];
            v3 att = dcm2att(C);
            o[0] = att.x; o[1] = att.y; o[2] = att.z; n = 3;
        }

        fprintf(fo, "%d", code);
        for (int i = 0; i < 9; i++) fprintf(fo, ",%.17g", o[i]);
        fprintf(fo, "\n");
        (void)n;
    }
    fclose(fi); fclose(fo);
    return 0;
}
