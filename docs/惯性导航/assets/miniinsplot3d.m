function miniinsplot3d(varargin)
% 迷你 3D 轨迹对比（自写零依赖；PSINS 无此图，属自写增强，用于把"垂直差异"立起来）
% 【函数签名 / 参数 / MATLAB 惯用法详解】见 04_拆解PSINS篇/附录_绘图函数与MATLAB惯用法.md
%   单轨迹:  miniinsplot3d(avp, ttl)                  -> Z=高度(相对起点)×ZFAC
%   对比:    miniinsplot3d({s1,s2,...}, truth, ttl)    -> 真值(黑,Z=0 参考面) + 各解算(Z=高度误差×ZFAC)
% 约定（统一）：真值永远画黑线/参考面；解算按配色循环（free=红、fix=蓝、…）。
% 与 gen_sins.py 双轨一致；仅用 MATLAB 内置 plot3，无工具箱依赖。
% 设计：水平通道 Schuler 稳定 -> free/fix 水平投影几乎重合（2D 看不出差别）；
%       Z 轴 = (估计高度 - 真值高度) × ZFAC，把"垂直通道开环发散"放大到肉眼可见。
%       ZFAC 仅为显示放大，单位仍是 m；本环境 matlab -batch 开图会崩，故 saveas 默认注释。
deg = pi/180;  Re = 6378137.0;  ZFAC = 8.0;

% ---------------- 参数解析 ----------------
if nargin==2 && ischar(varargin{2})
    sols = {varargin{1}};  truth = [];  ttl = varargin{2};  iscmp = false;  labels = {};
elseif nargin>=3 && ischar(varargin{3})
    if iscell(varargin{1}), sols = varargin{1}; else sols = {varargin{1}}; end
    truth = varargin{2};  ttl = varargin{3};  iscmp = true;
    if nargin>=4, labels = varargin{4}; else labels = {}; end
else
    error('miniinsplot3d: 参数错误（应为 miniinsplot3d(avp,ttl) 或 miniinsplot3d({sols},truth,ttl)）');
end

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

if iscmp, lon0 = truth(1,8); lat0 = truth(1,7);
else,     lon0 = sols{1}(1,8); lat0 = sols{1}(1,7); end
enu = @(a) deal((a(:,8)-lon0)*Re*cos(lat0), (a(:,7)-lat0)*Re);  % deal(...) 一次返回多个输出（这里同时返回 East、North 两个向量）；匿名函数写在一行里

figure('Color','w'); hold on; grid on; view(3);
if iscmp
    [xt, yt] = enu(truth);
    zt = zeros(size(xt));
    ht = plot3(xt, yt, zt, 'k-', 'LineWidth', 1.8);   % 真值（黑，Z=0 参考平面）
    hs = [];
    for k = 1:length(sols)
        s = sols{k};
        [xs, ys] = enu(s);
        h_truth = interp1(truth(:,10), truth(:,9), s(:,10), 'linear', 'extrap');  % 按时间把真值高度插值到解算的时间轴上（对齐时间戳）
        zs = (s(:,9) - h_truth) * ZFAC;
        hs(k) = plot3(xs, ys, zs, solcols{min(k,length(solcols))});
    end
    hold off;
    xlabel('East / m'); ylabel('North / m'); zlabel(sprintf('Height error x%d / m', ZFAC));
    title(sprintf('3D trajectory (Z = height error, x%d): %s', ZFAC, ttl));
    legend([ht, hs], [{'Truth'}, sollbl(1:length(sols))], 'Location','best');
else
    [x, y] = enu(sols{1});
    z = (sols{1}(:,9) - sols{1}(1,9)) * ZFAC;
    plot3(x, y, z, solcols{1});
    hold off;
    xlabel('East / m'); ylabel('North / m'); zlabel(sprintf('Height (rel. start) x%d / m', ZFAC));
    title(sprintf('3D trajectory (x%d): %s', ZFAC, ttl));
end

% 取消下方注释保存为图片（本环境 matlab -batch 开图会崩）
% saveas(gcf, sprintf('miniinsplot3d_%s.png', ttl));
% fprintf('    图已保存: miniinsplot3d_%s.png\n', ttl);
% close(gcf);
end
