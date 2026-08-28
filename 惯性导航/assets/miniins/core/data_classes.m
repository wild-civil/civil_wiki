function s = data_classes(kind, n)
% data_classes - Mini-INS 数据结构字段定义 + 默认构造函数
%
% 本文件是 wiki「拆解 PSINS 第 0 篇：数据结构速查表」的代码形态——
% 字段名/顺序/单位与第 0 篇表格一一对应（以 PSINS 源码语义为蓝本，零依赖自写）。
%
% 用法：
%   trj = data_classes('trj');         % 空轨迹结构（字段齐全，值待填）
%   ins = data_classes('ins');         % 初始 ins 结构（含默认单位阵/零向量）
%   kf  = data_classes('kf');          % 15 维 kf 结构
%   kf  = data_classes('kf', 22);      % 指定维度（如 22 维 SINS+DR）
%   dr  = data_classes('dr');          % 空 DR 结构
%
% 新手速览：
%   - 惯导代码 90% 的时间在"读写这些结构体的字段"，先把字段名记熟；
%   - 所有状态都是列向量，所有时间序列都是矩阵（每行一拍，最后一列 t）；
%   - 单位约定：角度/角速度 = 弧度(rad)，位置 lat/lon = 弧度、h = 米，速度 = m/s。

if nargin < 1, error('data_classes: 需要指定结构类型 ''trj''/''ins''/''kf''/''dr'''); end

switch lower(kind)
%% ================= trj：数据母版（对标 trjsimu 产出） =================
case 'trj'
    s = struct( ...
        'avp0', zeros(12,1), ...   % [att(3); vn(3); pos(3)] 初始状态（att=弧度, pos lat/lon 弧度 + h 米）
        'avp',  zeros(0,10), ...   % N×10：每拍真值 [att(3) vn(3) pos(3) t]
        'imu',  zeros(0,7),  ...   % N×7 ：每拍 IMU 增量 [wm(3) vm(3) t]（增量！不是速率）
        'od',   zeros(0,2),  ...   % N×2 ：每拍里程增量 [S t]（P3/P4 用）
        'ts',   0.01,         ...  % 采样间隔 (s)，100 Hz
        'len',  0,            ...  % 总拍数
        'wat',  []);              % 航段表（P1 讲过，trjsegment 的产物）

%% ================= ins：解算状态（对标 insinit） =================
case 'ins'
    s = struct( ...
        'qnb', [1;0;0;0], ...      % 4×1 姿态四元数 [w;x;y;z]（体→导航）
        'vn',  [0;0;0],   ...      % 3×1 速度 [vE;vN;vU]（ENU！与固件 NED 不同）
        'pos', [0;0;0],   ...      % 3×1 位置 [lat;lon;h]（lat/lon 弧度，h 米）
        'eb',  [0;0;0],   ...      % 陀螺零偏 (rad/s)
        'db',  [0;0;0],   ...      % 加计零偏 (m/s^2)
        'wib', [0;0;0],   ...      % 陀螺测量角速度（含地球自转）(rad/s)
        'wnb', [0;0;0],   ...      % 体轴相对导航系角速度 (rad/s)
        'eth', [],        ...      % 地球参数结构体（earth.m 产出：RMh/RNh/wnie/wnin/gcc）
        'Kg',  eye(3),    ...      % 陀螺刻度/安装误差阵（单位阵 = 无误差）
        'Ka',  eye(3),    ...      % 加计刻度/安装误差阵
        't',   0);                % 当前时间 (s)

%% ================= kf：卡尔曼状态（对标 kfinit） =================
case 'kf'
    if nargin < 2, n = 15; end
    s = struct( ...
        'Phikk_1', eye(n), ...     % n×n 离散状态转移阵（每步由 kffk 刷新）
        'Ft',      zeros(n), ...   % n×n 连续状态阵（etm 生成）
        'Hk',      [],       ...   % m×n 量测阵
        'Rk',      [],       ...   % m×m 量测噪声协方差
        'Pk',      eye(n),   ...   % n×n 状态协方差（初值来自 avperrset/poserrset）
        'xk',      zeros(n,1), ... % n×1 状态估计（误差状态）
        'Qk',      [],       ...   % 过程噪声
        'Gk',      []);           % 过程噪声驱动阵

%% ================= dr：航位推算状态（对标 drinit） =================
case 'dr'
    s = struct( ...
        'qnb', [1;0;0;0], ...      % 4×1 姿态四元数（P4 里直接抄 ins.qnb）
        'pos', [0;0;0],   ...      % 3×1 位置 [lat;lon;h]
        'vn',  [0;0;0],   ...      % 3×1 速度（DR 由里程 dS 推速度）
        'Kg',  1.0,       ...      % 里程计刻度系数（≈1）
        'att', [0;0]);            % 2×1 安装角 [俯仰; 航向] (rad)（P4 的 dinst）

otherwise
    error('data_classes: 未知类型 %s（可选 ''trj''/''ins''/''kf''/''dr''）', kind);
end
end
