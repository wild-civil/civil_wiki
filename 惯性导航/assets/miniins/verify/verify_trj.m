function [nPass, nFail] = verify_trj()
% verify_trj - 轨迹生成模块自洽性测试（Mini-INS M2 回归）
%
% 运行：cd docs/惯性导航/assets/miniins/verify; verify_trj
% 要求：无工具箱，确定性。
%
% 自洽性原理（P2 的"正演→反演闭环"）：
%   trjsimu 从"想要的姿态/速度/位置"反算 wm/vm（正演），
%   insupdate 从 wm/vm 积分回姿态/速度/位置（反演）。
%   无误差注入时，反演应复现正演的真值 avp —— 证明生成与解算
%   是同一套数学的互逆对（误差应 cm~m 级，来源为位置微分的
%   欧拉/梯形积分差与双子样对齐，P2 自洽性测试同量级）。

addpath(fullfile(fileparts(mfilename('fullpath')), '..', 'core'));  % 保证找到 core 函数
glv = glvs();
fprintf('=== Mini-INS trjsimu 自洽性测试 ===\n');
nPass = 0; nFail = 0;

%% 1) 造轨迹：加速5s(a=2) → 匀速100s → 左转30s(w=2°/s) → 匀速20s（共 155 s）
seg = trjsegment([], 'init');                % 初始化（初速 0）
seg = trjsegment(seg, 'accelerate', 5, 2);   % 直线加速：v: 0→10 m/s
seg = trjsegment(seg, 'uniform', 100);       % 匀速 10 m/s
seg = trjsegment(seg, 'turnleft', 30, 2);    % 协调左转（cf = ω·v ≈ 0.35 m/s²）
seg = trjsegment(seg, 'uniform', 20);        % 收尾匀速
avp0 = [0;0;0; 0;0;0; 29*glv.deg; 106*glv.deg; 450];   % 西安附近静止起步
ts = 0.01;                                   % 100 Hz
trj = trjsimu(avp0, seg.wat, ts);
fprintf('  轨迹：%.0f s / %d 拍，末位置 (%.4f°, %.4f°, %.1f m)\n', ...
    trj.len*ts, trj.len, trj.avp(end,7)/glv.deg, trj.avp(end,8)/glv.deg, trj.avp(end,9));

%% 2) 反演：从 avp0 起，insupdate 双子样积分
ins = data_classes('ins');
ins.qnb = cnb2q(euler2cnb(avp0(1:3)));       % 初始姿态→四元数
ins.vn  = avp0(4:6);
ins.pos = avp0(7:9);
n2 = floor((trj.len-1)/2);                   % 双子样输出行数
avp2 = zeros(n2, 9);
for k = 1:n2
    k1 = 2*k - 1;                            % 双子样起点
    ins = insupdate(ins, trj.imu(k1:k1+1,1:3), trj.imu(k1:k1+1,4:6), ts);
    avp2(k,:) = [cnb2euler(q2cnb(ins.qnb)); ins.vn; ins.pos]';
end

%% 3) 对齐比较（双子样对齐：真值取 2:2:end，P2 坑 5）
truth = trj.avp(2:2:2*n2, 1:9);
errAtt = avp2(:,1:3) - truth(:,1:3);
errVel = avp2(:,4:6) - truth(:,4:6);
errPos = avp2(:,7:9) - truth(:,7:9);
eth0 = earth(avp0(7:9), avp0(4:6));         % 转米用初始位置的地球参数
errPosM = [errPos(:,1)*eth0.RMh,  errPos(:,2)*eth0.RNh*cos(avp0(7)),  errPos(:,3)];
rmsA = sqrt(mean(sum(errAtt.^2, 2)));
rmsV = sqrt(mean(sum(errVel.^2, 2)));
rmsP = sqrt(mean(sum(errPosM.^2, 2)));
fprintf('  自洽误差 RMS：att %.3e rad | vel %.3e m/s | pos %.3e m\n', rmsA, rmsV, rmsP);
fprintf('  末点位置误差：%.2f m\n', norm(errPosM(end,:)));

ok = check('trjsimu→insupdate 自洽（位置<20 m）',  rmsP, 20);   nPass=nPass+ok; nFail=nFail+~ok;
ok = check('trjsimu→insupdate 自洽（姿态<0.01 rad）', rmsA, 0.01); nPass=nPass+ok; nFail=nFail+~ok;
ok = check('trjsimu→insupdate 自洽（速度<0.5 m/s）', rmsV, 0.5); nPass=nPass+ok; nFail=nFail+~ok;

%% 汇总
fprintf('----------------------------------------\n');
fprintf('RESULT: %d PASS, %d FAIL\n', nPass, nFail);
if nFail == 0, fprintf('VERDICT: ALL PASS √\n'); else, fprintf('VERDICT: FAIL ×\n'); end
end

function ok = check(name, err, tol)
ok = err < tol;
if ok, fprintf('  PASS  %s\n', name); else, fprintf('  FAIL  %s (err=%.2e > %.0e)\n', name, err, tol); end
end
