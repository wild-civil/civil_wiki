% gen_sins_error.m — 纯惯导误差传播：简化水平北向通道（锚定牛小骥讲义式 62/68/69）
% 输出：
%   sins_error_compare.png   图1: 各误差源对北向位置误差的贡献分解（60 min）
%   sins_error_timescale.png 图2: 不同陀螺零偏下位置发散对比（0.001/0.01/0.1 deg/h）
%   sins_error_verify.png    图3: 数值积分 vs 解析解对照（验证式 68）
%   sins_error_res.csv       数值数据（供 Python 对照）
clear; clc; close all;

% ---- 常量 ----
g = 9.8;            % m/s^2
R = 6371e3;         % 地球平均半径 m
ws = sqrt(g/R);     % 舒勒角频率 rad/s
Ts = 2*pi/ws;       % 舒勒周期 s
fprintf('舒勒周期 Ts = %.1f min\n', Ts/60);

% 误差源（讲义式 68 参数，p13 示例同款量级）
dr0   = 0;            % 初始位置误差 m
dv0   = 0.1;          % 初始速度误差 m/s
phi0  = 5/60*pi/180;  % 初始俯仰失准角 5'（弧秒级）→ rad
dfN   = 10e-5;        % 北向加计零偏 10 mGal → m/s^2 (1 mGal = 1e-5 m/s^2)
dwE   = 0.01*pi/180/3600;  % 东向陀螺零偏 0.01 deg/h → rad/s

% ---- 解析解（式 68 结构，自推自洽：见 09 篇正文推导）----
% δr(t) = dr0 + dv0*sin(ws t)/ws + g*phi0*(1-cos)/(ws^2)
%       + dfN*(1-cos)/(ws^2) + R*dwE*(sin(ws t)/ws - t)
t = 0:1:3600;  % 60 min
sint = sin(ws*t); cost = cos(ws*t);
r_dr0   = dr0 * ones(size(t));
r_dv0   = dv0 .* sint ./ ws;
r_phi0  = (g*phi0/ws^2) .* (1 - cost);   % = R*phi0*(1-cos)
r_dfN   = (dfN/ws^2) .* (1 - cost);
r_dwE   = R*dwE .* (sint./ws - t);
r_total = r_dr0 + r_dv0 + r_phi0 + r_dfN + r_dwE;

% ---- 图1: 各误差源贡献分解 ----
figure('Position',[100 100 900 560]);
plot(t/60, r_phi0/1000, 'b-', 'LineWidth',1.6); hold on;
plot(t/60, r_dfN/1000, 'g-', 'LineWidth',1.6);
plot(t/60, r_dwE/1000, 'r-', 'LineWidth',1.8);
plot(t/60, r_dv0/1000, 'm--', 'LineWidth',1.2);
plot(t/60, r_total/1000, 'k-', 'LineWidth',2.2);
legend({'初始失准角 5''（舒勒振荡）','加计零偏 10 mGal（有界振荡）', ...
    '陀螺零偏 0.01°/h（线性发散!）','初始速度 0.1 m/s（正弦）','总位置误差'}, ...
    'Location','northwest','FontSize',9);
xlabel('时间 (min)'); ylabel('北向位置误差 (km)');
title(sprintf('纯惯导北向位置误差：各误差源贡献（舒勒周期 T_s≈%.0f min）', Ts/60));
grid on; xlim([0 60]);
saveas(gcf, 'sins_error_compare.png');

% ---- 图2: 不同陀螺零偏下的位置发散（"1 小时漂 1 海里"指标）----
dws = [0.001, 0.01, 0.1] * pi/180/3600;   % deg/h → rad/s
figure('Position',[100 100 900 560]);
for k = 1:3
    rk = R*dws(k) .* (sint./ws - t);
    plot(t/60, rk/1852, 'LineWidth',1.8); hold on;
end
plot([0 60],[1 1],'k--','LineWidth',1); text(2,1.06,'1 海里/h 指标线','FontSize',9);
legend({'陀螺零偏 0.001°/h (战术级)','陀螺零偏 0.01°/h (导航级)','陀螺零偏 0.1°/h (消费级)'}, ...
    'Location','northwest','FontSize',9);
xlabel('时间 (min)'); ylabel('北向位置误差 (海里)');
title('陀螺零偏主导的线性发散：纯惯导为何必发散');
grid on; xlim([0 60]);
saveas(gcf, 'sins_error_timescale.png');

% ---- 图3: 数值积分 vs 解析解（验证式 68 结构）----
% 状态 x = [dr_N; dv_N; phi_E]; 常值误差 dfN, dwE 作为输入
% d(dr)=dv; d(dv)=g*phi+dfN; d(phi)=-dv/R-dwE
dt = 1; N = length(t);
x = [dr0; dv0; phi0];
xnum = zeros(3, N); xnum(:,1) = x;
for i = 2:N
    dx = [x(2); g*x(3)+dfN; -x(2)/R-dwE];
    x = x + dx*dt;
    xnum(:,i) = x;
end
figure('Position',[100 100 900 560]);
subplot(311); plot(t/60, xnum(1,:)/1000, 'b-', 'LineWidth',1.4); hold on;
plot(t/60, r_total/1000, 'r--', 'LineWidth',1.4);
ylabel('位置 (km)'); legend({'数值积分','解析解'},'FontSize',8);
title('简化北向通道：数值积分 vs 解析解（式 68）'); grid on;
subplot(312); plot(t/60, xnum(2,:), 'b-', 'LineWidth',1.4);
ylabel('速度 (m/s)'); grid on;
subplot(313); plot(t/60, xnum(3,:)*180/pi*3600, 'b-', 'LineWidth',1.4);
ylabel('失准角 (arcsec)'); xlabel('时间 (min)'); grid on;
saveas(gcf, 'sins_error_verify.png');

% ---- 数据导出（供 Python 对照）----
dlmwrite('sins_error_res.csv', [t(:), r_total(:)/1000, r_dwE(:)/1000, xnum(1,:)'/1000, xnum(3,:)'*180/pi*3600], ...
    'precision', 12);
fprintf('max|pos err| 60min = %.2f m\n', max(abs(r_total)));
fprintf('陀螺零偏项 60min   = %.2f m = %.3f 海里\n', max(abs(r_dwE)), max(abs(r_dwE))/1852);
fprintf('数值vs解析 位置差  = %.2e m\n', max(abs(xnum(1,:)-r_total)));
disp('DONE');
