function [nPass, nFail] = verify_dr()
% verify_dr - 航位推算模块自洽性测试（Mini-INS M3 回归）
%
% 运行：cd docs/惯性导航/assets/miniins/verify; verify_dr
% 要求：无工具箱，确定性。
%
% 原理（P3 的"航向×里程"）：
%   用 trjsimu 造一条轨迹 → 里程 dS = |vn|·ts（车前进距离）→ drinit →
%   逐拍 drupdate(wm, dS) 推 DR 位置 → 与真值 avp 比较。
%   无误差注入（Kg=1、无安装角）时，DR 位置应复现真值（cm~m 级），
%   证明"里程 + 航向 → 位置"这条独立链路的数学正确。

addpath(fullfile(fileparts(mfilename('fullpath')), '..', 'core'));  % 保证找到 core 函数
glv = glvs();
fprintf('=== Mini-INS drinit/drupdate 自洽性测试 ===\n');
nPass = 0; nFail = 0;

%% 1) 造轨迹（与 verify_trj 同一场景）
seg = trjsegment([], 'init');
seg = trjsegment(seg, 'accelerate', 5, 2);     % v: 0→10 m/s
seg = trjsegment(seg, 'uniform', 100);
seg = trjsegment(seg, 'turnleft', 30, 2);      % 协调左转 60°
seg = trjsegment(seg, 'uniform', 20);
avp0 = [0;0;0; 0;0;0; 29*glv.deg; 106*glv.deg; 450];
ts = 0.01;
trj = trjsimu(avp0, seg.wat, ts);

%% 2) 构造里程：dS = 水平速度 × ts（车前进距离；垂直速度≈0 故用 |vn|）
dS = sqrt(sum(trj.avp(:,4:6).^2, 2)) .* trj.ts;   % N×1 每拍里程增量

%% 3) DR 解算
dr = drinit(avp0, [0;0], 1, ts);                 % 无安装误差、刻度 1
pos_dr = zeros(trj.len, 3);
for k = 1:trj.len
    dr = drupdate(dr, trj.imu(k,1:3)', dS(k));   % wm 每拍（单子样）
    pos_dr(k,:) = dr.pos';
end

%% 4) 比较（lat/lon 弧度差转米）
eth0 = earth(avp0(7:9), avp0(4:6));
err = pos_dr - trj.avp(:,7:9);                   % [dlat; dlon; dh]
errM = [err(:,1)*eth0.RMh,  err(:,2)*eth0.RNh*cos(avp0(7)),  err(:,3)];
rmsP = sqrt(mean(sum(errM.^2, 2)));
fprintf('  轨迹：%.0f s / %d 拍 | 末点真值 (%.4f°, %.4f°, %.1f m)\n', ...
    trj.len*ts, trj.len, trj.avp(end,7)/glv.deg, trj.avp(end,8)/glv.deg, trj.avp(end,9));
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
