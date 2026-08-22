% gen_ekf_vs_eskf.m — 直接法 EKF vs 误差状态 ESKF 对比（11 篇）
%
% 场景：CTRV 圆周运动（匀速圆周），状态 [x, y, ψ, v]，量测只有位置 (x,y)，
%       大初始航向误差 30°。对比：
%   直接法 EKF：状态=全量 [x,y,ψ,v]，雅可比在"估计点"线性化
%   ESKF（间接法）：名义态用真实非线性推进，误差态 δx=[δx,δy,δψ,δv]
%                   在"名义点"（≈真值）线性化，量测更新估计误差→反馈注入
%
% 教学点：
%   ① 直接法雅可比在偏离真值的估计点线性化 → 初始大误差时收敛慢/振荡
%   ② ESKF 误差态是小量 → 线性化精确 → 快速收敛
%   ③ 反馈注入：x_nom += δx，δx 清零（间接法标准流程）
% 输出：ekf_vs_eskf.png（4 子图）
% 对照：Python gen_ekf_vs_eskf_py.py 读 CSV 用同一份量测（双轨字节级一致）
clear; clc; close all;

% —— 场景参数 ——
dt = 1.0;  T = 100;  N = T/dt;
Rc = 100.0;  w = 0.05;  v_true = Rc*w;      % 圆周半径/角速度/速度
rng(42);
t = (0:N)';
xt = Rc*cos(w*t);  yt = Rc*sin(w*t);        % 真值轨迹
psit = w*t + pi/2;                           % 航向（切向）
zx = xt + sqrt(25)*randn(N+1,1);             % 位置量测 σ=5m
zy = yt + sqrt(25)*randn(N+1,1);

% —— 公共量测函数 ——
Hz = [1 0 0 0; 0 1 0 0];  Rz = 25*eye(2);    % 量测矩阵/噪声（直接法）
Hd = [1 0 0 0; 0 1 0 0];                     % 误差态量测矩阵（δz = z - h(x_nom)）

% —— 直接法 EKF（全量状态，雅可比在估计点）——
xE = [xt(1)+0; yt(1)+0; psit(1)+30*pi/180; v_true];   % 初始航向偏 30°
PE = diag([25, 25, (30*pi/180)^2, 1]);
QE = diag([1e-3, 1e-3, 1e-6, 1e-3]);
xEh = zeros(N+1,4); xEh(1,:) = xE;
for k = 1:N+1
    if k > 1
        % 预测（非线性 f）
        xE(1) = xE(1) + xE(4)*cos(xE(3))*dt;
        xE(2) = xE(2) + xE(4)*sin(xE(3))*dt;
        xE(3) = xE(3) + w*dt;                 % ω 已知
        % 雅可比 F（在估计点）
        F = [1 0 -xE(4)*sin(xE(3))*dt  cos(xE(3))*dt;
             0 1  xE(4)*cos(xE(3))*dt  sin(xE(3))*dt;
             0 0 1 0;
             0 0 0 1];
        PE = F*PE*F' + QE;
    end
    % 量测更新
    S = Hz*PE*Hz' + Rz;
    K = PE*Hz' / S;
    r = [zx(k); zy(k)] - Hz*xE;
    xE = xE + K*r;
    PE = (eye(4) - K*Hz)*PE;
    xEh(k,:) = xE;
end

% —— ESKF（误差状态，名义态非线性推进 + 误差态滤波 + 反馈注入）——
xN = [xt(1)+0; yt(1)+0; psit(1)+30*pi/180; v_true];   % 名义态：同样偏 30°
dx = zeros(4,1);  Pd = diag([25, 25, (30*pi/180)^2, 1]);  % 误差态：从 0 开始，P 反映"名义态可能偏 30°"
Qd = diag([1e-3, 1e-3, 1e-6, 1e-3]);
xNh = zeros(N+1,4); xNh(1,:) = xN;
for k = 1:N+1
    if k > 1
        % ① 名义态：真实非线性 f 推进
        xN(1) = xN(1) + xN(4)*cos(xN(3))*dt;
        xN(2) = xN(2) + xN(4)*sin(xN(3))*dt;
        xN(3) = xN(3) + w*dt;
        % ② 误差态：在名义点线性化（与直接法 F 同构，但用名义 ψ）
        Fd = [1 0 -xN(4)*sin(xN(3))*dt  cos(xN(3))*dt;
              0 1  xN(4)*cos(xN(3))*dt  sin(xN(3))*dt;
              0 0 1 0;
              0 0 0 1];
        dx = Fd*dx;
        Pd = Fd*Pd*Fd' + Qd;
    end
    % ③ 量测更新（误差态）：δz = 量测 - h(名义态)
    S = Hd*Pd*Hd' + Rz;
    K = Pd*Hd' / S;
    r = [zx(k); zy(k)] - [xN(1); xN(2)];
    dx = dx + K*r;
    Pd = (eye(4) - K*Hd)*Pd;
    % ④ 反馈注入：x_nom += δx，δx 清零
    xN = xN + dx;
    dx = zeros(4,1);
    xNh(k,:) = xN;
end

% —— 误差计算 ——
errE = sqrt((xEh(:,1)-xt).^2 + (xEh(:,2)-yt).^2);
errN = sqrt((xNh(:,1)-xt).^2 + (xNh(:,2)-yt).^2);
psiE = wrapToPi(xEh(:,3)-psit);  psiN = wrapToPi(xNh(:,3)-psit);
% 等价性实证：直接法 EKF 与 ESKF 估计差应 ~0（都是最优线性估计，理论预期）
equiv = max(abs(xEh(:) - xNh(:)));
fprintf('=== 直接法 EKF vs ESKF（圆周运动, 初始航向误差 30°）===\n');
fprintf('位置 RMSE 全程   : EKF %.2f m | ESKF %.2f m\n', sqrt(mean(errE.^2)), sqrt(mean(errN.^2)));
fprintf('航向误差 100s 时 : EKF %.1f° | ESKF %.1f°\n', abs(psiE(end))*180/pi, abs(psiN(end))*180/pi);
fprintf('★ 等价性: max|EKF - ESKF| = %.3e m —— 两者数学等价（弱非线性+强可观）\n', equiv);
fprintf('  → 差异在姿态流形/高维/数值场景显现（见 11 篇正文第六节）\n');

% —— 画图 ——
figure('Position',[100 100 1100 800]);
subplot(221);
plot(xt, yt, 'k-', 'LineWidth',1.6); hold on;
plot(xEh(:,1), xEh(:,2), 'r-', 'LineWidth',1.2);
plot(xNh(:,1), xNh(:,2), 'g-', 'LineWidth',1.4);
legend({'真值','直接法 EKF','ESKF'},'Location','nw','FontSize',8);
xlabel('x (m)'); ylabel('y (m)'); title('① 轨迹：直接法与 ESKF 重合（等价性实证）'); grid on; axis equal;
subplot(222);
plot(t, errE, 'r-', 'LineWidth',1.2); hold on;
plot(t, errN, 'g--', 'LineWidth',1.2);
legend({'直接法 EKF','ESKF'},'Location','ne','FontSize',8);
xlabel('t (s)'); ylabel('位置误差 (m)'); title('② 位置误差：两曲线几乎重合'); grid on;
subplot(223);
plot(t, psiE*180/pi, 'r-', 'LineWidth',1.2); hold on;
plot(t, psiN*180/pi, 'g--', 'LineWidth',1.2);
plot([0 T],[0 0],'k--','LineWidth',0.8);
legend({'直接法 EKF','ESKF'},'Location','ne','FontSize',8);
xlabel('t (s)'); ylabel('航向误差 (°)'); title('③ 航向误差：30° 初始误差都被拉回'); grid on;
subplot(224);
b = bar([sqrt(mean(errE.^2)), sqrt(mean(errN.^2))]);
b.FaceColor = 'flat'; b.CData = [0.85 0.33 0.10; 0.20 0.63 0.36];
set(gca,'XTickLabel',{'直接法 EKF','ESKF'}); ylabel('位置 RMSE (m)');
title(sprintf('④ RMSE：等价（差 %.0e）', equiv)); grid on;
saveas(gcf, 'ekf_vs_eskf.png');
dlmwrite('ekf_vs_eskf_res.csv', [t, xt, yt, zx, zy, xEh, xNh], 'precision', 12);
disp('DONE');
