function dr = drupdate(dr, wm, dS)
% drupdate - 航位推算更新：航向 × 里程推位置（Mini-INS DR 模块 M3）
%
% 对标 PSINS `base/base1/drupdate.m`，本库教学简化版（零依赖）。
%
% ─── 输入 ─────────────────────────────────────────────────────────
%   dr   DR 结构（drinit 初始化）
%   wm   本拍角增量（体轴，rad）3×1 —— 陀螺测的航向变化
%   dS   本拍里程增量（m）标量 —— 里程计沿车轴（体 x）的前进距离
%   dr   = 更新后的 DR 结构
%
% ─── 更新数学（三步）───────────────────────────────────────────────
%   ① 姿态更新   qnb ← qnb ⊗ rv2q(wm)             （公式 6.1，陀螺推航向）
%   ② 里程转向   dpos_n = Cbn·[dS;0;0]             （公式 6.2，体 x 里程→导航系）
%   ③ 位置更新   dlat=dN/RMh; dlon=dE/(RNh·cosL); dh=dU   （公式 6.3）
%
% ─── 新手备注 ───────────────────────────────────────────────────────
%   · **DR 的本质**：位置增量 = 前进距离 × 前进方向。
%     距离来自里程计（dS），方向来自姿态（qnb）——这就是"航向×里程"；
%   · ② 里 [dS;0;0] 是体 x 轴的里程（车头方向），qmulv 用 Cbn 把它转到
%     导航系得 [dE;dN;dU]，再按 ENU 位置微分公式折算成经纬高增量；
%   · 与 SINS 的本质差异（P3）：SINS 积分"加速度"（二阶），DR 积分
%     "里程"（一阶）——DR 短时稳、长时尺度/角度发散；SINS 长时漂；
%   · **P4 组合时**：每步先 insupdate 再 dr.qnb=ins.qnb（姿态硬锚定，
%     此步的 ① 可省），然后本函数用 dS 推位置——KF 用位置差修正 SINS。
%   · 教学简化：未做安装角修正（dr.att 留给 M4 KF 用）、未做 vn 外推。

% --- ① 姿态更新（公式 6.1）：陀螺角增量右乘 ---
dr.qnb = qmul(dr.qnb, rv2q(wm));           % 体轴增量右乘（先转 wm 再原有姿态）
dr.qnb = dr.qnb / norm(dr.qnb);            % 归一化（防模长漂移）

% --- ② 里程 → 导航系位移（公式 6.2）：体 x 前进 dS 米 ---
dS_k = dr.Kg * dS;                         % 刻度系数修正（Kg≈1；P4 里 dKod 就修这里）
dpos_n = qmulv(dr.qnb, [dS_k; 0; 0]);      % [dE; dN; dU]（米）

% --- ③ 位置更新（公式 6.3）：ENU 位置微分 ---
eth = earth(dr.pos, dr.vn);                % 复用 M1 earth.m（RMh/RNh）
dlat = dpos_n(2) / eth.RMh;                % d(lat) = dN / RMh（子午圈）
dlon = dpos_n(1) / (eth.RNh * cos(dr.pos(1)));  % d(lon) = dE / (RNh·cosL)
dh   = dpos_n(3);                          % d(h)   = dU
dr.pos = dr.pos + [dlat; dlon; dh];        % 位置推进

% --- ④ 速度（供后续 KF/绘图用）：里程速率 × 航向 ---
dr.vn = dpos_n / dr.ts;                    % DR 速度 = 导航系位移 / 采样间隔
end
