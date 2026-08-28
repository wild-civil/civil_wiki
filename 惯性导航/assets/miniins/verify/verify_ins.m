function [nPass, nFail] = verify_ins()
% verify_ins - insupdate 机械编排数值自检（Mini-INS 回归测试）
%
% 运行：cd docs/惯性导航/assets/miniins/verify; verify_ins
% 要求：无工具箱，确定性。
%
% 覆盖：
%   A. 姿态更新：双子样各绕 z 转 45°（总 90°），yaw 应 ≈ 90°
%      （验证 ⑥ 姿态更新：圆锥补偿 + rv2q + 四元数乘法）
%   B. 比力方程自洽：静止 + 重力补偿比力输入 → vn / 水平位置不变
%      （验证 ④⑤：比力 fn + gcc = 0 运动加速度，梯形位置积分不漂移）
%
% 说明：insupdate 的"对拍级"验证（与 PSINS test_SINS 935.9 vs 936.0 m）
% 需要 M2 的 trjsimu 数据母版，M1 先做运动学自洽；两者互补。

addpath(fullfile(fileparts(mfilename('fullpath')), '..', 'core'));  % 保证找到 core 函数
glv = glvs();
fprintf('=== Mini-INS insupdate 机械编排自检 ===\n');
nPass = 0; nFail = 0;

%% A) 姿态更新：双子样绕 z 各 45°，总 90°
ins = data_classes('ins');           % 初始 ins（qnb=单位元, vn=0, pos=原点）
ts = 0.01;                           % 采样间隔 100 Hz
wmA = repmat([0, 0, pi/4], 2, 1);    % 两个子样各 45° 角增量（rad）
vmA = zeros(2,3);                    % 无速度增量（纯旋转）
ins = insupdate(ins, wmA, vmA, ts);  % 推进一个双子样
att = cnb2euler(q2cnb(ins.qnb));     % 解算姿态
errA = abs(att(3) - pi/2);           % yaw 应 ≈ 90°（wnin 补偿在 0.02s 内贡献 < 1e-4 rad）
ok = check('A. 双子样姿态更新 yaw≈90°', errA, 1e-3);  nPass=nPass+ok; nFail=nFail+~ok;
ok = check('A. pitch/roll 保持 0°', norm(att(1:2)), 1e-3);  nPass=nPass+ok; nFail=nFail+~ok;

%% B) 比力方程自洽：静止 + 重力补偿 → vn/pos 不变
ins2 = data_classes('ins');          % vn=0, pos=原点
wmB = zeros(2,3);                    % 无旋转
vmB = repmat([0, 0, glv.g0*ts], 2, 1);  % 加计输出 = 比力 −gn 的增量（ENU 下 [0;0;+g0]）
ins2 = insupdate(ins2, wmB, vmB, ts);
errB = norm(ins2.vn) + norm(ins2.pos(1:2));  % 运动加速度应为 0 → vn 不变、水平位置不变
ok = check('B. 静止比力自洽 vn/pos 守恒', errB, 1e-4);  nPass=nPass+ok; nFail=nFail+~ok;

%% 汇总
fprintf('----------------------------------------\n');
fprintf('RESULT: %d PASS, %d FAIL\n', nPass, nFail);
if nFail == 0, fprintf('VERDICT: ALL PASS √\n'); else, fprintf('VERDICT: FAIL ×\n'); end
end

function ok = check(name, err, tol)
ok = err < tol;
if ok, fprintf('  PASS  %s\n', name); else, fprintf('  FAIL  %s (err=%.2e > %.0e)\n', name, err, tol); end
end
