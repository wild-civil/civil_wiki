function [nPass, nFail] = verify_trans()
% verify_trans - trans 模块数值自检（Mini-INS 回归测试）
%
% 运行：cd docs/惯性导航/assets/miniins/verify; verify_trans
% 要求：无任何工具箱，固定随机种子（确定性，每次结果一致）。
%
% 覆盖：
%   1. q2cnb ↔ cnb2q 互逆
%   2. euler2cnb ↔ cnb2euler 互逆
%   3. qmul 旋转合成一致性（q1⊗q2 的 C == C1·C2）
%   4. rv2m ↔ m2rv 互逆
%   5. rv2q 与 cnb2q(rv2m(rv)) 两种路径一致
%   6. qmulv 与 q2cnb(q)·vb 一致
%   7. skew ↔ vecc 互逆
%   8. qconj：q ⊗ q* = 单位元（归一化后）
%   9. 已知值：绕 z 转 90° 的 rv2m / euler2cnb 结果

addpath(fullfile(fileparts(mfilename('fullpath')), '..', 'core'));  % 保证找到 core 函数
glv = glvs();
fprintf('=== Mini-INS trans 模块自检 ===\n');
nPass = 0; nFail = 0;

rng(42);   % 固定种子，确定性

%% 1) q2cnb ↔ cnb2q 互逆
for k = 1:20
    q = randn(4,1);  q = q/norm(q);                 % 随机合法四元数
    if q(1) < 0, q = -q; end                        % 符号归一：cnb2q 强制 w>0（PSINS a2qua 约定）
    err = norm(cnb2q(q2cnb(q)) - q);
    ok = check('1.q2cnb↔cnb2q 互逆', err, 1e-9);  nPass=nPass+ok; nFail=nFail+~ok;
end

%% 2) euler2cnb ↔ cnb2euler 互逆
for k = 1:20
    att = (rand(3,1)-0.5) * 0.9*pi;                 % 随机姿态（避开 ±90° 奇点）
    err = norm(cnb2euler(euler2cnb(att)) - att);
    ok = check('2.euler2cnb↔cnb2euler 互逆', err, 1e-9);  nPass=nPass+ok; nFail=nFail+~ok;
end

%% 3) qmul 旋转合成一致性
for k = 1:20
    q1 = randn(4,1); q1=q1/norm(q1);  q2 = randn(4,1); q2=q2/norm(q2);
    C12 = q2cnb(qmul(q1, q2));                       % 合成旋转的姿态阵
    C1C2 = q2cnb(q1) * q2cnb(q2);                    % 矩阵乘积（先 q2 后 q1）
    ok = check('3.qmul 合成一致性 C(q1⊗q2)=C1·C2', norm(C12-C1C2), 1e-9);  nPass=nPass+ok; nFail=nFail+~ok;
end

%% 4) rv2m ↔ m2rv 互逆
for k = 1:20
    rv = (rand(3,1)-0.5) * 2.5;                      % 随机旋转矢量（转角 < π 附近）
    err = norm(m2rv(rv2m(rv)) - rv);
    ok = check('4.rv2m↔m2rv 互逆', err, 1e-9);  nPass=nPass+ok; nFail=nFail+~ok;
end

%% 5) rv2q 与 cnb2q(rv2m) 两种路径一致
for k = 1:20
    rv = (rand(3,1)-0.5) * 2.5;
    qa = rv2q(rv);  qb = cnb2q(rv2m(rv));
    if qa(1)<0, qa = -qa; end   % 符号归一后再比
    err = norm(qa - qb);
    ok = check('5.rv2q 与 cnb2q(rv2m) 一致', err, 1e-9);  nPass=nPass+ok; nFail=nFail+~ok;
end

%% 6) qmulv 与 q2cnb(q)·vb 一致
for k = 1:20
    q = randn(4,1); q=q/norm(q);  vb = randn(3,1);
    err = norm(qmulv(q, vb) - q2cnb(q)*vb);
    ok = check('6.qmulv 与 q2cnb·vb 一致', err, 1e-9);  nPass=nPass+ok; nFail=nFail+~ok;
end

%% 7) skew ↔ vecc 互逆
v = [1;2;3];
err = norm(vecc(skew(v)) - v);
ok = check('7.skew↔vecc 互逆', err, 1e-12);  nPass=nPass+ok; nFail=nFail+~ok;
err = norm(skew(v)*[4;5;6] - cross(v,[4;5;6]));
ok = check('7.skew·w == v×w', err, 1e-12);  nPass=nPass+ok; nFail=nFail+~ok;

%% 8) qconj：q ⊗ q* = 单位元
q = [0.3;0.4;0.5;0.7]; q = q/norm(q);
err = norm(qmul(q, qconj(q)) - [1;0;0;0]);
ok = check('8.q⊗q*=单位元', err, 1e-12);  nPass=nPass+ok; nFail=nFail+~ok;

%% 9) 已知值
err = norm(rv2m([0;0;pi/2]) - [0 -1 0; 1 0 0; 0 0 1]);
ok = check('9.rv2m 绕z转90°', err, 1e-12);  nPass=nPass+ok; nFail=nFail+~ok;
err = norm(euler2cnb([0;0;pi/2]) - [0 -1 0; 1 0 0; 0 0 1]);
ok = check('9.euler2cnb 绕z转90°', err, 1e-12);  nPass=nPass+ok; nFail=nFail+~ok;

%% 汇总
fprintf('----------------------------------------\n');
fprintf('RESULT: %d PASS, %d FAIL\n', nPass, nFail);
if nFail == 0, fprintf('VERDICT: ALL PASS √\n'); else, fprintf('VERDICT: FAIL ×\n'); end
end

function ok = check(name, err, tol)
% check - 断言并打印。err 小于 tol 即 PASS。
ok = err < tol;
if ok, fprintf('  PASS  %s\n', name); else, fprintf('  FAIL  %s (err=%.2e > %.0e)\n', name, err, tol); end
end
