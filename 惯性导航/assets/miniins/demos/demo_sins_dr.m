function demo_sins_dr()
% demo_sins_dr - SINS+DR 组合导航完整仿真（Mini-INS M4 验收 demo）
%
% 对齐 P4 `docs/惯性导航/assets/gen_sins_dr.py`（即 PSINS test_SINS_DR.m 的迷你版）：
%   [生成] WAT 表(21 行, 含俯仰机动) → trjsimu 出真值 avp + imu；odsimu 出完美里程
%   [注入] eb=0.01°/h 陀螺零偏、db=100µg 加计零偏、初始误差 davp；
%          安装角 dinst=[15;0;10]'(arcmin)、刻度 dkod=0.05
%   [解算] 主循环（每双子样）：
%        ins = insupdate(ins, wm, vm)      % SINS 前推（不标定，吃含误差 imu）
%        dr.qnb = ins.qnb                  % ★ DR 姿态硬锚定
%        dr = drupdate(dr, wm, dS)         % DR 航位推算（体 y 里程）
%        kf.Phikk_1 = kffk(ins)            % 22 维 F（φ角 INS15 + DR 扩展 7）
%        kf = kfupdate(kf)                 % 时间更新
%        每 5 batch(≈0.1s)：z=ins.pos-dr.pos → H → kfupdate(kf,z)
%        → 反馈 ins.vn -= xk(4:6)（仅速度闭环 'v'，其余状态跨时间累积）
%   [输出] SINS-only / DR-only / 组合 三链误差对比 + 22 维在线自标定
%
% 期望（对拍 P4 基准，2026-08-24 已与 PSINS 原版对拍）：
%   SINS-only 水平 RMS ≈ 345 m | DR-only ≈ 151 m | 组合(22维) ≈ 45.5 m
%   dKod 估计 → 收敛（末段均值接近 +0.05，可能偏大系弱可辨识性）
%
% 运行：cd docs/惯性导航/assets/miniins/demos; demo_sins_dr
% 要求：无工具箱；依赖 core/（trans/earth/trjsimu/odsimu/insupdate/drinit/
%        drupdate/kffk/kfupdate），addpath 自动加。

% ---- 路径 ----
addpath(fullfile(fileparts(mfilename('fullpath')), '..', 'core'));
glv = glvs();
deg = glv.deg;  dph = deg/3600;  ug = 1e-6*glv.g0;
ts = 0.01;  nn = 2;  nts = nn*ts;

fprintf('%s\n', repmat('=',1,68));
fprintf('Mini-INS ④：SINS+DR 组合导航（SINS 主导 + DR 辅助，22 维 KF 自标定）\n');
fprintf('%s\n', repmat('=',1,68));

%% ========== 1) WAT 表（P1 产物：test_SINS_trj 展开 21 行） ==========
% 列：[时长s 初速m/s w1 w2 w3(rad/s) a1 a2 a3(m/s²)]  ← w3=yaw 速率、a2=前向
WAT = [ 100,  0,  0,          0,      0,         0,      0,      0;
         10,  0,  0,          0,      0,         0,      1,      0;
        100, 10,  0,          0,      0,         0,      0,      0;
          4, 10,  0, -0.51*deg,      0,         0,      0,      0;
         45, 10,  0,          0, 2.00*deg, -0.349,      0,      0;
          4, 10,  0,  0.51*deg,      0,         0,      0,      0;
        100, 10,  0,          0,      0,         0,      0,      0;
          4, 10,  0,  2.28*deg,      0,         0,      0,      0;
         50, 10,  0,          0,-9.00*deg,  1.571,      0,      0;
          4, 10,  0, -2.28*deg,      0,         0,      0,      0;
        100, 10,  0,          0,      0,         0,      0,      0;
         10, 10, 2.00*deg,    0,      0,         0,      0, 0.349;
         50, 10,  0,          0,      0,         0,      0,      0;
         10, 10,-2.00*deg,    0,      0,         0,      0,-0.349;
        100, 10,  0,          0,      0,         0,      0,      0;
         10, 10,-2.00*deg,    0,      0,         0,      0,-0.349;
         50, 10,  0,          0,      0,         0,      0,      0;
         10, 10, 2.00*deg,    0,      0,         0,      0, 0.349;
        100, 10,  0,          0,      0,         0,      0,      0;
          5, 10,  0,          0,      0,         0,     -2,      0;
        100,  0,  0,          0,      0,         0,      0,      0];

fprintf('\n[1] 真值轨迹 + 完美里程计（100 Hz，双子样）\n');
avp0 = [0;0;0; 0;0;0; 29*deg; 106*deg; 450.0];
trj = trjsimu(avp0, WAT, ts);                     % 正演机 → 真值 avp + imu
od  = odsimu(trj, zeros(3,1), 1.0);               % 完美里程（真值位移，kod=1）
fprintf('    imu 行数 = %d（期望 96600），总里程 = %.1f m\n', trj.len, sum(od(:,1)));

%% ========== 2) 确定性误差注入（与 P4 一致） ==========
fprintf('\n[2] 确定性误差注入\n');
eb   = [0.01; 0.01; 0.01]*dph;                    % 陀螺零偏 0.01°/h
db   = [100; 100; 100]*ug;                        % 加计零偏 100µg
davp = [0.5; 0.5; 5.0]*(deg/60);                  % 初始姿态误差（arcmin）
imu_e = trj.imu;                                  % 含误差 imu（SINS 吃它，不标定）
imu_e(:,1:3) = imu_e(:,1:3) + (eb*ts)';           % wm += eb·ts
imu_e(:,4:6) = imu_e(:,4:6) + (db*ts)';           % vm += db·ts
avp0e = [avp0(1:3)+davp; 0.1;0.1;0.1; ...
         avp0(7)+10/glv.Re; avp0(8)+10/(glv.Re*cos(avp0(7))); avp0(9)+10];
dinst = [15; 0; 10]*(deg/60);                     % 安装角误差（arcmin）
dkod  = 0.05;

%% ========== 3) KF 初始协方差/噪声（对齐 P4 / PSINS test_SINS_DR_def） ==========
N = 22;
web = (0.001*deg)/sqrt(3600);                     % 陀螺角度随机游走 0.001°/√h
wdb = 5e-6*glv.g0/sqrt(1.0);                      % 加计速度随机游走 5µg/√Hz
q_diag = [repmat(web^2,3,1); repmat(wdb^2,3,1); repmat(1e-14,16,1)];
Qk = diag(q_diag);                                % 只在 φ/δv 有量，其余≈0
Rk = diag([(10/glv.Re)^2; (10/glv.Re)^2; 10^2]);  % 位置量测 ~10m（lat/lon 转弧度）
dposP0 = [(100/glv.Re)^2; (100/glv.Re)^2; 100^2];
p0_diag = [(davp*10).^2; zeros(3,1); dposP0; ...  % φ, δv(=0), δr
           (eb*10).^2; (db*10).^2; dposP0; ...    % eb, db, dposD
           (dinst([1;3])*10).^2; (dkod*10)^2; (0.01*10)^2];
P0 = diag(p0_diag);

kf = kfinit(N, ts);
kf.Pk = P0;  kf.Qk = Qk;  kf.Rk = Rk;  kf.xk = zeros(N,1);

%% ========== 4) 解算 A：SINS-only（free，无 DR/无 KF） ==========
fprintf('\n[3] SINS-only（free，无 DR/无 KF）\n');
m = floor(trj.len/nn);
ins_s = data_classes('ins');
ins_s.qnb = a2qua(avp0e(1:3));  ins_s.vn = avp0e(4:6);  ins_s.pos = avp0e(7:9);
avp_sins = zeros(m, 10);
for ki = 1:m
    k = (ki-1)*nn + 1;
    ins_s = insupdate(ins_s, imu_e(k:k+1,1:3), imu_e(k:k+1,4:6), ts);
    avp_sins(ki,:) = [q2att(ins_s.qnb); ins_s.vn; ins_s.pos; trj.imu(k+1,7)]';
end

%% ========== 5) 解算 B：DR-only（自积分姿态，含 dinst/dkod 误差） ==========
fprintf('\n[4] DR-only（自积分姿态，含安装/尺度误差）\n');
dr_o = drinit(avp0e, dinst, 1.0*(1+dkod), ts);
avp_dr = zeros(m, 10);
for ki = 1:m
    k = (ki-1)*nn + 1;
    dS = od(k,1) + od(k+1,1);
    dr_o = drupdate(dr_o, imu_e(k:k+1,1:3), dS);
    avp_dr(ki,:) = [dr_o.att; dr_o.vn; dr_o.pos; trj.imu(k+1,7)]';
end

%% ========== 6) 解算 C：组合（SINS + DR 锚定 + KF + 反馈） ==========
fprintf('\n[5] 组合解（SINS 主导 + DR 辅助，22 维 KF 自标定）\n');
ins = data_classes('ins');
ins.qnb = a2qua(avp0e(1:3));  ins.vn = avp0e(4:6);  ins.pos = avp0e(7:9);
dr  = drinit(avp0e, dinst, 1.0*(1+dkod), ts);
avp_comb = zeros(m, 10);
xk_rec = [];                                     % 记录量测时刻的状态估计
for ki = 1:m
    k = (ki-1)*nn + 1;
    wm = imu_e(k:k+1, 1:3);  vm = imu_e(k:k+1, 4:6);
    % --- SINS 前推（不标定：ins.eb=0/Kg=I 默认，吃含误差 imu）---
    ins = insupdate(ins, wm, vm, ts);
    % --- DR 锚定姿态 = SINS ---
    dr.qnb = ins.qnb;
    dS = od(k,1) + od(k+1,1);
    dr = drupdate(dr, wm, dS);
    % --- KF 时间更新：只推 P、不推 x（对齐 P4 kf_predict）---
    % ⚠️ 关键：P4 参考 gen_sins_dr.py 的 kf_predict 只做 P=Fd·P·Fd'+Q，
    %    从不推进状态 x（x 仅由量测更新驱动）。若用 kfupdate(kf)（推 x：
    %    xk=Φ·xk），未清零的慢参数态（φ/δr/db/dKod/dT）会经 Φ 耦合进
    %    δv 预测 → xfb 偏大 → 反馈过冲 → 组合 267 m（M4 实测 bug，
    %    2026-08-25 修复：267.1 → 44.9，对齐 P4 45.5）。
    kf.Phikk_1 = kffk(ins);
    kf.Pk = kf.Phikk_1 * kf.Pk * kf.Phikk_1' + kf.Qk;
    % --- 量测（每 5 batch = 10 个 IMU 样本 ≈0.1s）---
    if mod(ki, 5) == 0
        z = ins.pos - dr.pos;                    % [dlat; dlon; dh]（与 PSINS 一致）
        H = zeros(3, N);
        H(1:3,7:9)   =  eye(3);                  % δr -> 位置差
        H(1:3,16:18) = -eye(3);                  % dposD -> 位置差（DR 位置误差）
        RMh = ins.eth.RMh;  RNh = ins.eth.RNh;
        Mpvvn = [ins.vn(2)/RMh; ins.vn(1)/(RNh*cos(ins.pos(1))); ins.vn(3)];
        H(1:3,22) = -Mpvvn;                      % dT -> 位置差
        kf.Hk = H;
        kf = kfupdate(kf, z);
        % --- 反馈（对齐 PSINS test_SINS_DR 'v'：仅速度闭环）---
        %    xk = (est - true)，修正 = est - xk → ins.vn -= xk(4:6)。
        %    只清零已回灌的 δv（等价 kffeedback 'v'）；φ/δr/eb/db/dKod/dinst/dT
        %    跨时间累积——这是 dKod 等慢参数能被在线辨识的前提！
        xfb = kf.xk(4:6);
        ins.vn = ins.vn - xfb;
        kf.xk(4:6) = 0;
        xk_rec = [xk_rec; kf.xk', trj.imu(k+1,7)];   % 每行 = [xk(1:22), t] 共 23 列（水平拼接）
    end
    avp_comb(ki,:) = [q2att(ins.qnb); ins.vn; ins.pos; trj.imu(k+1,7)]';
end

%% ========== 7) 误差统计（对齐 P4：trj 奇数拍对齐 + wrap + 转米） ==========
Re_h = glv.Re + avp0(9);
trj_d = trj.avp(2:2:2*m, 1:9);                   % 双子样中心对齐（奇数拍）
fprintf('\n[6] 误差对比（vs 真值，%.0f s）\n', trj.len*ts);
errstats('SINS-only ', avp_sins, trj_d, Re_h, avp0(7));
errstats('DR-only   ', avp_dr,   trj_d, Re_h, avp0(7));
errstats('组合(22维) ', avp_comb, trj_d, Re_h, avp0(7));

%% ========== 8) 22 维在线自标定（末段 50s 平均 vs 注入真值） ==========
tail = xk_rec(end-499:end, :);                   % 末 500 次量测 = 50s
fprintf('\n[6.5] 22 维在线自标定（末段 50s 平均 vs 注入真值）\n');
fprintf('    dKod   = %+.4f（真值 %+.2f）', mean(tail(:,21)), dkod);
fprintf(' | dpitch = %+.1f''（真值 %+.1f''）', mean(tail(:,19))/deg*60, dinst(1)/deg*60);
fprintf(' | dyaw = %+.1f''（真值 %+.1f''）\n', mean(tail(:,20))/deg*60, dinst(3)/deg*60);
fprintf('    dT     = %+.4f s（真值 0）', mean(tail(:,22)));
fprintf(' | eb = %+.3f °/h（真值 %+.2f）', mean(tail(:,10:12))/dph, eb(1)/dph);
fprintf(' | db = %+.0f µg（真值 %+.0f）\n', mean(tail(:,13:15))/ug, db(1)/ug);

%% ========== 9) 可视化（真值 + 三解 4 色叠加 + 残差 + 3D） ==========
% 绘图函数在 assets/（miniinsplot / miniavpcmpplot / miniinsplot3d，零依赖自写）
% 输出 png 存到 assets/（与 gen_sins_dr.py 双轨同名，可对拍）
plot_dir = fullfile(fileparts(fileparts(mfilename('fullpath'))), '..');
addpath(plot_dir);
avp_trj = trj.avp(2:2:2*m, 1:10);               % 真值（奇数拍对齐，与误差统计一致）

% ① 轨迹叠加（真值黑 + SINS-only红 + DR-only蓝 + 组合绿）
miniinsplot({avp_sins, avp_dr, avp_comb}, avp_trj, 'cmp_sinsdr', ...
            {'SINS-only','DR-only','Combined'});
saveas(gcf, fullfile(plot_dir, 'miniinsplot_cmp_sinsdr_m.png')); close(gcf);

% ② 姿态/速度/位置残差对比（真值 vs 三解）——miniavpcmpplot 内部自己做 2:2:end 对齐，传全密度真值
miniavpcmpplot(trj.avp(1:2*m, 1:10), {avp_sins, avp_dr, avp_comb}, ...
               {'SINS-only','DR-only','Combined'}, fullfile(plot_dir, 'miniavpcmpplot_sinsdr_m.png'));

% ③ 3D 轨迹对比（真值黑 Z=0 参考面 + 三解，Z=高度误差×8 显示放大）
try
    miniinsplot3d({avp_sins, avp_dr, avp_comb}, avp_trj, 'cmp_sinsdr', ...
                  {'SINS-only','DR-only','Combined'});
    saveas(gcf, fullfile(plot_dir, 'miniinsplot3d_cmp_sinsdr_m.png')); close(gcf);
catch
    fprintf('   （3D 图在 batch 模式可能不可用，已跳过）\n');
end
fprintf('\n[7] 可视化完成：miniinsplot_cmp_sinsdr_m / miniavpcmpplot_sinsdr_m / miniinsplot3d_cmp_sinsdr_m（assets/）\n');
end

%% ========== 局部函数：误差统计（对齐 P4 errstats） ==========
function errstats(name, avp, trj_d, Re_h, lat0)
n = min(size(avp,1), size(trj_d,1));
avp = avp(1:n,:);  trj_d = trj_d(1:n,:);
de = avp(:,1:3) - trj_d(:,1:3);
de(:,3) = wrap_pi(de(:,3));                      % yaw 差 wrap 到 [-π,π]
dv = avp(:,4:6) - trj_d(:,4:6);
dp = avp(:,7:9) - trj_d(:,7:9);
dph = [dp(:,1)*Re_h, dp(:,2)*Re_h*cos(lat0), dp(:,3)];   % lat/lon 转米
dhoriz = hypot(dph(:,1), dph(:,2));
fprintf('    [%s] att RMS = (%.1f, %.1f, %.1f) arcsec', name, ...
    mean(abs(de(:,1)))/deg2rad(1)*3600, mean(abs(de(:,2)))/deg2rad(1)*3600, ...
    mean(abs(de(:,3)))/deg2rad(1)*3600);
fprintf(' | vel RMS = [%.3f %.3f %.3f] m/s\n', mean(abs(dv)));
fprintf('             水平位置 RMS = %.1f m, 末点 = %.1f m', mean(dhoriz), dhoriz(end));
fprintf(' | 垂直 = %.1f m (末 %.1f m)\n', mean(abs(dph(:,3))), dph(end,3));
end

function w = wrap_pi(a)
w = mod(a + pi, 2*pi) - pi;
end
