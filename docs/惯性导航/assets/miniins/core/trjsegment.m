function seg = trjsegment(seg, segtype, lasting, varargin)
% trjsegment - 航段语言：往 seg.wat 表追加一行（Mini-INS 轨迹生成 M2）
%
% 对标 PSINS `base/base1/trjsegment.m`，本库教学简化版：只做 8 种基本航段，
% 复合航段（协调转弯/爬升等）可自行用基本段拼（P1 讲过 wat 表是"可编程"的）。
%
% 用法（链式调用，每行加一段）：
%   seg = trjsegment(seg, 'init', 0, 10);        % 初始化：初速 10 m/s
%   seg = trjsegment(seg, 'accelerate', 5, 2);   % 直线加速 5 s，a=2 m/s²
%   seg = trjsegment(seg, 'uniform', 100);       % 匀速 100 s
%   seg = trjsegment(seg, 'turnleft', 30, 2);    % 左转 30 s，w=2 °/s（协调）
%   seg = trjsegment(seg, 'headup', 10, 3);      % 抬头 10 s，w=3 °/s
%
% wat 表每行（8 列）：
%   [lasting, vel, wx, wy, wz, ax, ay, az]
%    lasting 时长(s) | vel 段初速(m/s) | w 角速度(rad/s) | a 加速度(m/s²)
%   （角速度/加速度定义在"轨迹系"：wz=航向、wy=俯仰、wx=横滚；ax=前进方向）
%
% ─── 新手备注 ───────────────────────────────────────────────────────
%   · trjsimu 只认 wat 表，不认"语义"——每种航段 = 往表里塞一行（或改一行）；
%   · seg.vel 是"内部游标"：加速/减速会更新它，供下一段计算向心加速度 cf=w·v；
%   · 协调转弯（turnleft/right）：要保持速度大小不变，横向必须有向心加速度
%     cf = w·vel（P1 第四节），所以 turnleft 写 a_y=−cf、turnright 写 a_y=+cf。

% ---- 参数解析 ----
if nargin < 2, error('trjsegment: 至少需要 seg 与 segtype'); end

switch lower(segtype)
    case 'init'
        % 初始化（可带初速）
        vel0 = 0; if nargin >= 3 && ~isempty(lasting), vel0 = lasting; end
        seg = struct('wat', [], 'vel', vel0);
        return;
end
if isempty(seg.wat), seg.wat = zeros(0,8); end

switch lower(segtype)
    case 'uniform'          % 匀速直线：w=0, a=0，速度大小不变
        seg.wat(end+1,:) = [lasting, seg.vel, 0,0,0, 0,0,0];

    case 'accelerate'       % 直线加速：a 沿前进方向（+x）
        a = varargin{1};
        seg.wat(end+1,:) = [lasting, seg.vel, 0,0,0, a,0,0];
        seg.vel = seg.vel + a*lasting;          % 更新游标（末速 = 初速 + a·t）

    case 'deaccelerate'     % 直线减速：a 反向（传正值，内部取负）
        a = varargin{1};
        seg.wat(end+1,:) = [lasting, seg.vel, 0,0,0, -a,0,0];
        seg.vel = seg.vel - a*lasting;

    case 'headup'           % 抬头：ω 绕轨迹系 y 轴 +w（俯仰速率）
        w = varargin{1}*pi/180;                 % °/s → rad/s
        seg.wat(end+1,:) = [lasting, seg.vel, 0,w,0, 0,0,0];

    case 'headdown'         % 低头：ω 绕 y 轴 −w
        w = varargin{1}*pi/180;
        seg.wat(end+1,:) = [lasting, seg.vel, 0,-w,0, 0,0,0];

    case 'turnleft'         % 左转：ω 绕 z 轴 +w，向心加速度 a_y=−cf（cf=w·v）
        w = varargin{1}*pi/180;
        cf = w*seg.vel;                          % 向心加速度 = ω·v（P1 第四节）
        seg.wat(end+1,:) = [lasting, seg.vel, 0,0,w, 0,-cf,0];

    case 'turnright'        % 右转：ω 绕 z 轴 −w，a_y=+cf
        w = varargin{1}*pi/180;
        cf = w*seg.vel;
        seg.wat(end+1,:) = [lasting, seg.vel, 0,0,-w, 0,cf,0];

    case 'rollleft'         % 左滚转：ω 绕 x 轴 +w（只滚转不转向）
        w = varargin{1}*pi/180;
        seg.wat(end+1,:) = [lasting, seg.vel, w,0,0, 0,0,0];

    case 'rollright'        % 右滚转：ω 绕 x 轴 −w
        w = varargin{1}*pi/180;
        seg.wat(end+1,:) = [lasting, seg.vel, -w,0,0, 0,0,0];

    otherwise
        error('trjsegment: 未知航段类型 %s（init/uniform/accelerate/deaccelerate/headup/headdown/turnleft/turnright/rollleft/rollright）', segtype);
end
end
