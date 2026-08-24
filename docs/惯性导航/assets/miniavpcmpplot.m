function miniavpcmpplot(trj, avps, names, fname)
% 迷你 avpcmpplot（自写零依赖；布局对齐 PSINS avpcmpplot(avp0,varargin) 'avp' 6 面板）
% 【函数签名 / 参数 / MATLAB 惯用法详解】见 04_拆解PSINS篇/附录_绘图函数与MATLAB惯用法.md
%   trj : 真值 avp（100 Hz，[att3,vn3,pos3,t]）
%   avps: cell of 解算 avp（双子样 50 Hz，与 trj 对齐）
%   names: cell of 字符串（图例，每个解算一个）
% 布局（对齐 PSINS）：
%   (321) 姿态：真值(黑实线) + 各解算(彩色虚线) 叠加
%   (322) 姿态误差（arcsec）
%   (323) 速度：真值 + 各解算 叠加
%   (324) 速度误差（m/s）
%   (325) 位置偏移：真值 + 各解算 叠加（Dlat/Dlon/DH）
%   (326) 位置误差（m，dN/dE/dH）
% 每个解算固定分配：颜色 + 线型（free=蓝虚线, fix=红点划线, ...），保证可区分。
% 零依赖，不调用 glv/avpcmp。
deg = pi/180;  Re = 6378137.0;  dph = deg/3600;
lat0 = trj(1,7);
trj_d = trj(2:2:end,:);                 % 双子样对齐（50 Hz）
n = length(avps);
sol_color = {'b','r','g','m','c'};     % 各解算颜色（free=蓝, fix=红, ...）
sol_style = {'--','-.',':','-'};        % 各解算线型
att_rms = zeros(n,1); vel_rms = zeros(n,1); pos_rms = zeros(n,1);

scrsz = get(0,'ScreenSize');   % 对齐 PSINS myfigure：宽屏
figure('Color','w','OuterPosition',[0.02*scrsz(3), 0.05*scrsz(4), 0.9*scrsz(3), 0.85*scrsz(4)]);
% ===== (321) 姿态：真值实线 + 各解算虚线 =====
subplot(3,2,1); hold on; grid on;
plot(trj_d(:,end), trj_d(:,1:3)/deg, 'k-', 'LineWidth', 1.4);
for k=1:n
    m = min(size(avps{k},1), size(trj_d,1));
    plot(trj_d(1:m,end), avps{k}(1:m,1:3)/deg, 'Color', sol_color{k}, 'LineStyle', sol_style{k}, 'LineWidth', 1.1);
end
xlabel('t / s'); ylabel('(deg)'); title('Attitude'); legend('Pitch Ref.','Roll Ref.','Yaw Ref.','Location','best');

% ===== (322) 姿态误差（arcsec）=====
subplot(3,2,2); hold on; grid on;
for k=1:n
    m = min(size(avps{k},1), size(trj_d,1));
    de = avps{k}(1:m,1:3) - trj_d(1:m,1:3);
    de(:,3) = mod(de(:,3)+pi, 2*pi) - pi;   % 把 yaw 误差归一到 [-pi, pi]，避免跨 ±180° 时画出巨大跳变（如 179°→-179° 应算 2° 而非 358°）
    h = plot(trj_d(1:m,end), de/dph, 'Color', sol_color{k}, 'LineStyle', sol_style{k}, 'LineWidth', 1.1);
    for j=2:3, h(j).Annotation.LegendInformation.IconDisplayStyle = 'off'; end  % 仅首线入图例
    att_rms(k) = sqrt(mean(de(:).^2))/dph;
end
xlabel('t / s'); ylabel('(arcsec)'); title(sprintf('Attitude error   RMS = %.0f arcsec', mean(att_rms)));
legend(names, 'Location','best');

% ===== (323) 速度：真值 + 各解算 =====
subplot(3,2,3); hold on; grid on;
plot(trj_d(:,end), trj_d(:,4:6), 'k-', 'LineWidth', 1.4);
for k=1:n
    m = min(size(avps{k},1), size(trj_d,1));
    plot(trj_d(1:m,end), avps{k}(1:m,4:6), 'Color', sol_color{k}, 'LineStyle', sol_style{k}, 'LineWidth', 1.1);
end
xlabel('t / s'); ylabel('(m/s)'); title('Velocity'); legend('VE Ref.','VN Ref.','VU Ref.','Location','best');

% ===== (324) 速度误差 =====
subplot(3,2,4); hold on; grid on;
for k=1:n
    m = min(size(avps{k},1), size(trj_d,1));
    dv = avps{k}(1:m,4:6) - trj_d(1:m,4:6);
    h = plot(trj_d(1:m,end), dv, 'Color', sol_color{k}, 'LineStyle', sol_style{k}, 'LineWidth', 1.1);
    for j=2:3, h(j).Annotation.LegendInformation.IconDisplayStyle = 'off'; end
    vel_rms(k) = sqrt(mean(dv(:).^2));
end
xlabel('t / s'); ylabel('(m/s)'); title(sprintf('Velocity error   RMS = %.4f m/s', mean(vel_rms)));
legend(names, 'Location','best');

% ===== (325) 位置偏移：真值 + 各解算（Dlat/Dlon/DH，对齐 PSINS）=====
subplot(3,2,5); hold on; grid on;
dlat = (trj_d(:,7)-trj_d(1,7))*Re; dlon = (trj_d(:,8)-trj_d(1,8))*Re*cos(lat0); dh = trj_d(:,9)-trj_d(1,9);
plot(trj_d(:,end), [dlat, dlon, dh], 'k-', 'LineWidth', 1.4);
for k=1:n
    m = min(size(avps{k},1), size(trj_d,1));
    dlatk = (avps{k}(1:m,7)-trj_d(1,7))*Re; dlonk = (avps{k}(1:m,8)-trj_d(1,8))*Re*cos(lat0); dhk = avps{k}(1:m,9)-trj_d(1,9);
    plot(trj_d(1:m,end), [dlatk, dlonk, dhk], 'Color', sol_color{k}, 'LineStyle', sol_style{k}, 'LineWidth', 1.1);
end
xlabel('t / s'); ylabel('(m)'); title('Position offset'); legend('Dlat','Dlon','DH','Location','best');

% ===== (326) 位置误差（dN/dE/dH）=====
subplot(3,2,6); hold on; grid on;
for k=1:n
    m = min(size(avps{k},1), size(trj_d,1));
    dp = avps{k}(1:m,7:9) - trj_d(1:m,7:9);
    dN = dp(:,1)*Re; dE = dp(:,2)*Re*cos(lat0); dH = dp(:,3);
    h = plot(trj_d(1:m,end), [dN, dE, dH], 'Color', sol_color{k}, 'LineStyle', sol_style{k}, 'LineWidth', 1.1);
    for j=2:3, h(j).Annotation.LegendInformation.IconDisplayStyle = 'off'; end % 图形对象技巧：把每条解算的第 2、3 条线从图例藏起来，让"姿态三维曲线"共用一个图例项
    pos_rms(k) = sqrt(mean([dN, dE, dH].^2, 'all'));
end
xlabel('t / s'); ylabel('(m)'); title(sprintf('Position error   RMS = %.1f m', mean(pos_rms)));
legend(names, 'Location','best');

% 可选第 4 参 fname：保存为图片（P4 三解算对比传入；P2/P3 两解算 3 参调用不受影响）
if nargin >= 4 && ~isempty(fname)
    saveas(gcf, fname);
    fprintf('    图已保存: %s\n', fname);
end

% close(gcf);% 是否显示figure
end
