function [nPass, nFail] = verify_dr()
% verify_dr - 航位推算模块自洽性测试（Mini-INS M4 回归）
%
% 运行：cd docs/惯性导航/assets/miniins/verify; verify_dr
% 要求：无工具箱，确定性。
%
% ⚠️ M4 重写为 P4 形态（M3 版已废弃）：
%   · 轨迹用 P4 WAT 21 行（含俯仰机动，与 demo_sins_dr 同源）；
%   · 里程用 odsimu（真值位置差分 dS），不再用 |vn|·ts 近似；
%   · drupdate 为 M4 版（体 y 里程 + 半程姿态 + 圆锥 + wnin 补偿）；
%   · 双子样消费（每 2 拍一次），与 P4 主循环一致。
%
% 原理（P3 的"航向×里程"）：无误差注入（inst=0、kod=1）时，
% DR 位置应复现真值（cm~m 级）——证明"里程 + 航向 → 位置"这条
% 独立链路在 M4 约定（x 右 y 前 z 上、体 y 前向）下的数学正确。

addpath(fullfile(fileparts(mfilename('fullpath')), '..', 'core'));
glv = glvs();
deg = glv.deg;
fprintf('=== Mini-INS drinit/drupdate 自洽性测试（M4 版）===\n');
nPass = 0; nFail = 0;

%% 1) P4 WAT 轨迹（21 行，含俯仰机动——对拍 demo_sins_dr 同源）
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
avp0 = [0;0;0; 0;0;0; 29*deg; 106*deg; 450];
ts = 0.01;
trj = trjsimu(avp0, WAT, ts);                  % 正演机（M4 版）
od  = odsimu(trj, zeros(3,1), 1.0);            % 真值里程（kod=1）

%% 2) DR 解算（无误差：inst=0、kod=1；双子样消费）
dr = drinit(avp0, [0;0;0], 1, ts);
n2 = floor((trj.len-1)/2);
pos_dr = zeros(n2, 3);
for k = 1:n2
    k1 = 2*k - 1;                              % 双子样起点（1 基）
    dS = od(k1,1) + od(k1+1,1);                % 两拍里程和
    dr = drupdate(dr, trj.imu(k1:k1+1,1:3), dS);
    pos_dr(k,:) = dr.pos';
end

%% 3) 比较（双子样对齐 truth=2:2:end；lat/lon 弧度差转米）
truth = trj.avp(2:2:2*n2, 7:9);
eth0 = earth(avp0(7:9), avp0(4:6));
err = pos_dr - truth;
errM = [err(:,1)*eth0.RMh,  err(:,2)*eth0.RNh*cos(avp0(7)),  err(:,3)];
rmsP = sqrt(mean(sum(errM.^2, 2)));
fprintf('  轨迹：%.0f s / %d 拍 | 末点真值 (%.4f°, %.4f°, %.1f m)\n', ...
    trj.len*ts, trj.len, truth(end,1)/deg, truth(end,2)/deg, truth(end,3));
fprintf('  DR 位置 RMS：%.3f m | 末点误差：%.2f m\n', rmsP, norm(errM(end,:)));

ok = check('DR 航向×里程自洽（位置<20 m）', rmsP, 20);  nPass=nPass+ok; nFail=nFail+~ok;

%% 汇总
fprintf('----------------------------------------\n');
fprintf('RESULT: %d PASS, %d FAIL\n', nPass, nFail);
if nFail == 0, fprintf('VERDICT: ALL PASS √\n'); else, fprintf('VERDICT: FAIL ×\n'); end
end

function ok = check(name, err, tol)
ok = err < tol;
if ok, fprintf('  PASS  %s\n', name); else, fprintf('  FAIL  %s (err=%.2e > %.0e)\n', name, err, tol); end
end
