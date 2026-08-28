function dr = drinit(avp0, inst, kod, ts)
% drinit - 航位推算初始化（Mini-INS DR 模块 M4 版，对齐 P4 mini_drinit）
%
% ⚠️ M4 重写为 P4 结构（M3 简化版已废弃）。新增字段：Cnb/prj/aos/Mpv/
% distance，用于 drupdate 的"体 y 里程投影 + 安装角/刻度误差注入"。
%
% ─── 输入 ─────────────────────────────────────────────────────────
%   avp0 = [att0(3); vn0(3); pos0(3)]  初始状态（att 弧度；pos lat/lon 弧度+h 米）
%          （可 12 维含速度，或 9 维仅 att+pos——内部自动补零）
%   inst = [dpitch; droll; dyaw]（弧度）里程计安装角误差（体轴 vs 车轴）
%   kod  = 里程计刻度系数（1 = 无刻度误差；P4 注入 1+dkod）
%   ts   = 采样间隔（s）
%   dr   = 初始化后的 DR 结构（P4 字段齐全）
%
% ─── ⚠️ PSINS 机体系约定 ──────────────────────────────────────────
%   x 右、y 前、z 上；里程计沿体 **y**（前进方向）。
%   prj = Cbo·[0;1;0]：里程方向在体轴的投影（含安装角误差 + 刻度）。
%
% ─── 新手备注 ───────────────────────────────────────────────────────
%   · DR 是"第二条独立定位链"：不靠加速度，靠**航向 × 里程**推位置；
%   · aos = inst(2)（droll）：安装横滚误差，drupdate 里做"陀螺方位
%     误差旋转"补偿（P4 mini_drupdate 的 rotv([0;0;−aos·φz/nts],·)）；
%   · **P4 组合时** DR 姿态被硬锚定（dr.qnb = ins.qnb），初始化仍保留
%     自推能力，供 DR-only 链（P3/P4 解算 2）使用。

% ---- 兼容 9/12 维 avp0 ----
avp0 = avp0(:);
if length(avp0) < 9
    avp0 = [avp0(1:3); zeros(3,1); avp0(4:6)];
end

% ---- 初始姿态/位置 ----
dr = data_classes('dr');
dr.qnb = a2qua(avp0(1:3));                % att → 四元数（PSINS a2qua）
dr.att = q2att(dr.qnb);                   % 一致性回读
dr.Cnb = q2cnb(dr.qnb);                   % C_n^b（体→导航）
dr.vn  = zeros(3,1);                      % DR 速度由里程推（初值 0）
dr.pos = avp0(7:9);                       % [lat; lon; h]
dr.avp = [dr.att; dr.vn; dr.pos];
dr.kod = kod;                             % 刻度系数（P4 注入 1+dkod）

% ---- 安装角/刻度 → 里程方向投影（P4 mini_drinit 逐行）----
dr.aos = inst(2);                         % 安装横滚误差（drupdate 方位修正用）
inst2 = inst;  inst2(2) = 0;              % Cbo 构造时把 aos 单独剥出
Cbo = euler2cnb(-inst2) * kod;            % 安装角旋转 × 刻度（euler2cnb = a2mat）
dr.Cbo = Cbo;
dr.prj = Cbo * [0; 1; 0];                 % ★ 里程方向 = 体 y 在"车体系"投影

dr.ts = ts;
dr.distance = 0;                          % 累计里程（drupdate 累加）
eth = earth(dr.pos, zeros(3,1));          % 初始位置微分阵
dr.Mpv = [0, 1/eth.RMh, 0;  1/eth.clRNh, 0, 0;  0, 0, 1];
dr.Td = 0;                                % 时延（教学简化 Td=0）
end
