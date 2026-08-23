function miniinsplot(avp, arg2, ttl)
% 迷你 insplot（自写零依赖；布局对齐 PSINS insplot(avp,'avp')，不调用 glv/myfigure/xygo/pos2dxyz）
%  单轨迹模式: miniinsplot(avp, ttl)            -> 生成 miniinsplot_<ttl>.png
%    avp: [att3, vn3, pos3, t]（NED，att=[pitch;roll;yaw]）; ttl: 文件名后缀字符串
%  对比模式:   miniinsplot(dr, truth, ttl)      -> 生成 miniinsplot_<ttl>.png
%    dr: 估计轨迹; truth: 真值轨迹; 轨迹子图(3,2,[4,6]) 叠 蓝(估计)+红(真值)+红星(起点)
% 与 gen_dr.py 双轨一致；仅用 MATLAB 内置 plot，无工具箱依赖。
% 轨迹朝向严格对齐 pos2dxyz：East 在横轴(右)、North 在纵轴(上)（标准地图朝向）。
deg = pi/180;  Re = 6378137.0;
cmp = (nargin>=2) && isnumeric(arg2) && ~ischar(arg2);   % 第二参为矩阵 -> 对比模式
if cmp
    truth = arg2;   % 真值轨迹（第三参 ttl 不变）
else
    truth = [];
    ttl   = arg2;   % 单模式：第二参即 ttl
end
t   = avp(:,end);
lat0 = avp(1,7); lon0 = avp(1,8); h0 = avp(1,9);
% 度分秒字符串（dddmmss.ss，对齐 PSINS 图例 DMS 格式）
strdms = @(d) sprintf('%03d%02d%05.2f', floor(abs(d)), floor(rem(abs(d)*60,60)), rem(abs(d)*3600,60));
% 局部坐标（pos2dxyz 对齐：E-N-U；首点为原点）
xE = (avp(:,8)-lon0)*Re*cos(lat0);   % East（右 / x）
yN = (avp(:,7)-lat0)*Re;             % North（上 / y）
zU = avp(:,9)-h0;                    % Up（天向偏移）
dxyz = [xE, yN, zU];
if cmp
    xE_t = (truth(:,8)-lon0)*Re*cos(lat0);   % 真值 East
    yN_t = (truth(:,7)-lat0)*Re;             % 真值 North
end

scrsz = get(0,'ScreenSize');   % 对齐 PSINS myfigure：宽屏，轨迹 [4,6] 才显正方形
figure('Color','w','OuterPosition',[0.02*scrsz(3), 0.05*scrsz(4), 0.9*scrsz(3), 0.85*scrsz(4)]);
% (321) pitch / roll
subplot(3,2,1); plot(t, avp(:,1)/deg, t, avp(:,2)/deg); grid on;
xlabel('t / s'); ylabel('$\theta / (^{\circ})$','Interpreter','latex'); title('Pitch / Roll'); legend('Pitch','Roll','Location','best');
% (322) yaw
subplot(3,2,2); plot(t, avp(:,3)/deg); grid on;
xlabel('t / s'); ylabel('$\psi / (^{\circ})$','Interpreter','latex'); title('Yaw');
% (323) velocity（VE/VN/VU + 地速 VG，对齐 PSINS 'avp' 的 4 线）
VG = sqrt(avp(:,4).^2 + avp(:,5).^2);
subplot(3,2,3); plot(t, [avp(:,4), avp(:,5), avp(:,6), VG]); grid on;
xlabel('t / s'); ylabel('(m/s)'); title('Velocity'); legend('VE','VN','VU','VG','Location','best');
% (3,2,[4,6]) 轨迹（E 右 / N 上，对齐 pos2dxyz + PSINS insplot 轨迹朝向）
subplot(3,2,[4,6]); plot(0, 0, 'rp', 'HandleVisibility','off'); hold on;   % 起点红点，不进入 legend
if cmp
    h1 = plot(xE, yN, 'b-');        % 估计值（蓝）
    h2 = plot(xE_t, yN_t, 'r-');    % 真值（红）
    hold off; grid on; axis tight;
    allx = [xE; xE_t]; ally = [yN; yN_t];
    xlim([min(allx)-0.02*range(allx), max(allx)+0.02*range(allx)]);
    ylim([min(ally)-0.02*range(ally), max(ally)+0.02*range(ally)]);
    xlabel('East / m'); ylabel('North / m'); title('Trajectory (True vs DR)');
    legend([h1, h2], {'DR (est)', 'Truth'}, 'Location','best');
else
    plot(xE, yN); hold off; grid on; axis tight;
    xlim([min(xE)-0.02*range(xE), max(xE)+0.02*range(xE)]);
    ylim([min(yN)-0.02*range(yN), max(yN)+0.02*range(yN)]);
    xlabel('East / m'); ylabel('North / m'); title('Trajectory (E-N up)');
    legend(sprintf('LON0:%s, LAT0:%s (DMS), H0:%.1f (m)', strdms(lon0/deg), strdms(lat0/deg), h0), 'Location','best');
end
% (325) 位置偏移（Dlat/Dlon/DH，对齐 PSINS dxyz(:,[2,1,3])=[North,East,Up]）
subplot(3,2,5); plot(t, dxyz(:,[2,1,3])); grid on;
xlabel('t / s'); ylabel('(m)'); title('Position offset from start'); legend('Dlat','Dlon','DH','Location','best');

% 取消下方注释保存为图片
% saveas(gcf, sprintf('miniinsplot_%s.png', ttl));
% fprintf('    图已保存: miniinsplot_%s.png\n', ttl);

% close(gcf);% 是否显示figure
end
