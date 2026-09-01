function [nPass, nFail] = cmp_sil(tol, mode)
% cmp_sil - SIL 对拍：比较 C 输出与 MATLAB oracle 期望
%
% 用法：cmp_sil()               默认 double 允差 1e-13
%       cmp_sil(1e-5, 'float')  单精度构建用（累积量允差放宽）
% 判据：逐 case 取有效列的最大绝对误差 < 允差

if nargin < 1 || isempty(tol),  tol  = 1e-13; end
if nargin < 2 || isempty(mode), mode = 'double'; end
d = fullfile(fileparts(mfilename('fullpath')), 'data');
rd = @(f) readmatrix(fullfile(d, f));
fprintf('=== Mini-INS C 版 SIL 对拍（%s，允差 %.1e）===\n', mode, tol);
nPass = 0;  nFail = 0;

%% 1) trans 系列（按 code 取有效列）
in = rd('tv_trans_in.csv');  ex = rd('tv_trans_exp.csv');  ou = rd('out_trans.csv');
ncols = containers.Map({1,2,3,4,5,6}, {9,4,4,4,9,3});
names = containers.Map({1,2,3,4,5,6}, {'q2dcm','dcm2q','rv2q','qmul','a2dcm(NED)','dcm2att(NED)'});
for code = 1:6
    idx = in(:,1) == code;
    n   = ncols(code);
    e   = max(abs(ou(idx,2:1+n) - ex(idx,2:1+n)), [], 'all');
    if e < tol, nPass=nPass+1; fprintf('  [PASS] trans/%s：max|err| = %.3e（%d 例）\n', names(code), e, sum(idx));
    else,       nFail=nFail+1; fprintf('  [FAIL] trans/%s：max|err| = %.3e（%d 例）\n', names(code), e, sum(idx));
    end
end

%% 2) TRIAD
ex = rd('tv_triad_exp.csv');  ou = rd('out_triad.csv');
e = max(abs(ou - ex), [], 'all');
if e < tol, nPass=nPass+1; fprintf('  [PASS] triad：max|err| = %.3e\n', e);
else,       nFail=nFail+1; fprintf('  [FAIL] triad：max|err| = %.3e\n', e);
end

%% 3) Mahony（逐步对拍 q 与积分项）
ex = rd('tv_mahony_exp.csv');  ou = rd('out_mahony.csv');
e = max(abs(ou - ex), [], 'all');
if e < tol, nPass=nPass+1; fprintf('  [PASS] mahony：max|err| = %.3e（%d 步）\n', e, size(ex,1));
else,       nFail=nFail+1; fprintf('  [FAIL] mahony：max|err| = %.3e（%d 步）\n', e, size(ex,1));
end

%% 4) 功能性检查（不判 PASS/FAIL，仅报告）：静止段末姿态误差
tr = rd('truth_mahony.csv');
if exist(fullfile(d,'seq_info.txt'),'file')
    nA = str2double(fileread(fullfile(d,'seq_info.txt')));
else
    nA = 1000;                                          % 默认：静止段 10 s @100 Hz
end
if size(ou,1) >= nA && size(tr,1) >= nA
    q = ou(nA,1:4)';  C = q2dcm_local(q);
    att = [atan2(C(3,2),C(3,3)); asin(max(-1,min(1,-C(3,1)))); atan2(C(2,1),C(1,1))];
    fprintf('  [INFO] 静止段（10 s）末姿态误差 = [%.3f %.3f %.3f]°（真值 0，含 3~5° 初始误差）\n', ...
            att(1)*180/pi, att(2)*180/pi, att(3)*180/pi);
end

fprintf('=== 结果：%d PASS / %d FAIL ===\n', nPass, nFail);
end

function C = q2dcm_local(q)
w=q(1); x=q(2); y=q(3); z=q(4);
C = [1-2*(y^2+z^2),   2*(x*y-z*w),   2*(x*z+y*w);
       2*(x*y+z*w), 1-2*(x^2+z^2),   2*(y*z-x*w);
       2*(x*z-y*w),   2*(y*z+x*w), 1-2*(x^2+y^2)];
end
