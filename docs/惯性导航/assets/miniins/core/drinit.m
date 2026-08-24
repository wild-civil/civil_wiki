function dr = drinit(avp0, att_inst, Kg, ts)
% drinit - 航位推算初始化（Mini-INS DR 模块 M3）
%
% 对标 PSINS `base/base1/drinit.m`，本库教学简化版。
%
% ─── 输入 ─────────────────────────────────────────────────────────
%   avp0       = [att0(3); vn0(3); pos0(3)]  初始状态（att 弧度；pos lat/lon 弧度+h 米）
%   att_inst   = [dpitch; dyaw]              里程计安装角误差（体轴 vs 车轴，rad）2×1
%   Kg         = 1                           里程计刻度系数（≈1，1=无刻度误差）
%   ts         = 0.01                        采样间隔（s）
%   dr         = 初始化后的 DR 结构（字段见 data_classes('dr')）
%
% ─── 新手备注 ───────────────────────────────────────────────────────
%   · DR 是"第二条独立定位链"：不靠加速度，靠**航向 × 里程**推位置；
%   · 里程计测的是"车轴前进的距离增量 dS"（体 x 方向），陀螺给航向；
%   · 姿态初始值照抄 avp0（四元数），里程计安装角/刻度误差在这里注入
%     （P3 讲安装角与刻度系数的本质差异：前者歪装、后者刻度不准）；
%   · **P4 里 DR 姿态被硬锚定**（dr.qnb = ins.qnb），本初始化仍保留自推
%     能力，供 P3 单独跑 DR 用。

dr = data_classes('dr');                   % 取 DR 标准结构（字段见 data_classes）
dr.qnb = cnb2q(euler2cnb(avp0(1:3)));      % 初始姿态：欧拉角 → 四元数
dr.pos = avp0(7:9);                        % 初始位置 [lat; lon; h]
dr.vn  = avp0(4:6);                        % 初始速度（DR 用里程推，初值=起点速度）
dr.Kg  = Kg;                               % 里程计刻度系数
dr.att = att_inst;                         % 安装角误差 [俯仰; 航向]
dr.ts  = ts;                               % 采样间隔（drupdate 算速度用）
end
