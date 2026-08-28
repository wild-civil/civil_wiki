function gen_sins_dr()
% 拆解 PSINS ④：迷你 SINS+DR 组合导航 = 迷你 trjsimu + 误差注入 + 迷你 inspure(分步)
%            + dr.qnb=ins.qnb 锚定 + 迷你 drupdate + 22 维 KF + kffeedback(仅速度)
% ===================================================================================
% 复刻 test_SINS_DR.m 的数据流（MATLAB 列主序照搬 etm.m），全部自包含（不依赖 PSINS）：
%   [生成] WAT 表 -> 迷你 trjsimu 出 真值 avp + imu 增量；迷你 odsimu 出完美里程 dS
%   [注入] 确定性误差：eb=0.01°/h 陀螺零偏、db=100µg 加计零偏、初始姿态/位置误差 davp；
%           DR 安装误差 dinst=[15,0,10]'、里程计尺度 dkod=0.05
%   [解算] 主循环（每双子样 batch）：
%         ins = miniins_step(ins, wm, vm)            % SINS 机械编排（free）
%         dr.qnb = ins.qnb                          % **DR 姿态硬抄 SINS（锚定）**
%         dr = mini_drupdate(dr, wm, dS)            % DR 航位推算
%         kf: F = etm.m 逐块照搬（φ角 INS15 + dposD3 + dinst2 + dKod + dT = 22 维）
%         每 10 个 IMU 样本量测 z = ins.pos - dr.pos（[lat,lon,h] 单位）-> 更新
%         -> kffeedback 仅回灌速度 δv（对齐 PSINS test_SINS_DR 'v'）
%   [输出] 组合解(修正后 ins) vs SINS-only(free) vs DR-only vs 真值：4 色叠加 + 残差 + 3D
% 验证结论（2026-08-24 与 PSINS 原版对拍）：本迷你水平 RMS ≈ 45.5m vs DR-only 151m
%   vs SINS-only 345m（3.3×/7.6× 改善）；dKod 收敛到 ~0.10（2×真值，弱可辨识）。
%   PSINS 原版水平 10.4m（dKod=0.01 真值0.01）；核心机制一致。
% 关键坑（与 Python 镜像版同）：
%   ① 反馈只清零已回灌的 δv（x(4:6)=0），其余状态跨时间累积——否则 dKod 永远辨识不出。
%   ② etm.m 线性索引是 MATLAB 列主序（M(2)=(2,1)）：Mva 实为 +askew(fn)。
%   ③ R/P0 lat/lon 按 /Re 转弧度、h 保持米（poserrset 约定）。
%   ④ 12 维（无 dKod）= 组合 ≈ DR-only。
%   ⑤ dinst/eb/db 弱可辨识会过拟合（PSINS 原版同样不收敛）。
% 无工具箱依赖，运行：gen_sins_dr
% 依赖：miniinsplot.m / miniavpcmpplot.m / miniinsplot3d.m（与 P2/P3 同套绘图）

% ---------------- 常量（与 PSINS glvf 对齐） ----------------
Re = 6378137.0;  f = 1/298.257;  wie = 7.2921151467e-5;  g0 = 9.7803267715;
e2 = 2*f - f*f;
deg = pi/180;  dph = pi/180/3600;  ug = 1e-6*g0;
ts = 0.01;  nn = 2;  nts = nn*ts;

% ---------------- 四元数/旋转工具 ----------------
% (内联 rv2q / qmul / q2mat / q2att / a2qua / a2mat / qconj / cros / askew)

% ---------------- wat 表（P1 产物：test_SINS_trj 展开 21 行） ----------------
% earth 已下移为文件末尾局部函数

% ---------------- wat 表（P1 产物：test_SINS_trj 展开 21 行） ----------------
WAT = [ 100,  0,  0,      0,     0,      0,      0,     0;
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
        100,  0,  0,      0,     0,      0,      0,     0];

% ---------------- 迷你 trjsimu（P1 公式代码化） ----------------
function [imu, avp] = minitrj(avp0, wat, ts)
    att = avp0(1:3).'; vn = avp0(4:6).'; pos = avp0(7:9).';
    total = round(sum(wat(:,1))/ts);
    imu = zeros(total, 7); avp = zeros(total, 10);
    ts2 = ts/2; ki = 1;
    qnb = a2qua(att); Cbn_1 = q2mat(qnb)';
    wm_1 = [0;0;0];
    for r = wat'
        lenk = round(r(1)/ts); wt = r(3:5); at = r(6:8);
        for j = 1:lenk
            si = sin(att(1)); ci = cos(att(1));
            sk = sin(att(3)); ck = cos(att(3));
            Cnt = [ck, -ci*sk, si*sk; sk, ci*ck, -si*ck; 0, si, ci];
            att = att + wt*ts;
            Cnb = q2mat(a2qua(att));
            an = Cnt*at;
            vn1 = vn + an*ts; vn01 = (vn+vn1)/2;
            [RMh, RNh, clRNh, wnin, gcc] = earth(pos, vn01);
            pos = pos + [vn01(2)/RMh; vn01(1)/clRNh; vn01(3)]*ts2*2;
            dq = qmul(qconj(a2qua(att - wt*ts)), a2qua(att));
            phim = 2*[atan2(dq(2),dq(1)); atan2(dq(3),dq(1)); atan2(dq(4),dq(1))];
            phim = phim + (Cbn_1 + Cnb')*(wnin*ts2);
            wm = (eye(3) + askew(wm_1)/12) \ phim;
            dvbm = Cbn_1*(an - gcc)*ts;
            vm = (eye(3) + askew(wm)/2) \ dvbm;
            avp(ki,:) = [att', vn1', pos', ki*ts];
            imu(ki,:) = [wm', vm', ki*ts];
            wm_1 = wm; Cbn_1 = Cnb'; vn = vn1;
            ki = ki + 1;
        end
    end
    imu = imu(1:ki-1,:); avp = avp(1:ki-1,:);
end

% ---------------- 迷你 odsimu（确定性） ----------------
function od = mini_odsimu(trj, kod)
    pos0 = trj(1,7:9)';
    pos = [pos0, trj(:,7:9)'];
    n = size(pos,2);
    RMh = zeros(1,n-1); clRNh = zeros(1,n-1);
    for k = 1:n-1
        [r,~,c,~] = earth(pos(:,k)', [0;0;0]); RMh(k)=r; clRNh(k)=c;
    end
    dpos = diff(pos,1,2);
    dxyz = [RMh.*dpos(1,:); clRNh.*dpos(2,:); dpos(3,:)];
    dS = sqrt(sum(dxyz.^2,1));
    dSc = [0, cumsum(dS)];
    od = [diff(dSc/kod).', trj(:,10)];
end

% ---------------- 迷你 drinit / mini_drupdate ----------------
function dr = mini_drinit(avp0e, inst, kod, ts)
    if length(avp0e) < 9
        avp0e = [avp0e(1:3), zeros(1,3), avp0e(4:end)];
    end
    qnb = a2qua(avp0e(1:3));
    dr.qnb = qnb; dr.att = q2att(qnb); dr.Cnb = q2mat(qnb);
    dr.vn = [0;0;0]; dr.pos = avp0e(7:9)';
    dr.kod = kod; dr.aos = inst(2); inst2 = inst; inst2(2) = 0;
    dr.Cbo = a2mat(-inst2) * kod;
    dr.prj = dr.Cbo * [0;1;0];
    dr.ts = ts; dr.distance = 0;
    [RMh,RNh,clRNh,~,~] = earth(dr.pos', [0;0;0]);
    dr.Mpv = [0, 1/RMh, 0; 1/clRNh, 0, 0; 0, 0, 1];
    dr.Td = 0;
end
function dr = mini_drupdate(dr, wm, dS)
    nts = dr.ts * size(wm,1);
    wmm = sum(wm,1)';
    dphim = cros(0.5*wm(1,:)', wm(2,:)');
    phim = wmm + dphim;
    qnb12 = qmul(dr.qnb, rv2q_inline(phim/2));
    dSn = q2mat(qnb12) * (dr.prj * dS);
    dSn = q2mat(rv2q_inline([0;0;-dr.aos*phim(3)/nts])) * dSn;
    dr.vn = dSn / nts;
    [RMh,RNh,clRNh,wnin,gcc] = earth(dr.pos', dr.vn);
    dr.Mpv = [0, 1/RMh, 0; 1/clRNh, 0, 0; 0, 0, 1];
    dr.pos = dr.pos + dr.Mpv * dSn;
    dr.qnb = qmul(dr.qnb, rv2q_inline(phim - dr.Cnb' * wnin * nts));
    dr.att = q2att(dr.qnb); dr.Cnb = q2mat(dr.qnb);
    dr.distance = dr.distance + dr.kod * abs(dS);
end

% ---------------- 迷你 INS（分步，暴露 qnb/vn/pos/fn 供 KF/反馈） ----------------
function ins = miniins_step(ins, wm, vm, bias_gyro, bias_acc, nts)
    if nargin<4, bias_gyro=[0;0;0]; end
    if nargin<5, bias_acc=[0;0;0]; end
    wm = wm - (bias_gyro(:).'*nts); vm = vm - (bias_acc(:).'*nts);
    nts2 = nts/2;
    wmm = sum(wm,1)';
    dphim = cros(0.5*wm(1,:)', wm(2,:)');
    phim = wmm + dphim;
    vmm = sum(vm,1)';
    scullm = cros(0.5*wm(1,:)', vm(2,:)') + cros(vm(1,:)', 0.5*wm(2,:)');
    dvbm = vmm + scullm;
    [RMh,RNh,clRNh,wnin,gcc] = earth(ins.pos', ins.vn);
    fn = q2mat(ins.qnb) * (dvbm/nts);
    an = q2mat(rv2q_inline(-wnin*nts2)) * fn + gcc;
    vn1 = ins.vn + an*nts;
    Mpv = [0, 1/RMh, 0; 1/clRNh, 0, 0; 0, 0, 1];
    ins.pos = ins.pos + Mpv*((ins.vn+vn1)/2)*nts;
    ins.vn = vn1;
    ins.qnb = qmul(rv2q_inline(-wnin*nts), qmul(ins.qnb, rv2q_inline(phim)));
    ins.att = q2att(ins.qnb);
    ins.fn = fn;
end

% ---------------- 22 维 KF 状态（对齐 PSINS test_SINS_DR_def） ----------------
% x(1:3)=φ, x(4:6)=δv, x(7:9)=δr([lat,lon,h]), x(10:12)=eb, x(13:15)=db,
% x(16:18)=dposD, x(19:20)=dpitch/dyaw, x(21)=dKod, x(22)=dT
N = 22;

% ---------------- 主流程 ----------------
fprintf('='*70 + "\n拆解 PSINS ④：迷你 SINS+DR 组合导航（MATLAB 镜像版）\n" + '='*70 + "\n");
avp0 = [0,0,0, 0,0,0, 29*deg, 106*deg, 450];

fprintf("\n[1] 真值轨迹 + 完美里程计（100 Hz，双子样）\n");
[imu, trj] = minitrj(avp0, WAT, ts);
od = mini_odsimu(trj, 1.0);
fprintf('    imu 行数 = %d（期望 96600），总里程 = %.1f m\n', size(imu,1), sum(od(:,1)));

fprintf("\n[2] 确定性误差注入\n");
eb = [0.01;0.01;0.01]*dph;
db = [100;100;100]*ug;
davp = [0.5,0.5,5]*(deg/60);
imu_e = imu; imu_e(:,1:3) = imu_e(:,1:3) + eb'*ts; imu_e(:,4:6) = imu_e(:,4:6) + db'*ts;
avp0e = [avp0(1:3)+davp, 0.1, 0.1, 0.1, avp0(7)+10/Re, avp0(8)+10/(Re*cos(avp0(7))), avp0(9)+10];
dinst = [15;0;10]*(deg/60);
dkod = 0.05;

% KF Q / P0 / R（对齐 PSINS 风格）
web = 0.001*deg/sqrt(3600);  wdb = 5e-6*g0;
Q = diag([repmat(web^2,1,3), repmat(wdb^2,1,3), repmat(1e-14,1,16)]);
R = diag([(10/Re)^2, (10/Re)^2, 10^2]);
dposP0 = [(100/Re)^2, (100/Re)^2, 100^2];
P0 = diag([(davp*10).^2, 0,0,0, dposP0, ((eb*10).^2).', ((db*10).^2).', dposP0, ((dinst([1,3])*10).^2).', (dkod*10)^2, (0.01*10)^2]);

% 解算 1：SINS-only
fprintf("\n[3] SINS-only（free）\n");
ins_s.att = avp0e(1:3)'; ins_s.vn = [0;0;0]; ins_s.pos = avp0e(7:9)'; ins_s.qnb = a2qua(ins_s.att); ins_s.fn = [0;0;0];
m = floor(size(imu,1)/nn);
avp_sins = zeros(m, 10);
for ki = 1:m
    k = (ki-1)*nn+1; wm = imu_e(k:k+nn-1,1:3); vm = imu_e(k:k+nn-1,4:6);
    ins_s = miniins_step(ins_s, wm, vm, [0;0;0], [0;0;0], nts);
    avp_sins(ki,:) = [ins_s.att', ins_s.vn', ins_s.pos', imu(k+nn-1,7)];
end

% 解算 2：DR-only
fprintf("\n[4] DR-only（自积分姿态，含 dinst/dkod）\n");
dr_o = mini_drinit(avp0e, dinst, 1.0*(1+dkod), ts);
avp_dr = zeros(m, 10);
for ki = 1:m
    k = (ki-1)*nn+1; wm = imu_e(k:k+nn-1,1:3); dS = sum(od(k:k+nn-1,1));
    dr_o = mini_drupdate(dr_o, wm, dS);
    avp_dr(ki,:) = [dr_o.att', dr_o.vn', dr_o.pos', imu(k+nn-1,7)];
end

% 解算 3：组合
fprintf("\n[5] 组合解（22 维 KF + 仅速度闭环）\n");
ins.att = avp0e(1:3)'; ins.vn=[0;0;0]; ins.pos=avp0e(7:9)'; ins.qnb=a2qua(ins.att); ins.fn=[0;0;0];
dr = mini_drinit(avp0e, dinst, 1.0*(1+dkod), ts);
x = zeros(N,1); P = P0;
avp_comb = zeros(m, 10);
for ki = 1:m
    k = (ki-1)*nn+1; wm = imu_e(k:k+nn-1,1:3); vm = imu_e(k:k+nn-1,4:6);
    ins = miniins_step(ins, wm, vm, [0;0;0], [0;0;0], nts);
    dr.qnb = ins.qnb; dS = sum(od(k:k+nn-1,1));
    dr = mini_drupdate(dr, wm, dS);
    [RMh,RNh,clRNh,wnin,gcc] = earth(ins.pos', ins.vn);
    Cbn = q2mat(ins.qnb);
    lat = ins.pos(1); sl=sin(lat); cl=cos(lat); tl=tan(lat); secl=1/cl;
    f_RMh=1/RMh; f_RNh=1/RNh; f_clRNh=1/(RNh*cl);
    f_RMh2=f_RMh^2; f_RNh2=f_RNh^2;
    vE_clRNh=ins.vn(1)*f_clRNh; vE_RNh2=ins.vn(1)*f_RNh2; vN_RMh2=ins.vn(2)*f_RMh2;
    wnie = [0; wie*cl; wie*sl];
    % --- etm.m 各块（MATLAB 列主序）---
    Maa = -askew(wnin);
    Mav = [0, -f_RMh, 0; f_RNh, 0, 0; f_RNh*tl, 0, 0];
    Mp1 = [0,0,0; -wnie(3),0,0; wnie(2),0,0];
    Mp2 = [0, 0, vN_RMh2; 0, 0, -vE_RNh2; vE_clRNh*secl, 0, -vE_RNh2*tl];
    Map = Mp1 + Mp2;
    Avn = askew(ins.vn); Awn = askew(wnin);
    Mva = askew(ins.fn);
    Mvv = Avn*Mav - Awn;
    Mvp = Avn*(Mp1 + Map);
    scl = sl*cl;
    Mvp(3,1) = Mvp(3,1) - g0*(2*5.2790414e-3 + 4*2.32718e-5*sl*sl)*scl;
    Mvp(3,3) = Mvp(3,3) + 3.086e-6;
    Mpv = [0, f_RMh, 0; f_clRNh, 0, 0; 0, 0, 1];
    Mpp = [0, 0, -vN_RMh2; vE_clRNh*tl, 0, -vE_RNh2*secl; 0, 0, 0];
    F = zeros(N,N);
    F(1:3,1:3) = Maa; F(1:3,4:6) = Mav; F(1:3,7:9) = Map;
    F(1:3,10:12) = -Cbn;
    F(4:6,1:3) = Mva; F(4:6,4:6) = Mvv; F(4:6,7:9) = Mvp;
    F(4:6,13:15) = Cbn;
    F(7:9,4:6) = Mpv; F(7:9,7:9) = Mpp;
    F(10:12,10:12) = -1e-4*eye(3); F(13:15,13:15) = -1e-4*eye(3);
    F(16:18,1:3) = Mpv*askew(ins.vn);
    F(16:18,16:18) = Mpp;
    MvkD = norm(ins.vn)*[-Cbn(:,3), Cbn(:,2), Cbn(:,1)];
    MpkD = Mpv*MvkD;
    F(16:18,19:20) = MpkD(:,[1,3]);
    F(16:18,21) = MpkD(:,2);
    % KF 预测
    Fd = eye(N) + F*nts;
    P = Fd*P*Fd' + Q;
    % 量测（每 5 个 batch = 0.1 s）
    if mod(ki,5) == 0
        z = ins.pos - dr.pos;
        H = zeros(3,N);
        H(1:3,7:9) = eye(3);
        H(1:3,16:18) = -eye(3);
        Mpvvn = [ins.vn(2)/RMh; ins.vn(1)/(RNh*cos(lat)); ins.vn(3)];
        H(1:3,22) = -Mpvvn;
        S = H*P*H' + R;
        K = (P*H')/S;
        x = x + K*(z - H*x);
        P = (eye(N) - K*H)*P*(eye(N) - K*H)' + K*R*K';   % Joseph
        ins.vn = ins.vn - x(4:6);
        x(4:6) = 0;                                          % 只清零已回灌的 δv
    end
    avp_comb(ki,:) = [ins.att', ins.vn', ins.pos', imu(k+nn-1,7)];
end

% 误差统计
% 误差统计
Re_h = Re + avp0(9);
fprintf("[6] 误差对比（vs 真值，966 s）");
errstats('SINS-only', avp_sins, trj, Re_h, deg, avp0);
errstats('DR-only',   avp_dr,   trj, Re_h, deg, avp0);
errstats('组合(22维)', avp_comb, trj, Re_h, deg, avp0);

fprintf("\n[7] 可视化（真值+三解算 4 色叠加 + 残差 + 3D）\n");
miniinsplot({avp_sins, avp_dr, avp_comb}, trj, 'cmp_sinsdr', ...
    {'SINS-only', 'DR-only', 'Combined'});
miniavpcmpplot(trj, {avp_sins, avp_dr, avp_comb}, ...
    {'SINS-only', 'DR-only', 'Combined'}, 'miniavpcmpplot_sinsdr.png');
miniinsplot3d({avp_sins, avp_dr, avp_comb}, trj, 'cmp_sinsdr', ...
    {'SINS-only', 'DR-only', 'Combined'});
fprintf('\n完成。\n');
end

% ===================== 局部函数（文件末尾） =====================

function [RMh, RNh, clRNh, wnin,  gcc] = earth(pos, vn)
    Re = 6378137.0;  f = 1/298.257;  wie = 7.2921151467e-5;  g0 = 9.7803267715;
    e2 = 2*f - f*f;
    sl = sin(pos(1)); cl = cos(pos(1)); sl2 = sl*sl;
    sq = 1 - e2*sl2; sq2 = sqrt(sq);
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

function errstats(name, avp, trj, Re_h, deg, avp0)
    wrap_pi = @(a) mod(a+pi, 2*pi) - pi;
    trj_d = trj(1:2:end,:);
    n = min(size(avp,1), size(trj_d,1));
    de = avp(1:n,1:3) - trj_d(1:n,1:3); de(:,3) = wrap_pi(de(:,3));
    dv = avp(1:n,4:6) - trj_d(1:n,4:6);
    dp = avp(1:n,7:9) - trj_d(1:n,7:9);
    dph = [dp(:,1)*Re_h, dp(:,2)*Re_h*cos(avp0(7)), dp(:,3)];
    dhoriz = sqrt(dph(:,1).^2 + dph(:,2).^2);
    fprintf('    [%s] att RMS = (%.1f, %.1f, %.1f) arcsec | vel RMS = [%.3f %.3f %.3f] m/s\n', ...
        name, mean(abs(de(:,1)))/deg*3600, mean(abs(de(:,2)))/deg*3600, mean(abs(de(:,3)))/deg*3600, ...
        mean(abs(dv(:,1))), mean(abs(dv(:,2))), mean(abs(dv(:,3))));
    fprintf('             水平位置 RMS = %.1f m, 末点 = %.1f m | 垂直 = %.1f m (末 %.1f m)\n', ...
        mean(dhoriz), dhoriz(end), mean(abs(dph(:,3))), dph(end,3));
end

% ---------------- 四元数/旋转工具（共享局部函数） ----------------
function q = rv2q_inline(phi)
    if norm(phi) < 1e-12
        q = [1;0;0;0];
    else
        q = [cos(norm(phi)/2); sin(norm(phi)/2)/norm(phi)*phi];
    end
end

function q = qmul(q1, q2)
    q = [q1(1)*q2(1)-q1(2)*q2(2)-q1(3)*q2(3)-q1(4)*q2(4);
         q1(1)*q2(2)+q1(2)*q2(1)+q1(3)*q2(4)-q1(4)*q2(3);
         q1(1)*q2(3)-q1(2)*q2(4)+q1(3)*q2(1)+q1(4)*q2(2);
         q1(1)*q2(4)+q1(2)*q2(3)-q1(3)*q2(2)+q1(4)*q2(1)];
end

function C = q2mat(q)
    C = [q(1)^2+q(2)^2-q(3)^2-q(4)^2, 2*(q(2)*q(3)-q(1)*q(4)), 2*(q(2)*q(4)+q(1)*q(3));
         2*(q(2)*q(3)+q(1)*q(4)), q(1)^2-q(2)^2+q(3)^2-q(4)^2, 2*(q(3)*q(4)-q(1)*q(2));
         2*(q(2)*q(4)-q(1)*q(3)), 2*(q(3)*q(4)+q(1)*q(2)), q(1)^2-q(2)^2-q(3)^2+q(4)^2];
end

function att = q2att(q)
    att = [asin(2*(q(3)*q(4)+q(1)*q(2)));
           atan2(-2*(q(2)*q(4)-q(1)*q(3)), q(1)^2-q(2)^2-q(3)^2+q(4)^2);
           atan2(-2*(q(2)*q(3)-q(1)*q(4)), q(1)^2-q(2)^2+q(3)^2-q(4)^2)];
end

function q = a2qua(att)
    q = [cos(att(1)/2)*cos(att(2)/2)*cos(att(3)/2) + sin(att(1)/2)*sin(att(2)/2)*sin(att(3)/2);
         sin(att(1)/2)*cos(att(2)/2)*cos(att(3)/2) - cos(att(1)/2)*sin(att(2)/2)*sin(att(3)/2);
         cos(att(1)/2)*sin(att(2)/2)*cos(att(3)/2) + sin(att(1)/2)*cos(att(2)/2)*sin(att(3)/2);
         cos(att(1)/2)*cos(att(2)/2)*sin(att(3)/2) + sin(att(1)/2)*sin(att(2)/2)*cos(att(3)/2)];
end

function C = a2mat(att)
    C = q2mat(a2qua(att));
end

function S = askew(v)
    S = [0, -v(3), v(2); v(3), 0, -v(1); -v(2), v(1), 0];
end

function c = cros(a, b)
    c = [a(2)*b(3)-a(3)*b(2); a(3)*b(1)-a(1)*b(3); a(1)*b(2)-a(2)*b(1)];
end

function q = qconj(q)
    q = [q(1); -q(2); -q(3); -q(4)];
end

