function gen_sins()
% 拆解 PSINS ②：迷你链路 = 迷你 trjsimu + 误差注入 + 迷你 inspure（纯 MATLAB，与 gen_sins.py 双轨）
% =====================================================================================
% 复刻 test_SINS.m 的数据流，但全部自包含（不依赖 PSINS）：
%   [生成] wat 表（P1 产物，21 行硬编码）-> 迷你 trjsimu 数值积分出 真值 avp + imu 增量
%   [注入] 确定性误差：eb=0.01°/h 陀螺零偏、db=100µg 加计零偏、初始姿态误差 [0.5;0.5;5]'
%   [解算] 迷你 inspure（nn=2 双子样机械编排：cnscl 圆锥/划桨 + earth + 速度/位置/姿态更新）
%   [分析] 解算 vs 真值：姿态/速度/位置误差（Schuler 振荡、水平漂移、高度通道）
% 高度阻尼选项：free（自由）/ fix（固定真值高度，= test_SINS 的 trj.bh 作用）
% 教学简化（对拍 PSINS 时允许的差异）：随机游走省略（确定性）、trjsimu 无匀速阻尼。
% 无工具箱依赖，运行：gen_sins

% ---------------- 常量（与 PSINS glvf 对齐） ----------------
Re = 6378137.0;  f = 1/298.257;  wie = 7.2921151467e-5;  g0 = 9.7803267715;
e2 = 2*f - f*f;
deg = pi/180;  dph = pi/180/3600;  ug = 1e-6*g0;
ts = 0.01;                       % 100 Hz

% ---------------- wat 表（P1 产物：test_SINS_trj 展开 21 行） ----------------
% 列：[时长s, 初速m/s, w1, w2, w3(rad/s), a1, a2, a3(m/s²)]（w/a 已转 rad）
WAT = [ ...
 100,  0,  0,      0,     0,      0,      0,     0;
  10,  0,  0,      0,     0,      0,      1,     0;
 100, 10,  0,      0,     0,      0,      0,     0;
   4, 10,  0, -0.51*deg, 0,      0,      0,     0;
  45, 10,  0,      0, 2.00*deg, -0.349,  0,     0;
   4, 10,  0,  0.51*deg, 0,      0,      0,     0;
 100, 10,  0,      0,     0,      0,      0,     0;
   4, 10,  0,  2.28*deg, 0,      0,      0,     0;
  50, 10,  0,      0,-9.00*deg,  1.571,  0,     0;
   4, 10,  0, -2.28*deg, 0,      0,      0,     0;
 100, 10,  0,      0,     0,      0,      0,     0;
  10, 10, 2.00*deg, 0, 0,        0,      0, 0.349;
  50, 10,  0,      0,     0,      0,      0,     0;
  10, 10,-2.00*deg, 0, 0,        0,      0,-0.349;
 100, 10,  0,      0,     0,      0,      0,     0;
  10, 10,-2.00*deg, 0, 0,        0,      0,-0.349;
  50, 10,  0,      0,     0,      0,      0,     0;
  10, 10, 2.00*deg, 0, 0,        0,      0, 0.349;
 100, 10,  0,      0,     0,      0,      0,     0;
   5, 10,  0,      0,     0,      0,     -2,     0;
 100,  0,  0,      0,     0,      0,      0,     0 ];

avp0 = [0;0;0; 0;0;0; 29*deg; 106*deg; 450.0];

fprintf('%s\n', repmat('=', 1, 70));
fprintf('拆解 PSINS ②：迷你链路 = 迷你 trjsimu + 误差注入 + 迷你 inspure\n');
fprintf('%s\n', repmat('=', 1, 70));

fprintf('\n[1] 迷你 trjsimu：966 s 轨迹生成（100 Hz，双子样增量）\n');
[imu, trj] = minitrj(avp0, WAT, ts);
fprintf('    行数 = %d（期望 96600），末位置 = (%.4f°, %.4f°, %.1f m)\n', ...
        size(imu,1), trj(end,7)/deg, trj(end,8)/deg, trj(end,9));

fprintf('\n[2] 确定性误差注入（eb=0.01°/h, db=100µg, att err [0.5;0.5;5]'', vn 0.1, pos 10m）\n');
eb = [0.01;0.01;0.01]*dph;
db = [100.;100.;100.]*ug;
imu_e = imu;
imu_e(:,1:3) = imu_e(:,1:3) + (eb*ts)';
imu_e(:,4:6) = imu_e(:,4:6) + (db*ts)';
att0e = avp0(1:3) + ([0.5;0.5;5.0]*(deg/60));
avp0e = [att0e; 0.1;0.1;0.1; avp0(7)+10/Re; avp0(8)+10/(Re*cos(avp0(7))); avp0(9)+10];

fprintf('\n[3] 迷你 inspure（nn=2 双子样机械编排）\n');
avp_free = miniinspure(imu_e, avp0e, false);
avp_fix  = miniinspure(imu_e, avp0e, true);
Re_h = Re + avp0(9);
pe = pos_err_m(avp_free(end,7:9)-trj(end,7:9), avp0, Re_h);
pf = pos_err_m(avp_fix(end,7:9)-trj(end,7:9),  avp0, Re_h);
fprintf('    高度自由:  末点位置误差 = (%.1f, %.1f, %.1f) m\n', pe(1), pe(2), pe(3));
fprintf('    高度固定:  末点位置误差 = (%.1f, %.1f, %.1f) m\n', pf(1), pf(2), pf(3));

fprintf('\n[4] 误差传播分析（vs 真值，966 s）\n');
errstats('高度自由', avp_free, trj, avp0, Re_h, deg);
errstats('高度固定', avp_fix,  trj, avp0, Re_h, deg);

fprintf('\n[5] 教学要点\n');
fprintf('    陀螺零偏 eb -> 姿态误差(线性增长) -> 位置误差(Schuler 振荡 ~84min 周期) -> 水平漂移 km 级\n');
fprintf('    高度通道开环不稳定(垂直 Schuler ~9min 周期发散) -> test_SINS 用 trj.bh 固定高度(高度阻尼)\n');
fprintf('    mini vs PSINS：随机游走/trjsimu 阻尼差异，量级形态一致（对拍数字见 P2 正文）\n');

fprintf('\n[6] 可视化（迷你 insplot / avpcmpplot，零依赖自写，参考 PSINS 布局）\n');
miniinsplot(trj,    'truth');   % 真值轨迹（最像 PSINS test_SINS_trj 的 insplot(trj.avp)）
miniinsplot(avp_fix, 'fix');    % 高度阻尼解算轨迹
miniinsplot(avp_free, 'free');  % 高度自由解算轨迹
miniavpcmpplot(trj, {avp_free, avp_fix}, {'free','fix'});
% 方案 B：真值 + free + fix 同图三色叠加（黑=Truth，红=free，蓝=fix）
miniinsplot({avp_free, avp_fix}, trj, 'cmp_freefix');
% saveas(gcf, 'miniinsplot_cmp_freefix.png'); close(gcf);
% 方案 A：三维轨迹对比（独立图，Z=高度误差×8 放大，破"2D 看不出 free/fix 差别"的困惑）
miniinsplot3d({avp_free, avp_fix}, trj, 'cmp_freefix');
% saveas(gcf, 'miniinsplot3d_cmp_freefix.png'); close(gcf);

end

% ---------------- 四元数/旋转工具（与 PSINS base0 逐字对齐） ----------------
function q = rv2q(phi)
    n = norm(phi);
    if n < 1e-12, q = [1;0;0;0]; return; end
    s = sin(n/2)/n;
    q = [cos(n/2); s*phi(1); s*phi(2); s*phi(3)];
end

function q = qmul(q1, q2)
    q = [ q1(1)*q2(1)-q1(2)*q2(2)-q1(3)*q2(3)-q1(4)*q2(4);
          q1(1)*q2(2)+q1(2)*q2(1)+q1(3)*q2(4)-q1(4)*q2(3);
          q1(1)*q2(3)-q1(2)*q2(4)+q1(3)*q2(1)+q1(4)*q2(2);
          q1(1)*q2(4)+q1(2)*q2(3)-q1(3)*q2(2)+q1(4)*q2(1) ];
end

function Cnb = q2mat(q)
    q1=q(1); q2=q(2); q3=q(3); q4=q(4);
    q11=q1*q1; q12=q1*q2; q13=q1*q3; q14=q1*q4;
    q22=q2*q2; q23=q2*q3; q24=q2*q4;
    q33=q3*q3; q34=q3*q4; q44=q4*q4;
    Cnb = [ q11+q22-q33-q44,  2*(q23-q14),     2*(q24+q13);
            2*(q23+q14),      q11-q22+q33-q44, 2*(q34-q12);
            2*(q24-q13),      2*(q34+q12),     q11-q22-q33+q44 ];
end

function att = q2att(q)
    q11=q(1)^2; q12=q(1)*q(2); q13=q(1)*q(3); q14=q(1)*q(4);
    q22=q(2)^2; q23=q(2)*q(3); q24=q(2)*q(4);
    q33=q(3)^2; q34=q(3)*q(4); q44=q(4)^2;
    C12 = 2*(q23-q14);  C22 = q11-q22+q33-q44;
    C31 = 2*(q24-q13);  C32 = 2*(q34+q12);  C33 = q11-q22-q33+q44;
    if C32 > 0.999999
        C11 = q11+q22-q33-q44;  C13 = 2*(q24+q13);
        att = [pi/2; atan2(C13,C11); 0];
    elseif C32 < -0.999999
        C11 = q11+q22-q33-q44;  C13 = 2*(q24+q13);
        att = [-pi/2; atan2(C13,C11); 0];
    else
        att = [ asin(C32); atan2(-C31,C33); atan2(-C12,C22) ];
    end
end

function qnb = a2qua(att)
    % 注意：PSINS 260705 的 a2qua 带 `if qnb(1)<0, qnb=-qnb` 规范化（q0>0）。
    % 迷你版 minitrj 用 dq 法（conj(q_prev)⊗q_new）求姿态增量，符号翻转会让
    % yaw 跨 180°/360° 时 dq 跳变 → wm 方向错。q2mat 对 q 的全局符号不敏感，
    % 因此这里去掉翻转以保持符号连续（与 gen_sins.py 双轨一致）。
    att2 = att/2; s = sin(att2); c = cos(att2);
    sp=s(1); sr=s(2); sy=s(3); cp=c(1); cr=c(2); cy=c(3);
    qnb = [ cp*cr*cy - sp*sr*sy;
            sp*cr*cy - cp*sr*sy;
            cp*sr*cy + sp*cr*sy;
            cp*cr*sy + sp*sr*cy ];
end

function v = qmulv(q, v), v = q2mat(q)*v; end
function v = rotv(phi, v), v = qmulv(rv2q(phi), v); end
function v = qconj(q), v = [q(1); -q(2); -q(3); -q(4)]; end
function s = askew(v), s = [0,-v(3),v(2); v(3),0,-v(1); -v(2),v(1),0]; end

% ---------------- earth（PSINS base1/earth.m 核心） ----------------
function [RMh, RNh, clRNh, wnin, gcc] = earthf(pos, vn)
    Re=6378137.0; f=1/298.257; wie=7.2921151467e-5; g0=9.7803267715;
    e2 = 2*f-f*f;
    sl = sin(pos(1)); cl = cos(pos(1)); sl2 = sl*sl;
    sq = 1-e2*sl2; sq2 = sqrt(sq);
    RMh = Re*(1-e2)/sq/sq2 + pos(3);
    RNh = Re/sq2 + pos(3);
    clRNh = cl*RNh;
    vE_RNh = vn(1)/RNh;
    wnen = [-vn(2)/RMh; vE_RNh; vE_RNh*sl/cl];
    wnie = [0; wie*cl; wie*sl];
    wnin = wnie + wnen;
    gn = [0;0;-g0];
    gcc = gn - cross(wnie+wnen, vn);
end

% ---------------- 迷你 trjsimu（P1 公式代码化，含 wnin/gcc 补偿） ----------------
function [imu, avp] = minitrj(avp0, wat, ts)
    att = avp0(1:3); vn = avp0(4:6); pos = avp0(7:9);
    total = round(sum(wat(:,1))/ts);
    imu = zeros(total, 7); avp = zeros(total, 10);
    ts2 = ts/2; ki = 0;
    Cbn_1 = q2mat(a2qua(att))';  wm_1 = zeros(3,1);
    for r = 1:size(wat,1)
        lenk = round(wat(r,1)/ts); wt = wat(r,3:5)'; at = wat(r,6:8)';
        for j = 1:lenk
            si=sin(att(1)); ci=cos(att(1)); sk=sin(att(3)); ck=cos(att(3));
            Cnt = [ ck, -ci*sk, si*sk; sk, ci*ck, -si*ck; 0, si, ci ];
            att = att + wt*ts;
            Cnb = q2mat(a2qua(att));
            an = Cnt*at;
            vn1 = vn + an*ts;  vn01 = (vn+vn1)/2;
            [RMh, RNh, clRNh, wnin, gcc] = earthf(pos, vn01);
            dpos01 = [vn01(2)/RMh; vn01(1)/clRNh; vn01(3)]*ts2;
            pos = pos + 2*dpos01;
            % 姿态增量（dq 法 ≈ PSINS m2rv(Cbn_1*Cnb)）
            dq = qmul(qconj(a2qua(att - wt*ts)), a2qua(att));
            phim = 2*[atan2(dq(2),dq(1)); atan2(dq(3),dq(1)); atan2(dq(4),dq(1))];
            phim = phim + (Cbn_1 + Cnb')*(wnin*ts2);    % wnin 补偿（同 PSINS）
            wm = inv(eye(3) + 1/12*askew(wm_1))*phim;
            dvbm = Cbn_1*((an - gcc)*ts);
            vm = inv(eye(3) + 0.5*askew(wm))*dvbm;
            avp(ki+1,:) = [att; vn1; pos; ki*ts]';
            imu(ki+1,:) = [wm; vm; ki*ts]';
            wm_1 = wm; Cbn_1 = Cnb'; vn = vn1; ki = ki+1;
        end
    end
    imu = imu(1:ki,:); avp = avp(1:ki,:);
end

% ---------------- 迷你 inspure（nn=2 双子样机械编排） ----------------
function avp = miniinspure(imu, avp0, fix_h)
    nn = 2; ts = 0.01;
    att = avp0(1:3); vn = avp0(4:6); pos = avp0(7:9);
    qnb = a2qua(att); pos0 = pos;
    len_ = size(imu,1); m = floor(len_/nn);
    avp = zeros(m, 10); ki = 0;
    for k = 1:nn:len_-nn+1
        wm = imu(k:k+1, 1:3);  vm = imu(k:k+1, 4:6);
        nts = nn*ts;  nts2 = nts/2;
        % cnscl 双子样圆锥/划桨补偿
        wmm = sum(wm,1)';
        dphim = cross(0.5*wm(1,:)', wm(2,:)');
        phim = wmm + dphim;
        vmm = sum(vm,1)';
        scullm = cross(0.5*wm(1,:)', vm(2,:)') + cross(vm(1,:)', 0.5*wm(2,:)');
        dvbm = vmm + scullm;
        [RMh, RNh, clRNh, wnin, gcc] = earthf(pos, vn);
        % 速度更新
        fn = q2mat(qnb)*(dvbm/nts);
        an = rotv(-wnin*nts2, fn) + gcc;
        vn1 = vn + an*nts;
        % 位置更新
        Mpv = [0, 1/RMh, 0; 1/clRNh, 0, 0; 0, 0, 1];
        pos = pos + Mpv*((vn+vn1)/2)*nts;
        vn = vn1;
        % 姿态更新（qupdt2 等效）
        qnb = qmul(rv2q(-wnin*nts), qmul(qnb, rv2q(phim)));
        if fix_h, pos(3) = pos0(3); end
        att = q2att(qnb);
        avp(ki+1,:) = [att; vn; pos; imu(k+1,7)]';
        ki = ki+1;
    end
    avp = avp(1:ki,:);
end

% ---------------- 误差统计 ----------------
function d = pos_err_m(dp, avp0, Re_h)
    d = [dp(1)*Re_h; dp(2)*Re_h*cos(avp0(7)); dp(3)];
end

function w = wrap_pi(a), w = mod(a+pi, 2*pi)-pi; end

function errstats(name, avp, trj, avp0, Re_h, deg)
    trj_d = trj(2:2:end,:);          % 双子样对齐（时刻 1,3,5,...*ts）
    n = min(size(avp,1), size(trj_d,1));
    de = avp(1:n,1:3) - trj_d(1:n,1:3);  de(:,3) = wrap_pi(de(:,3));
    dv = avp(1:n,4:6) - trj_d(1:n,4:6);
    dp = avp(1:n,7:9) - trj_d(1:n,7:9);
    dph = [dp(:,1)*Re_h, dp(:,2)*Re_h*cos(avp0(7)), dp(:,3)];
    dph_h = sqrt(dph(:,1).^2 + dph(:,2).^2);
    fprintf('    [%s] att RMS = (%.1f, %.1f, %.1f) arcsec | vel RMS = [%.3f %.3f %.3f] m/s\n', ...
        name, mean(abs(de),1)/deg*3600, mean(abs(dv),1));
    fprintf('             水平位置误差 RMS = %.1f m, 末点 = %.1f m | 垂直 = %.1f m (末 %.1f m)\n', ...
        mean(dph_h), dph_h(end), mean(abs(dph(:,3))), dph(end,3));
end
