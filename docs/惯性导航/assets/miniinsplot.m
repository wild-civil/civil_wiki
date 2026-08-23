function miniinsplot(varargin)
% 迷你 insplot（自写零依赖；布局对齐 PSINS insplot(avp,'avp')，不调用 glv/myfigure/xygo/pos2dxyz）
%  单轨迹模式:  miniinsplot(avp, ttl)                 -> 生成 miniinsplot_<ttl>.png
%    avp: [att3, vn3, pos3, t]（NED，att=[pitch;roll;yaw]）; ttl: 文件名后缀字符串
%  对比模式(单解算):  miniinsplot(dr, truth, ttl)     -> 轨迹子图(3,2,[4,6]) 叠 红(估计)+黑(真值)+红星(起点)
%  对比模式(多解算):  miniinsplot({s1,s2,...}, truth, ttl) -> 轨迹子图 叠 黑(真值)+彩色(各解算)
% 约定（统一）：真值永远画黑线（参考基准）；解算按配色循环（free=红、fix=蓝、…）。
% 与 gen_dr.py / gen_sins.py 双轨一致；仅用 MATLAB 内置 plot，无工具箱依赖。
% 轨迹朝向严格对齐 pos2dxyz：East 在横轴(右)、North 在纵轴(上)（标准地图朝向）。
deg = pi/180;  Re = 6378137.0;

% ---------------- 参数解析 ----------------
if nargin==2 && ischar(varargin{2})
    avp = varargin{1};  truth = [];  ttl = varargin{2};  iscmp = false;  sols = {};  labels = {};
elseif nargin>=3 && ischar(varargin{3})
    if iscell(varargin{1})
        sols = varargin{1};
    else
        sols = {varargin{1}};
    end
    truth = varargin{2};  ttl = varargin{3};  iscmp = true;
    avp = sols{1};   % 其它 5 个子图以第一解算为准
    if nargin>=4, labels = varargin{4}; else labels = {}; end
else
    error('miniinsplot: 参数错误（应为 miniinsplot(avp,ttl) 或 miniinsplot({sols},truth,ttl)）');
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

% 解算配色与标签（第一解算=红；free/fix 顺序调用即红/蓝）
solcols = {'r-','b-','g-','m-','c-'};
if isempty(labels)
    switch length(sols)
        case 1,  sollbl = {'DR (est)'};
        case 2,  sollbl = {'free','fix'};
        otherwise, sollbl = arrayfun(@(k) sprintf('sol%d',k), 1:length(sols), 'UniformOutput',false);
    end
else
    sollbl = labels;
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
subplot(3,2,[4,6]); hold on;
plot(0, 0, 'rp', 'HandleVisibility','off');   % 起点红点，不进入 legend
if iscmp
    xE_t = (truth(:,8)-lon0)*Re*cos(lat0);    % 真值 East
    yN_t = (truth(:,7)-lat0)*Re;              % 真值 North
    ht = plot(xE_t, yN_t, 'k-', 'LineWidth', 1.8);   % 真值（黑，参考基准）
    hs = [];
    allx = xE_t; ally = yN_t;
    for k = 1:length(sols)
        s = sols{k};
        xs = (s(:,8)-lon0)*Re*cos(lat0);
        ys = (s(:,7)-lat0)*Re;
        hs(k) = plot(xs, ys, solcols{min(k,length(solcols))});
        allx = [allx; xs]; ally = [ally; ys];
    end
    hold off; grid on; axis tight;
    xlim([min(allx)-0.02*range(allx), max(allx)+0.02*range(allx)]);
    ylim([min(ally)-0.02*range(ally), max(ally)+0.02*range(ally)]);
    xlabel('East / m'); ylabel('North / m'); title('Trajectory (Truth vs solutions)');
    legend([ht, hs], [{'Truth'}, sollbl(1:length(sols))], 'Location','best');
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
