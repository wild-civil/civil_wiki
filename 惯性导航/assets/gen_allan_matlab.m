% gen_allan_matlab.m — PSINS 轨：Allan 方差演示（合成已知参数 → 计算 → 出图）
% 用法: matlab -batch "run('gen_allan_matlab.m')"
% 依赖: PSINS 工具箱（glvs / avarsimu / avar），输出单位 deg/h
% 输出: allan_curve_matlab.png（曲线图）+ allan_matlab.csv（tau,sigma 数据，供 Python 轨对照）
% 对应 wiki: 惯性导航/05_Allan方差.md

addpath('D:/WorkSpace/Code/MATLAB/psins260705/base');
glvs;

%% 1) 合成已知参数的陀螺数据（单位 deg/h）
ts  = 0.01;                 % 采样间隔 100Hz
len = 300000;               % 3000 s
rng(42);                    % 固定随机种子，保证可复现
% NRKQ = [N, R, K, Q]: ARW(°/√h), rate ramp(°/h²), RRW(°/h^1.5), 量化(arcsec)
y = avarsimu([0.01, 0.05, 0.01, 0.5], [], ts, len, 0);   % y in deg/h

%% 2) Allan 偏差
[sigma, tau] = avar(y, ts, 0);       % sigma in deg/h
dlmwrite('allan_matlab.csv', [tau, sigma], 'precision', '%.8e');
dlmwrite('allan_y.csv', y, 'precision', '%.8e');   % 原始合成数据（deg/h）供 Python 轨同一数据对照

%% 3) 出图（log-log + 斜率段标注）
fig = figure('Visible','off','Position',[100 100 860 520]);
loglog(tau, sigma, 'b-', 'LineWidth', 2); hold on; grid on;
xlabel('\tau / s');  ylabel('\sigma_A(\tau) / (deg/h)');
title('Allan 偏差曲线（PSINS avar，合成数据: ARW=0.01°/√h + RRW + rate ramp + 量化）');

% ARW 段参考线: sigma = N/sqrt(tau)，N=0.01°/√h
N_arw = 0.01/60;         taua = tau(tau<6);   loglog(taua, N_arw./sqrt(taua), 'g--', 'LineWidth',1.2);
% BI 段: 平台值（曲线最小处）
bi = min(sigma);         tau_bi = tau(sigma==bi); loglog([tau_bi*0.3, tau_bi*3], [bi bi], 'm-.', 'LineWidth',1.2);
% RRW 段参考线: sigma = K*sqrt(tau/3)，K=0.01 °/h^1.5
K_rrw = 0.01/(3600^1.5); taur = tau(tau>60 & tau<2000); loglog(taur, K_rrw*sqrt(taur/3), 'r--', 'LineWidth',1.2);

% 斜率标注
text(0.05, max(sigma)*0.85, 'QN \it{slope -1}', 'FontSize',9, 'Color',[0.3 0.3 0.3]);
text(0.8,  N_arw/sqrt(0.8)*1.4, 'ARW \it{-1/2}', 'FontSize',9, 'Color',[0 0.5 0]);
text(tau_bi*1.8, bi*1.8, 'BI \it{0 (平台)}', 'FontSize',9, 'Color',[0.8 0 0.8]);
text(300,  K_rrw*sqrt(300/3)*1.6, 'RRW \it{+1/2}', 'FontSize',9, 'Color',[0.8 0.2 0]);
text(1500, 1.5*sigma(end), 'RR \it{+1}', 'FontSize',9, 'Color',[0.5 0.3 0]);
legend('PSINS avar', 'ARW 参考线', 'BI 平台', 'RRW 参考线', 'Location','southeast');

saveas(fig, 'allan_curve_matlab.png');
fprintf('saved allan_curve_matlab.png + allan_matlab.csv + allan_y.csv (N=%d pts)\n', len);
