% gen_kf1d.m — 一维 2 态卡尔曼滤波演示（10 篇：卡尔曼滤波基础）
%
% 场景：匀速直线运动 p(t)=v0·t，v0=5 m/s；量测只有位置 z=p+n，n~N(0,R)。
% 教学点：
%   ① KF 五方程在 2×2 系统上的逐行实现（对应牛小骥讲义第 4 讲式 1-5）
%   ② 量测只测位置，但 KF 能估出速度（状态耦合的魔法）
%   ③ 协方差 P 单调收缩 → 估计误差收敛到 < 单点量测噪声
%   ④ 误差落在 ±3σ 带内 → P 自洽（滤波器不"过度自信/过度悲观"）
% 输出：kf1d_estimate.png（4 子图）
% 对照：Python 脚本 gen_kf1d_py.py 独立实现，数值应一致（双轨验证）
clear; clc; close all;

% —— 场景与模型 ——
dt   = 1.0;            % 采样周期 s
N    = 50;             % 步数
v0   = 5.0;            % 真速度 m/s
p0   = 0.0;            % 真初始位置 m
R    = 25.0;           % 量测噪声方差（σ=5 m）
Q    = diag([1e-3, 1e-3]);   % 过程噪声（匀速假设，小量）

% —— 系统矩阵（离散化）——
%   状态 x = [p; v]；x_{k} = Φ x_{k-1} + w；z_k = H x_k + v
Phi  = [1, dt; 0, 1];
Gam  = [dt^2/2; dt];            % 噪声驱动阵（加速度噪声 → 位置/速度）
H    = [1, 0];                  % 量测矩阵：只测位置
Gamma = [dt^2/2, 0; 0, dt];     % 过程噪声驱动（2×2，教学简化用对角）

% —— 生成真值 + 量测 ——
rng(42);
t    = (0:N)';
p    = p0 + v0*t;               % 真值位置
z    = p + sqrt(R)*randn(N+1,1); % 量测（带噪）

% —— KF 五方程（显式循环，逐行对应讲义式 4-8）——
x   = [0; 0];                   % 初始估计：位置 0、速度 0（不知道初速！）
P   = diag([100, 100]);         % 初始协方差：大（体现"不确定"）
xH  = zeros(N+1, 2); pH = zeros(N+1, 2); xH(1,:) = x';
for k = 1:N+1
    % —— 时间更新（预测，讲义式 4-5）——
    if k > 1
        x = Phi*x;
        P = Phi*P*Phi' + Gamma*Q*Gamma';
    end
    % —— 量测更新（修正，讲义式 6-8）——
    S   = H*P*H' + R;           % 新息协方差 S = HPH' + R
    K   = (P*H')/S;             % 增益 K = PH'/S
    r   = z(k) - H*x;           % 新息 r = z - Hx̂
    x   = x + K*r;              % 状态修正 x̂⁺ = x̂⁻ + K·r
    P   = (eye(2) - K*H)*P;     % 协方差修正 P⁺ = (I-KH)P⁻
    xH(k,:) = x'; pH(k,:) = [P(1,1), P(2,2)];
end

% —— 稳态增益（理论）——
Kinf = (sqrt(R)+0);  % 占位（实际用数值观察）

% —— 画图 ——
figure('Position',[100 100 1100 800]);
% 子图1：位置 真值/量测/估计
subplot(221);
plot(t, p, 'k-', 'LineWidth',1.8); hold on;
plot(t, z, 'b.', 'MarkerSize',5);
plot(t, xH(:,1), 'r-', 'LineWidth',1.8);
legend({'真值','量测(σ=5m)','KF 估计'},'Location','nw','FontSize',8);
xlabel('t (s)'); ylabel('位置 (m)'); title('① 位置：估计平滑跟随，优于单点量测'); grid on;
% 子图2：速度
subplot(222);
plot(t, v0*ones(size(t)), 'k-', 'LineWidth',1.8); hold on;
plot(t, xH(:,2), 'r-', 'LineWidth',1.8);
legend({'真值 v=5','KF 速度估计'},'Location','se','FontSize',8);
xlabel('t (s)'); ylabel('速度 (m/s)'); title('② 速度：量测只有位置，KF 仍估出速度'); grid on;
% 子图3：协方差
subplot(223);
plot(t, sqrt(pH(:,1)), 'b-', 'LineWidth',1.6); hold on;
plot(t, sqrt(pH(:,2)), 'r-', 'LineWidth',1.6);
legend({'σ_p (m)','σ_v (m/s)'},'Location','ne','FontSize',8);
xlabel('t (s)'); ylabel('标准差'); title('③ 协方差收缩：P 单调下降'); grid on;
% 子图4：位置误差 + 3σ 带
subplot(224);
err = xH(:,1) - p;
plot(t, err, 'b-', 'LineWidth',1.4); hold on;
plot(t, 3*sqrt(pH(:,1)), 'r--', 'LineWidth',1); 
plot(t, -3*sqrt(pH(:,1)), 'r--', 'LineWidth',1);
legend({'位置误差','±3σ 带'},'Location','ne','FontSize',8);
xlabel('t (s)'); ylabel('误差 (m)'); title('④ 误差落在 ±3σ 带内（P 自洽）'); grid on;
saveas(gcf, 'kf1d_estimate.png');

% —— 关键数字 ——
fprintf('=== 一维 KF 演示 ===\n');
fprintf('量测噪声 σ=%.0f m；KF 位置估计稳态 σ_p ≈ %.2f m（%.1f%% 于量测）\n', ...
    sqrt(R), sqrt(pH(end,1)), sqrt(pH(end,1))/sqrt(R)*100);
fprintf('速度估计 50s 时 = %.2f m/s（真值 5.00）\n', xH(end,2));
fprintf('位置最终误差 = %.2f m（量测单点噪声 ±%.0f m 的 1/%.0f）\n', ...
    abs(err(end)), sqrt(R), sqrt(R)/abs(err(end)));
dlmwrite('kf1d_res.csv', [t, p, z, xH(:,1), xH(:,2), err, sqrt(pH(:,1)), sqrt(pH(:,2))], 'precision', 12);
disp('DONE');
