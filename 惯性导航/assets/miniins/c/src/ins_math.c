#include "ins_math.h"

/* 常量（与 MATLAB glvs.m 一致） */
#define WIE 7.2921151467e-5      /* 地球自转角速度 rad/s */
#define G0  9.7803267714         /* 赤道标准重力 m/s² */

real_t glv_wie(void) { return (real_t)WIE; }
real_t glv_g0(void)  { return (real_t)G0;  }

quat q_make(real_t w, real_t x, real_t y, real_t z)
{ quat q; q.w = w; q.x = x; q.y = y; q.z = z; return q; }

v3 v_make(real_t x, real_t y, real_t z)
{ v3 v; v.x = x; v.y = y; v.z = z; return v; }

/* ---------------- 向量运算 ---------------- */
v3 cross3(v3 a, v3 b)
{ return v_make(a.y*b.z - a.z*b.y, a.z*b.x - a.x*b.z, a.x*b.y - a.y*b.x); }

real_t dot3(v3 a, v3 b) { return a.x*b.x + a.y*b.y + a.z*b.z; }

v3 add3(v3 a, v3 b) { return v_make(a.x+b.x, a.y+b.y, a.z+b.z); }

v3 sub3(v3 a, v3 b) { return v_make(a.x-b.x, a.y-b.y, a.z-b.z); }

v3 scale3(v3 a, real_t s) { return v_make(a.x*s, a.y*s, a.z*s); }

real_t norm3(v3 a) { return (real_t)sqrt(dot3(a, a)); }

v3 unit3(v3 a)
{
    real_t n = norm3(a);
    if (n < (real_t)1e-15) return v_make(0, 0, 0);
    return scale3(a, (real_t)1.0 / n);
}

/* ---------------- 四元数运算 ---------------- */
quat q_mul(quat a, quat b)
{
    /* Hamilton 积 a⊗b（与 miniins core/qmul.m 逐项一致） */
    return q_make(a.w*b.w - a.x*b.x - a.y*b.y - a.z*b.z,
                  a.w*b.x + a.x*b.w + a.y*b.z - a.z*b.y,
                  a.w*b.y - a.x*b.z + a.y*b.w + a.z*b.x,
                  a.w*b.z + a.x*b.y - a.y*b.x + a.z*b.w);
}

quat q_conj(quat q) { return q_make(q.w, -q.x, -q.y, -q.z); }

quat q_norm(quat q)
{
    real_t n = (real_t)sqrt(q.w*q.w + q.x*q.x + q.y*q.y + q.z*q.z);
    if (n < (real_t)1e-15) return q_make(1, 0, 0, 0);
    return q_make(q.w/n, q.x/n, q.y/n, q.z/n);
}

quat rv2q(v3 rv)
{
    /* q = [cos(θ/2); sin(θ/2)/θ · rv]，θ=|rv|（与 miniins core/rv2q.m 一致） */
    real_t n2 = dot3(rv, rv);
    real_t n  = (real_t)sqrt(n2);
    if (n < (real_t)1e-12) return q_norm(q_make(1, rv.x/2, rv.y/2, rv.z/2));
    real_t s = (real_t)sin(n/2) / n;
    return q_make((real_t)cos(n/2), rv.x*s, rv.y*s, rv.z*s);
}

v3 qmulv(quat q, v3 v)
{
    /* v' = q ⊗ v ⊗ q* = v + 2·qw·(qv×v) + 2·qv×(qv×v) */
    v3 qv = v_make(q.x, q.y, q.z);
    v3 t  = cross3(qv, v);
    t = v_make(t.x + q.w*v.x, t.y + q.w*v.y, t.z + q.w*v.z);
    v3 c  = cross3(qv, t);
    return v_make(v.x + 2*c.x, v.y + 2*c.y, v.z + 2*c.z);
}

/* ---------------- 姿态阵 ---------------- */
dcm q2dcm(quat q)
{
    /* 与 miniins core/q2cnb.m 公式 2.3 逐项一致（纯代数，与机体系约定无关） */
    real_t w = q.w, x = q.x, y = q.y, z = q.z;
    dcm C;
    C.m[0][0] = 1 - 2*(y*y + z*z); C.m[0][1] = 2*(x*y - z*w);   C.m[0][2] = 2*(x*z + y*w);
    C.m[1][0] = 2*(x*y + z*w);     C.m[1][1] = 1 - 2*(x*x + z*z); C.m[1][2] = 2*(y*z - x*w);
    C.m[2][0] = 2*(x*z - y*w);     C.m[2][1] = 2*(y*z + x*w);     C.m[2][2] = 1 - 2*(x*x + y*y);
    return C;
}

quat dcm2q(dcm C)
{
    /* Shepperd 法：先按 trace 选最大分支再取分量，数值稳定；最后归一并强制 w>0 */
    real_t tr = C.m[0][0] + C.m[1][1] + C.m[2][2];
    quat q;
    if (tr > 0) {
        real_t s = (real_t)sqrt(tr + 1) * 2;              /* s = 4w */
        q.w = (real_t)0.25 * s;
        q.x = (C.m[2][1] - C.m[1][2]) / s;
        q.y = (C.m[0][2] - C.m[2][0]) / s;
        q.z = (C.m[1][0] - C.m[0][1]) / s;
    } else if (C.m[0][0] > C.m[1][1] && C.m[0][0] > C.m[2][2]) {
        real_t s = (real_t)sqrt(1 + C.m[0][0] - C.m[1][1] - C.m[2][2]) * 2;
        q.w = (C.m[2][1] - C.m[1][2]) / s;
        q.x = (real_t)0.25 * s;
        q.y = (C.m[0][1] + C.m[1][0]) / s;
        q.z = (C.m[0][2] + C.m[2][0]) / s;
    } else if (C.m[1][1] > C.m[2][2]) {
        real_t s = (real_t)sqrt(1 + C.m[1][1] - C.m[0][0] - C.m[2][2]) * 2;
        q.w = (C.m[0][2] - C.m[2][0]) / s;
        q.x = (C.m[0][1] + C.m[1][0]) / s;
        q.y = (real_t)0.25 * s;
        q.z = (C.m[1][2] + C.m[2][1]) / s;
    } else {
        real_t s = (real_t)sqrt(1 + C.m[2][2] - C.m[0][0] - C.m[1][1]) * 2;
        q.w = (C.m[1][0] - C.m[0][1]) / s;
        q.x = (C.m[0][2] + C.m[2][0]) / s;
        q.y = (C.m[1][2] + C.m[2][1]) / s;
        q.z = (real_t)0.25 * s;
    }
    if (q.w < 0) { q.w = -q.w; q.x = -q.x; q.y = -q.y; q.z = -q.z; }
    return q_norm(q);
}

v3 mv3(dcm C, v3 v)
{
    return v_make(C.m[0][0]*v.x + C.m[0][1]*v.y + C.m[0][2]*v.z,
                  C.m[1][0]*v.x + C.m[1][1]*v.y + C.m[1][2]*v.z,
                  C.m[2][0]*v.x + C.m[2][1]*v.y + C.m[2][2]*v.z);
}

v3 tmv3(dcm C, v3 v)
{
    return v_make(C.m[0][0]*v.x + C.m[1][0]*v.y + C.m[2][0]*v.z,
                  C.m[0][1]*v.x + C.m[1][1]*v.y + C.m[2][1]*v.z,
                  C.m[0][2]*v.x + C.m[1][2]*v.y + C.m[2][2]*v.z);
}

v3 drow(dcm C, int i) { return v_make(C.m[i][0], C.m[i][1], C.m[i][2]); }

/* ---------------- 约定相关：NED + FRD ---------------- */
dcm a2dcm(v3 att)
{
    /* Cbn = Rz(yaw)·Ry(pitch)·Rx(roll)，att = [roll; pitch; yaw]（航空惯例） */
    real_t sr = (real_t)sin(att.x), cr = (real_t)cos(att.x);   /* roll  绕 x(前) */
    real_t sp = (real_t)sin(att.y), cp = (real_t)cos(att.y);   /* pitch 绕 y(右) */
    real_t sy = (real_t)sin(att.z), cy = (real_t)cos(att.z);   /* yaw   绕 z(下) */
    dcm C;
    C.m[0][0] =  cp*cy;  C.m[0][1] = sr*sp*cy - cr*sy;  C.m[0][2] = cr*sp*cy + sr*sy;
    C.m[1][0] =  cp*sy;  C.m[1][1] = sr*sp*sy + cr*cy;  C.m[1][2] = cr*sp*sy - sr*cy;
    C.m[2][0] = -sp;     C.m[2][1] = sr*cp;             C.m[2][2] = cr*cp;
    return C;
}

v3 dcm2att(dcm C)
{
    /* 逆变换：roll=atan2(C32,C33)、pitch=−asin(C31)、yaw=atan2(C21,C11) */
    real_t s = -C.m[2][0];
    if (s >  1) s =  1;                                        /* 防 asin 定义域溢出 */
    if (s < -1) s = -1;
    return v_make((real_t)atan2(C.m[2][1], C.m[2][2]),
                  (real_t)asin(s),
                  (real_t)atan2(C.m[1][0], C.m[0][0]));
}

v3 wnie_ned(real_t lat)
{
    /* NED：北分量 wie·cosL，东分量 0，地分量 −wie·sinL（z 轴朝下） */
    return v_make((real_t)(WIE * cos(lat)), 0, (real_t)(-WIE * sin(lat)));
}
