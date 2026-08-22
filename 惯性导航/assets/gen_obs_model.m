function gen_obs_model()
% 观测模型 H 矩阵构造 + 验证（本项目固件 ins_eskf_15d.c 锚定）
% ==============================================================
% 误差状态序（固件权威，0-based）：
%    [ p(0:2), v(3:5), phi(6:8), ba(9:11), bg(12:14) ]   共 15 维
%    p = NED 位置, v = NED 速度, phi = 3 维旋转矢量(姿态误差),
%    ba = 加计零偏, bg = 陀螺零偏
%    （MATLAB 1-based，代码里全部 +1：位置块 1:3 / 速度块 4:6 / 姿态块 7:9）
%
% 本脚本做三件事：
%   1) 按固件公式构造 5 种量测的 H 矩阵（GNSS 位置/速度、气压高度、加计、磁强计）
%   2) 有限差分验证 H 的正确性（解析 H 对 数值雅可比）
%   3) 演示可观测性解耦：加计只观 roll/pitch（重力方向），磁强计只观 yaw（航向）
%
% 纯 MATLAB（无工具箱），结果可直接复现；与 assets/gen_obs_model.py 数值一致。
% 运行：在 assets/ 目录下执行  gen_obs_model

G   = 9.81;
EPS = 1e-5;
R0  = eye(3);
mref = [1.0, 0.0, 0.4];

fprintf('%s\n', repmat('=', 1, 70));
fprintf('观测模型 H 矩阵（固件误差状态序 [p,v,phi,ba,bg]）\n');
fprintf('%s\n', repmat('=', 1, 70));

kinds = {'gnss_pos', 'gnss_vel', 'baro', 'accel', 'mag'};
for i = 1:numel(kinds)
    kind = kinds{i};
    H   = build_H(kind, R0, mref, G);
    err = fd_check(kind, R0, mref, G, EPS);
    fprintf('\n[%s]  H 形状 %dx15,  解析H vs 数值雅可比最大差 = %.3e\n', ...
            kind, size(H,1), err);
    nz = find(any(abs(H) > 1e-12, 1)) - 1;      % 0-based 列索引，与固件/正文一致
    fprintf('  非零误差态列索引: %s\n', join(string(nz), ', '));
    fprintf('  H =\n');
    for r = 1:size(H,1)
        fprintf('   %7.3f', H(r,:));
        fprintf('\n');
    end
end

observ_demo(G);

fprintf('\n[小结] 每种传感器点亮误差态的不同块：\n');
fprintf('  GNSS 位置 -> 位置块(0:2)        直接观测位置\n');
fprintf('  GNSS 速度 -> 速度块(3:5)        直接观测速度\n');
fprintf('  气压高度  -> 位置块 z(索引2)     仅观测高度(= -p_z)\n');
fprintf('  加计      -> 姿态块(6:8)        观测 roll/pitch(重力方向)\n');
fprintf('  磁强计    -> 姿态块(6:8)        观测 yaw(航向)\n');

end

% ---------------- 基础工具 ----------------
function S = skew(v)
% 3 维向量 v 的反对称矩阵（右误差雅可比用 +skew(h)）
x = v(1); y = v(2); z = v(3);
S = [0, -z, y; z, 0, -x; -y, x, 0];
end

function R = axis_angle_to_R(axis, ang)
% 罗德里格斯公式：绕 axis(单位向量) 旋转 ang(rad) 的旋转矩阵
axis = axis(:) / norm(axis);
K = skew(axis);
R = eye(3) + sin(ang)*K + (1 - cos(ang))*(K*K);
end

% ---------------- 量测预测函数 h(x_nom) ----------------
function h = h_gnss_pos(p), h = p(1:3);          end
function h = h_gnss_vel(v), h = v(4:6);          end
function h = h_baro(p),     h = -p(3);           end  % NED 下 z 向下为正，高度 = -p_z
function h = h_accel(R, G), h = R' * [0; 0; -G]; end  % 比力：R^T [0,0,-g]
function h = h_mag(R, mref), h = R' * mref(:);   end

% ---------------- 构造 H 矩阵（15 列，误差状态序） ----------------
function H = build_H(kind, R, mref, G)
% 位置/速度在固件里也走 3x15 的 eus3 联合更新；baro 才是 1x15 标量
if strcmp(kind, 'baro')
    H = zeros(1, 15);
else
    H = zeros(3, 15);
end
switch kind
    case 'gnss_pos'
        H(1,1) = 1.0; H(2,2) = 1.0; H(3,3) = 1.0;          % 位置块 1:3
    case 'gnss_vel'
        H(1,4) = 1.0; H(2,5) = 1.0; H(3,6) = 1.0;          % 速度块 4:6
    case 'baro'
        H(1,3) = -1.0;                                      % 高度 = -p_z
    case {'accel', 'mag'}
        if strcmp(kind, 'accel')
            h = h_accel(R, G);
        else
            h = h_mag(R, mref);
        end
        H(1:3, 7:9) = skew(h);                              % +skew(h)，姿态块 7:9
end
end

% ---------------- 有限差分验证 ----------------
function hp = predict_h(kind, p_pert, R_pert, mref, G)
% 按量测类型，用(扰动后的)名义态算预测值
switch kind
    case 'gnss_pos', hp = h_gnss_pos(p_pert);
    case 'gnss_vel', hp = h_gnss_vel(p_pert);
    case 'baro',     hp = h_baro(p_pert);
    case 'accel',    hp = h_accel(R_pert, G);
    case 'mag',      hp = h_mag(R_pert, mref);
end
end

function max_err = fd_check(kind, R0, mref, G, EPS)
% 对每一种量测，比较解析 H 与数值雅可比（对 15 个误差态逐列扰动）
p0  = zeros(15, 1);
H   = build_H(kind, R0, mref, G);
h0  = predict_h(kind, p0, R0, mref, G);
nrows = size(H, 1);
max_err = 0.0;
for j = 1:15
    p_pert = p0;
    R_pert = R0;
    if j <= 6                       % 位置/速度块（MATLAB 1-based 1:6）：直接平移名义态
        p_pert(j) = p_pert(j) + EPS;
    elseif j <= 9                   % 姿态块（7:9）：右乘小旋转
        axis = zeros(3, 1); axis(j - 6) = 1.0;
        R_pert = R0 * axis_angle_to_R(axis, EPS);
    end
    % ba/bg(10:15) 量测不依赖，名义态不变
    hp = predict_h(kind, p_pert, R_pert, mref, G);
    dh = (hp - h0) / EPS;
    for a = 1:nrows
        max_err = max(max_err, abs(dh(a) - H(a, j)));
    end
end
end

% ---------------- 可观测性解耦演示 ----------------
function observ_demo(G)
R0 = eye(3);                                % 名义：水平、朝北
mref = [1.0, 0.0, 0.4];                     % 导航系参考磁场：北向 + 向下(倾角)
fprintf('\n[可观测性] 名义 R=I, mref=[1,0,0.4]; 注入 10° 单轴姿态误差, 看各量测残差\n');
fprintf('%-10s%14s%16s\n', '误差轴', '加计残差|r|', '磁强计残差|r|');
axes_list = {'roll(x)',  [1 0 0], 10*pi/180;
             'pitch(y)', [0 1 0], 10*pi/180;
             'yaw(z)',   [0 0 1], 10*pi/180};
for i = 1:3
    name  = axes_list{i,1};
    axisv = axes_list{i,2};
    ang   = axes_list{i,3};
    Rerr  = axis_angle_to_R(axisv, ang);
    Rtrue = R0 * Rerr;                          % 右误差：R_true = R_nom * R(dθ)
    ra = h_accel(Rtrue, G) - h_accel(R0, G);    % 真值减名义 -> 残差方向
    rm = h_mag(Rtrue, mref) - h_mag(R0, mref);
    fprintf('%-10s%14.4f%16.4f\n', name, norm(ra), norm(rm));
end
fprintf('  -> 加计残差对 yaw≈0 (重力方向不含航向); 磁强计残差对 yaw 最大 (航向=罗盘)\n');
end
