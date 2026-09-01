/* test_triad.c - TRIAD 对拍
 * 输入行（13 列）：code, ib1(3), ib2(3), in1(3), in2(3)
 * 输出行（4 列）：q(4)（体→导航，w>0）
 * 用法：test_triad <in.csv> <out.csv>
 */
#include <stdio.h>
#include "triad.h"

int main(int argc, char **argv)
{
    const char *fin  = (argc > 1) ? argv[1] : "tv_triad_in.csv";
    const char *fout = (argc > 2) ? argv[2] : "out_triad.csv";
    FILE *fi = fopen(fin, "r");
    FILE *fo = fopen(fout, "w");
    if (!fi || !fo) { fprintf(stderr, "open fail\n"); return 1; }

    double f[13];
    while (fscanf(fi, "%lf,%lf,%lf,%lf,%lf,%lf,%lf,%lf,%lf,%lf,%lf,%lf,%lf",
                  &f[0], &f[1], &f[2], &f[3], &f[4], &f[5], &f[6], &f[7],
                  &f[8], &f[9], &f[10], &f[11], &f[12]) == 13) {
        v3 ib1 = v_make((real_t)f[1], (real_t)f[2], (real_t)f[3]);
        v3 ib2 = v_make((real_t)f[4], (real_t)f[5], (real_t)f[6]);
        v3 in1 = v_make((real_t)f[7], (real_t)f[8], (real_t)f[9]);
        v3 in2 = v_make((real_t)f[10], (real_t)f[11], (real_t)f[12]);
        quat q = triad(ib1, ib2, in1, in2);
        fprintf(fo, "%.17g,%.17g,%.17g,%.17g\n", (double)q.w, (double)q.x,
                (double)q.y, (double)q.z);
    }
    fclose(fi); fclose(fo);
    return 0;
}
