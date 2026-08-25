function dr = drupdate(dr, wm, dS)
% drupdate - 航位推算更新（Mini-INS DR 模块 M4 版，对齐 P4 mini_drupdate）
%
% ⚠️ M4 重写为 P4 结构（M3 简化版已废弃）。核心差异：
%  ① 里程沿体 **y** 轴投影（dr.prj = Cbo·[0;1;0]，x 右 y 前 z 上约定）；
%  ② 用**半程姿态** qnb12 = qnb ⊗ rv2q(φm/2) 投影（比终点姿态更准）；
%  ③ φm 含**圆锥补偿** ½·wm1×wm2（wm 为 2×3 双子样）；
%  ④ 安装横滚误差 aos 做"陀螺方位误差"旋转修正；
%  ⑤ qnb 更新含 wnin 补偿（dr.Cnb'·wnin·nts，与 SINS 姿态更新同源）。
%
% ─── 输入 ─────────────────────────────────────────────────────────
%   dr  DR 结构（drinit 初始化，P4 字段）
%   wm  2×3 双子样角增量（rad，两拍）
%   dS  标量：本双子样里程增量（m，两拍和）；或向量（走 Cbo·dS 分支）
%   dr  = 更新后的 DR 结构
%
% ─── 更新数学（P4 mini_drupdate 逐行）─────────────────────────────
%   ① φm = Σwm + ½·wm1×wm2                （圆锥补偿，公式 6.1'）
%   ② qnb12 = qnb ⊗ rv2q(φm/2)            （半程姿态）
%   ③ dSn = qnb12 ⊗ (prj·dS)              （里程 → 导航系位移，公式 6.2'）
%   ④ dSn = rotv([0;0;−aos·φz/nts], dSn)  （安装横滚修正）
%   ⑤ vn = dSn/nts；pos += Mpv·dSn         （位置更新，公式 6.3）
%   ⑥ qnb = qnb ⊗ rv2q(φm − Cnb'·wnin·nts)（姿态：体轴增量 + 导航系补偿）
%
% ─── 新手备注 ───────────────────────────────────────────────────────
%   · 本质仍是"航向×里程"：距离来自里程计 dS，方向来自姿态 qnb；
%   · 与 SINS 差异（P3）：SINS 积分加速度（二阶），DR 积分里程（一阶）；
%   · **P4 组合时**：主循环先 dr.qnb = ins.qnb（锚定）再调本函数，
%     ⑥ 的 φm 项使 DR 姿态与 SINS 保持同步（一阶一致）。

nts = dr.ts * size(wm,1);                 % 双子样总时长（= 2·ts）
wmm = sum(wm, 1)';                        % Σwm（两拍角增量和）
dphim = cross(0.5*wm(1,:), wm(2,:))';     % 圆锥项 ½·wm1×wm2（公式 6.1'）
phim = wmm + dphim;

% ② 半程姿态（比终点姿态投影更准）
qnb12 = qmul(dr.qnb, rv2q(phim/2));

% ③ 里程 → 导航系位移（体 y 投影，公式 6.2'）
if numel(dS) > 1
    dSn = qmulv(qnb12, dr.Cbo * dS);      % 向量里程（教学保留 Cbo 分支）
else
    dSn = qmulv(qnb12, dr.prj * dS);      % 标量里程（主用路径）
end

% ④ 安装横滚误差修正（P4 mini_drupdate 特有）
dSn = rotv([0; 0; -dr.aos*phim(3)/nts], dSn);

% ⑤ 速度 / 位置更新（公式 6.3）
dr.vn = dSn / nts;
eth = earth(dr.pos, dr.vn);
dr.Mpv = [0, 1/eth.RMh, 0;  1/eth.clRNh, 0, 0;  0, 0, 1];
dr.pos = dr.pos + dr.Mpv * dSn;

% ⑥ 姿态更新：体轴增量 + 导航系旋转补偿（dr.Cnb' 是旧拍，PSINS 同款）
dr.qnb = qmul(dr.qnb, rv2q(phim - dr.Cnb' * eth.wnin * nts));
dr.qnb = dr.qnb / norm(dr.qnb);           % 归一化
dr.att = q2att(dr.qnb);
dr.Cnb = q2cnb(dr.qnb);
dr.avp = [dr.att; dr.vn; dr.pos];
dr.distance = dr.distance + dr.kod * abs(dS);   % 累计里程（含刻度）
end
