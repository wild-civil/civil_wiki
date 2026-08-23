function gen_dr()
% 拆解 PSINS ③：迷你航位推算 = 真值轨迹生成 + 迷你 odsimu + 误差注入 + 迷你 drinit/drupdate
% =====================================================================================
% 复刻 test_DR.m 的数据流，但全部自包含（不依赖 PSINS）：
%   [生成] WAT 表（P1 产物）-> 迷你 trjsimu 数值积分出 真值 avp + 陀螺增量 imu
%   [里程] 迷你 odsimu：真值位置差分 -> 地球半径投影 -> 每步里程增量 dS（完美里程计）
%   [注入] 确定性误差：初始航向误差 davp(yaw)、里程计安装误差 dinst、尺度因子 dkod、陀螺零偏 eb
%   [解算] 迷你 drupdate 主循环：陀螺 wm 更新航向、里程 dS 投影递推位置（Td=0 无 leveling）
%   [分析] 解算 vs 真值：位置误差（航向误差×路程 -> 线性发散；尺度误差 -> 比例发散）
% 教学简化（route B 零依赖）：odsimu 不做 inst 旋转真值（inst 误差只在 drinit 注入）；
%   Td leveling 关掉；随机游走省略（确定性）。与 PSINS 对拍数字见 P3 正文。
% 无工具箱依赖，运行：gen_dr

% ---------------- 常量（与 PSINS glvf 对齐） ----------------
Re = 6378137.0;  f = 1/298.257;  wie = 7.2921151467e-5;  g0 = 9.7803267715;
e2 = 2*f - f*f;
deg = pi/180;  dph = pi/180/3600;  ug = 1e-6*g0;
ts = 0.01;                       % 100 Hz

% ---------------- wat 表（P1 产物：test_SINS_trj 展开 21 行） ----------------
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
fprintf('拆解 PSINS ③：迷你航位推算 = 真值 + odsimu + 误差注入 + drinit/drupdate\n');
fprintf('%s\n', repmat('=', 1, 70));

fprintf('\n[1] 真值轨迹生成（100 Hz，双子样增量）\n');
[imu, trj] = minitrj(avp0, WAT, ts);
fprintf('    行数 = %d（期望 96600），末位置 = (%.4f°, %.4f°, %.1f m)\n', ...
        size(imu,1), trj(end,7)/deg, trj(end,8)/deg, trj(end,9));

fprintf('\n[2] 迷你 odsimu：真值位置差分出完美里程增量 dS\n');
od = mini_odsimu(trj, 0, 1.0);   % inst=0, kod=1 -> 完美里程计
fprintf('    里程增量行数 = %d，总里程 = %.1f m\n', size(od,1), sum(od(:,1)));

fprintf('\n[3] 确定性误差注入（航向 1°、里程计安装 10''、尺度 5%%、陀螺零偏 0.01°/h）\n');
davp  = [60; 0; 60]*(deg/60);     % avperrset: 姿态误差 arcmin -> pitch 1°, roll 0, yaw 1°
dinst = [15; 0; 10]*(deg/60);     % 里程计安装误差 arcmin -> dyaw = 10''
dkod  = 0.05;                     % 尺度因子误差 5%
eb    = [0;0;0.01]*dph;           % 陀螺零偏（z 轴 -> 航向缓慢漂移）
avp0e = avp0; avp0e(1:3) = avp0(1:3) + davp;          % 初始姿态加误差
imu_e = imu; imu_e(:,1:3) = imu_e(:,1:3) + (eb*ts)';  % 陀螺加零偏
fprintf('    初始 yaw 误差 = %.3f° (=60''), 安装 dyaw = %.3f° (=10''), 尺度误差 = %.0f%%\n', ...
        davp(3)/deg, dinst(3)/deg, dkod*100);

fprintf('\n[4] 迷你 drinit + drupdate 主循环（Td=0）\n');
dr = mini_drinit(avp0e, dinst, 1.0*(1+dkod), ts);
len_ = size(imu_e,1); nn = 2; avp = zeros(floor(len_/nn), 10); ki = 0;
for k = 1:nn:len_-nn+1
    k1 = k+nn-1;
    wm = imu_e(k:k1, 1:3);
    dS = sum(od(k:k1, 1));
    dr = mini_drupdate(dr, wm, dS);
    avp(ki+1,:) = [dr.avp; imu_e(k1,end)]';
    ki = ki+1;
end
avp = avp(1:ki,:);
fprintf('    总里程 dr.distance = %.1f m（= 真值里程 ×(1+dkod)）\n', dr.distance);

fprintf('\n[5] 误差传播分析（DR vs 真值，966 s）\n');
Re_h = Re + avp0(9);
errstats('航位推算', avp, trj, avp0, Re_h, deg);

fprintf('\n[6] 教学要点\n');
fprintf('    航向误差 δψ -> 位置误差 ≈ tan(δψ)·S（S=已走路程） -> 随路程线性发散\n');
fprintf('    尺度因子误差 dkod -> 位置误差 ∝ dkod·S -> 同样线性（比例型）\n');
fprintf('    与 P2 纯惯导对照：P2 误差来自重力杠杆(Schuler 振荡,随时间) ；DR 误差随路程单调增长\n');

fprintf('\n[7] 可视化（迷你 insplot / avpcmpplot，零依赖自写，参考 PSINS 布局）\n');
miniinsplot(trj, 'truth');   % 真值轨迹
% saveas(gcf, 'miniinsplot_truth.png'); close(gcf);
miniinsplot(avp, 'dr');      % 航位推算解算轨迹
saveas(gcf, 'miniinsplot_dr.png'); close(gcf);
miniinsplot(avp, trj, 'cmp');  % 真值 vs 估计值 同图叠（对比模式）
% saveas(gcf, 'miniinsplot_cmp.png'); close(gcf);
miniavpcmpplot(trj, {avp}, {'dr'});
% saveas(gcf, 'miniavpcmpplot_dr.png'); close(gcf);

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
    % 注意：PSINS 260705 a2qua 带 `if qnb(1)<0, qnb=-qnb` 规范化（q0>0）。
    % 迷你版 minitrj 用 dq 法求姿态增量，符号翻转会让 yaw 跨 180°/360° 时 dq 跳变
    % -> wm 方向错。因此去掉翻转以保持符号连续（与 Python 双轨一致）。
    att2 = att/2; s = sin(att2); c = cos(att2);
    sp=s(1); sr=s(2); sy=s(3); cp=c(1); cr=c(2); cy=c(3);
    qnb = [ cp*cr*cy - sp*sr*sy;
            sp*cr*cy - cp*sr*sy;
            cp*sr*cy + sp*cr*sy;
            cp*cr*sy + sp*sr*cy ];
end

function Cnb = a2mat(att), Cnb = q2mat(a2qua(att)); end

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

% ---------------- 迷你 odsimu（里程增量仿真，Td=0 确定性） ----------------
function od = mini_odsimu(trj, inst, kod)
    % trj: 真值 avp (N×10)；inst: 安装误差(略, 教学版=0)；kod: 完美里程计=1
    % 输出 od: N×2 = [每步里程增量 dS, 时刻 t]，与 trj 行一一对应
    pos0 = trj(1,7:9);
    pos = [pos0; trj(:,7:9)];           % N+1 个位置点
    n = size(pos,1);
    RMh = zeros(n-1,1); clRNh = zeros(n-1,1);
    for k = 1:n-1
        [RMh(k),~,clRNh(k),~,~] = earthf(pos(k,:)', [0;0;0]);
    end
    dpos = diff(pos);
    dxyz = [RMh.*dpos(:,1), clRNh.*dpos(:,2), dpos(:,3)];  % lat*RMh, lon*clRNh, h
    dS = sqrt(sum(dxyz.^2, 2));
    dSc = cumsum([0;dS]);
    od = [diff(dSc/kod), trj(:,10)];     % 完美里程计每步增量 /kod
end

% ---------------- 迷你 drinit（DR 结构初始化，Td=0） ----------------
function dr = mini_drinit(avp0e, inst, kod, ts)
    dr = [];
    avp0e = avp0e(:);
    if length(avp0e)<9, avp0e = [avp0e(1:3); zeros(3,1); avp0e(4:end)]; end
    dr.qnb = a2qua(avp0e(1:3));
    [dr.qnb, dr.att, dr.Cnb] = attsyn(dr.qnb);
    dr.vn = zeros(3,1); dr.pos = avp0e(7:9);
    dr.avp = [dr.att; dr.vn; dr.pos];
    dr.kod = kod;
    dr.aos = inst(2); inst(2) = 0;          % aos: angle of slide（教学版=0）
    dr.Cbo = a2mat(-inst)*kod;
    dr.prj = dr.Cbo*[0;1;0];                % odometer 前向 -> SIMU 投影
    dr.ts = ts;
    dr.distance = 0;
    [~,~,clRNh,~,~] = earthf(dr.pos, [0;0;0]);
    RMh = earthf(dr.pos, [0;0;0]); RMh = RMh(1);
    dr.Mpv = [0, 1/RMh, 0; 1/clRNh, 0, 0; 0, 0, 1];
    dr.Td = 0;
end

% ---------------- 迷你 drupdate（DR 主更新，Td=0 无 leveling） ----------------
function dr = mini_drupdate(dr, wm, dS)
    nts = dr.ts * size(wm,1);
    % cnscl 双子样：陀螺圆锥补偿（DR 只用陀螺更新航向）
    wmm = sum(wm,1)';
    dphim = cross(0.5*wm(1,:)', wm(2,:)');
    phim = wmm + dphim;
    qnb12 = qmul(dr.qnb, rv2q(phim/2));     % qupdt(dr.qnb, phim/2)
    % 里程增量投影到导航系
    if length(dS)>1
        dSn = qmulv(qnb12, dr.Cbo*dS);
    else
        dSn = qmulv(qnb12, dr.prj*dS);
    end
    dSn = rotv([0;0;-dr.aos*phim(3)/nts], dSn);   % aos=0 -> 恒等
    dr.vn = dSn/nts;
    [RMh, RNh, clRNh, wnin, gcc] = earthf(dr.pos, dr.vn);
    dr.Mpv = [0, 1/RMh, 0; 1/clRNh, 0, 0; 0, 0, 1];
    dr.pos = dr.pos + dr.Mpv*dSn;            % 位置递推（严龚敏博士论文 Eq.4.1.1）
    dr.qnb = qmul(dr.qnb, rv2q(phim - dr.Cnb'*wnin*nts));   % 姿态更新
    [dr.qnb, dr.att, dr.Cnb] = attsyn(dr.qnb);
    dr.avp = [dr.att; dr.vn; dr.pos];
    dr.distance = dr.distance + dr.kod*norm(dS);
end

% ---------------- 误差统计 ----------------
function [q, att, Cnb] = attsyn(q), att = q2att(q); Cnb = q2mat(q); end

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
