#include "triad.h"

quat triad(v3 ib1, v3 ib2, v3 in1, v3 in2)
{
    /* 公式 6.1：两个正交标架的投影 Cbn = Tn · Tb'
     *   体标架 t1 = b1̂，t2 = (t1×b2)̂，t3 = t1×t2      （第 2 列的平行分量被叉乘丢掉）
     *   导航标架同构构造 → Cbn 把体向量投到导航系 */
    v3 t1 = unit3(ib1);
    v3 t2 = unit3(cross3(t1, ib2));
    v3 t3 = cross3(t1, t2);

    v3 r1 = unit3(in1);
    v3 r2 = unit3(cross3(r1, in2));
    v3 r3 = cross3(r1, r2);

    /* Tb/Tn 的第 k 列 = 第 k 个标架轴 */
    real_t Tb[3][3] = {{t1.x, t2.x, t3.x},
                       {t1.y, t2.y, t3.y},
                       {t1.z, t2.z, t3.z}};
    real_t Tn[3][3] = {{r1.x, r2.x, r3.x},
                       {r1.y, r2.y, r3.y},
                       {r1.z, r2.z, r3.z}};

    dcm C;
    int i, j, k;
    for (i = 0; i < 3; i++)
        for (j = 0; j < 3; j++) {
            real_t s = 0;
            for (k = 0; k < 3; k++) s += Tn[i][k] * Tb[j][k];   /* (Tn·Tb')(i,j) */
            C.m[i][j] = s;
        }
    return dcm2q(C);
}
