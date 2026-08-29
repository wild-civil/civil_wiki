function gen_tv()
% gen_tv - 生成 NED+FRD 约定的测试向量 + MATLAB oracle 期望输出（SIL 对拍用）
%
% 输出（sil/data/）：
%   tv_trans_in.csv  (11 列: code + 10 值)   → out_trans.csv  (10 列: code + 9 值)
%   tv_triad_in.csv  (13 列: code + 12 值)   → out_triad.csv  (4 列)
%   tv_mahony_in.csv (12 列: code + 11 值)   → out_mahony.csv (7 列)
%   *_exp.csv        与上面 out_* 同格式的 oracle 期望值
%   truth_mahony.csv Mahony 序列的真值姿态（功能性检查用）
%
% 约定：导航系 NED（x北 y东 z下）、机体系 FRD、att = [roll; pitch; yaw]。
% 与 miniins MATLAB 版（ENU + PSINS 机体）的差异：参考向量取值与 att↔DCM 转换，
% 四元数/矩阵代数本身完全一致（故 trans 类可 1:1 对拍）。

root = fullfile(fileparts(mfilename('fullpath')), '..');
addpath(fullfile(root, '..', 'core'));                 % glvs()
glv = glvs();  deg = glv.deg;  dph = glv.deg/3600;
d = fullfile(fileparts(mfilename('fullpath')), 'data');
if exist(d, 'dir') ~= 7, mkdir(d); end
rng(20260829);                                         % 确定性

W   = @(p, v) writematrix_row(p, v);                   % 逐行追加（见末）
N   = 30;
lat = 29*deg;  dec = -7*deg;  dip = 58*deg;  mH = 28000;
m_n = [mH*cos(dec); mH*sin(dec); mH*tan(dip)];         % NED 地磁（含磁偏角/磁倾角）

%% ---------- 1) trans 系列 ----------
fin = fullfile(d, 'tv_trans_in.csv');  fex = fullfile(d, 'tv_trans_exp.csv');
delete(fin); delete(fex);
atts = [(rand(N,1)-0.5)*300*deg, (rand(N,1)-0.5)*150*deg, (rand(N,1)-0.5)*340*deg];  % |pitch|<75°
for i = 1:N
    att = atts(i,:)';
    q   = qsignfix(att2q_ned(att));                    % 真值四元数（三次基本旋转复合 + w>0 归一）
    C   = a2dcm_ned(att);
    W(fin, [1, qrow(q), zeros(1,6)]);                  % code1: q2dcm
    W(fex, [1, reshape(C', 1, 9)]);                    % 期望 DCM（行优先）
    W(fin, [2, reshape(C', 1, 9), 0]);                 % code2: dcm2q
    W(fex, [2, qrow(q), zeros(1,5)]);
    W(fin, [5, att', zeros(1,7)]);                     % code5: a2dcm
    W(fex, [5, reshape(C', 1, 9)]);
    W(fin, [6, reshape(C', 1, 9), 0]);                 % code6: dcm2att
    W(fex, [6, att', zeros(1,6)]);
end
for i = 1:20
    rv = (rand(3,1)-0.5)*0.5;
    W(fin, [3, rv', zeros(1,7)]);                      % code3: rv2q
    W(fex, [3, qrow(rv2q_ned(rv)), zeros(1,5)]);
    qa = qnorm_ned(randn(4,1));  qb = qnorm_ned(randn(4,1));
    W(fin, [4, qrow(qa), qrow(qb), 0, 0]);             % code4: qmul
    W(fex, [4, qrow(qmul_ned(qa, qb)), zeros(1,5)]);
end

%% ---------- 2) TRIAD ----------
fin2 = fullfile(d, 'tv_triad_in.csv');  fex2 = fullfile(d, 'tv_triad_exp.csv');
delete(fin2); delete(fex2);
for i = 1:20
    att = [(rand-0.5)*300*deg; (rand-0.5)*150*deg; (rand-0.5)*340*deg];
    C   = a2dcm_ned(att);
    ib1 = C'*[0; 0; -1];                               % 加计方向（准静态：比力朝上 = NED 的 −z）
    ib2 = C'*m_n;                                      % 体磁
    W(fin2, [1, ib1', ib2', [0;0;-1]', m_n']);
    W(fex2, qrow(qsignfix(att2q_ned(att))));           % 期望：恢复出真值四元数（w>0）
end

%% ---------- 3) Mahony（两段：静止 + 水平加速，覆盖门控两条分支） ----------
fin3 = fullfile(d, 'tv_mahony_in.csv');  fex3 = fullfile(d, 'tv_mahony_exp.csv');
ftr  = fullfile(d, 'truth_mahony.csv');
delete(fin3); delete(fex3); delete(ftr);
ts = 0.01;
seq = { struct('T',10, 'a2',0), struct('T',5, 'a2',0.25) };   % 静止 10 s + 加速 5 s
att0_true = [0; 0; 0];   att0_est = [3*deg; -2*deg; 5*deg];
eb = [50; -30; 20]*dph;
for si = 1:numel(seq)
    T = seq{si}.T;  a2 = seq{si}.a2;
    a = ahrs_init_ned(att0_est, 1.0, 0.1, lat, dec);
    W(fin3, [0, att0_est', 1.0, 0.1, lat, dec, 0, 0, 0, 0]);
    attT = att0_true;  Ct = a2dcm_ned(attT);          % 真值（本序列姿态恒定）
    vn = [0; 0; 0];
    for k = 1:round(T/ts)
        % 真值运动：前向加速 a2（NED 北向，机头朝北时即体 x）
        if a2 > 0, vn = vn + [a2; 0; 0]*ts; end
        an   = [a2; 0; 0];                            % 运动加速度（导航系，机头朝北）
        fb_n = an - [0; 0; glv.g0];                   % 比力 = a − G；NED 的 G = [0;0;+g]（z 朝下）
        vm   = Ct'*fb_n*ts;                            % 加计增量（体）
        wm   = (Ct'*a.wnie + eb)*ts;                   % 陀螺增量（体）
        mag  = Ct'*m_n;                                % 磁测量（体）
        W(fin3, [1, wm', vm', mag', ts, 1]);
        a = ahrs_update_ned(a, wm, vm, mag, ts, 1);
        W(fex3, [a.q', a.exyzInt']);
        W(ftr,  attT');
    end
end
fprintf('gen_tv: 测试向量已写入 %s\n', d);
end

%% ================= 局部函数：NED+FRD 参考实现（oracle） =================
function r = qrow(q), r = reshape(q, 1, numel(q)); end

function q = qnorm_ned(q), q = q/norm(q); end

function q = qsignfix(q)
% q 与 −q 表示同一旋转，但数值差一个整体负号；C 版 dcm2q/triad 统一强制 w>0，
% 故 oracle 的期望四元数也必须做同样归一，否则大角度例会误报 ~2 的"误差"。
if q(1) < 0, q = -q; end
end

function q = att2q_ned(att)
% 三次基本旋转复合（独立构造真值 q，避免与 dcm2q 循环论证）
q = qmul_ned(qmul_ned(rv2q_ned([0;0;att(3)]), rv2q_ned([0;att(2);0])), rv2q_ned([att(1);0;0]));
end

function q = rv2q_ned(rv)
n = norm(rv);
if n < 1e-12, q = [1; rv/2];  else, q = [cos(n/2); sin(n/2)/n*rv];  end
q = q/norm(q);
end

function q = qmul_ned(a, b)
q = [a(1)*b(1) - a(2)*b(2) - a(3)*b(3) - a(4)*b(4);
     a(1)*b(2) + a(2)*b(1) + a(3)*b(4) - a(4)*b(3);
     a(1)*b(3) - a(2)*b(4) + a(3)*b(1) + a(4)*b(2);
     a(1)*b(4) + a(2)*b(3) - a(3)*b(2) + a(4)*b(1)];
end

function C = q2dcm_ned(q)
w=q(1); x=q(2); y=q(3); z=q(4);
C = [1-2*(y^2+z^2),   2*(x*y-z*w),   2*(x*z+y*w);
       2*(x*y+z*w), 1-2*(x^2+z^2),   2*(y*z-x*w);
       2*(x*z-y*w),   2*(y*z+x*w), 1-2*(x^2+y^2)];
end

function C = a2dcm_ned(att)
sr=sin(att(1)); cr=cos(att(1)); sp=sin(att(2)); cp=cos(att(2)); sy=sin(att(3)); cy=cos(att(3));
C = [ cp*cy,  sr*sp*cy - cr*sy,  cr*sp*cy + sr*sy;
      cp*sy,  sr*sp*sy + cr*cy,  cr*sp*sy - sr*cy;
       -sp,              sr*cp,             cr*cp];
end

function att = dcm2att_ned(C)
att = [atan2(C(3,2), C(3,3)); asin(max(-1, min(1, -C(3,1)))); atan2(C(2,1), C(1,1))];
end

function q = dcm2q_ned(C)
% Shepperd 法（与 C 版 dcm2q 逐行同构），最后强制 w>0
tr = trace(C);
if tr > 0
    s = sqrt(tr+1)*2;  q = [0.25*s; (C(3,2)-C(2,3))/s; (C(1,3)-C(3,1))/s; (C(2,1)-C(1,2))/s];
elseif C(1,1) > C(2,2) && C(1,1) > C(3,3)
    s = sqrt(1+C(1,1)-C(2,2)-C(3,3))*2;  q = [(C(3,2)-C(2,3))/s; 0.25*s; (C(1,2)+C(2,1))/s; (C(1,3)+C(3,1))/s];
elseif C(2,2) > C(3,3)
    s = sqrt(1+C(2,2)-C(1,1)-C(3,3))*2;  q = [(C(1,3)-C(3,1))/s; (C(1,2)+C(2,1))/s; 0.25*s; (C(2,3)+C(3,2))/s];
else
    s = sqrt(1+C(3,3)-C(1,1)-C(2,2))*2;  q = [(C(2,1)-C(1,2))/s; (C(1,3)+C(3,1))/s; (C(2,3)+C(3,2))/s; 0.25*s];
end
if q(1) < 0, q = -q; end
q = q/norm(q);
end

function q = triad_ned(ib1, ib2, in1, in2)
t1 = ib1/norm(ib1);  t2 = cross(t1, ib2);  t2 = t2/norm(t2);  t3 = cross(t1, t2);
r1 = in1/norm(in1);  r2 = cross(r1, in2);  r2 = r2/norm(r2);  r3 = cross(r1, r2);
C  = [r1 r2 r3] * [t1 t2 t3]';
q  = dcm2q_ned(C);
end

function a = ahrs_init_ned(att0, Kp, Ki, lat, dec)
glv = glvs();
C = a2dcm_ned(att0);
a.q = dcm2q_ned(C);  a.C = C;  a.exyzInt = zeros(3,1);
a.Kp = Kp;  a.Ki = Ki;
a.wnie = [glv.wie*cos(lat); 0; -glv.wie*sin(lat)];     % NED
a.dec = dec;  a.g0 = glv.g0;  a.tk = 0;
end

function a = ahrs_update_ned(a, wm, vm, mag, ts, use_mag)
% 与 C 版 src/mahony.c 逐行同构的 NED 参考实现
f = vm/ts;  nmf = norm(f);
if nmf > 0, acc = f/nmf;  else, acc = [0;0;0];  end
nm1 = abs(nmf - a.g0);
if nm1 <= 0.05, lam = 1;
elseif nm1 >= 0.20, lam = 0;
else, lam = (0.20 - nm1)/(0.20 - 0.05);
end
e = zeros(3,1);
if lam > 0
    up_b = -a.C(3,:)';                                  % NED：上是 −z（ENU 版为正）
    e = lam * cross(up_b, acc);
end
if use_mag && norm(mag) > 0
    m = mag/norm(mag);
    mn = a.C*m;
    mh = norm(mn(1:2));
    mn(1:2) = mh*[cos(a.dec); sin(a.dec)];              % 磁北（N/E 分量）
    mp = a.C'*mn;
    e = e + cross(mp, m);
end
a.exyzInt = a.exyzInt + e*a.Ki*ts;
eb = a.Kp*e + a.exyzInt;
phim = wm - (a.C'*a.wnie + eb)*ts;
a.q = qmul_ned(a.q, rv2q_ned(phim));  a.q = a.q/norm(a.q);
a.C = q2dcm_ned(a.q);  a.tk = a.tk + ts;
end

function writematrix_row(path, v)
fid = fopen(path, 'a');
fprintf(fid, '%.17g', v(1));
for i = 2:numel(v), fprintf(fid, ',%.17g', v(i)); end
fprintf(fid, '\n');
fclose(fid);
end
