function od = odsimu(trj, inst, kod)
% odsimu - 里程计增量仿真（Mini-INS 轨迹生成 M4）
%
% 对标 P4 `assets/gen_sins_dr.py` 的 mini_odsimu（教学简化：无噪声、无时延 Td=0）。
% 从真值位置序列差分出"每拍位移大小"，除以刻度 kod 得里程计原始读数。
%
% ─── 输入/输出 ─────────────────────────────────────────────────────
%   trj  = trjsimu 输出的轨迹结构（用 trj.avp 的 pos 列）
%   inst = 安装角（本函数只用位置差分，inst 保留签名对齐；内部未用）
%   kod  = 里程计真实刻度系数（1 = 无刻度误差；DR 侧用 1+dkod 注入误差）
%   od   = N×2：[dS; t]——dS 为每拍里程增量（除以 kod 后），t 为该拍时间
%
% ─── 数学（公式 7.1）───────────────────────────────────────────────
%   dS = |Δp_xyz|：每拍位置增量（经纬高差 → 米）的模长。
%   Δp_xyz = [RMh·Δlat; clRNh·Δlon; Δh]   （RMh/clRNh 取段起点，PSINS 简化）
%   od(:,1) = diff( cumsum(dS)/kod )       （刻度体现在读数上）
%
% ─── 新手备注 ───────────────────────────────────────────────────────
%   · 里程计只给"距离大小"，方向由 DR 的姿态（航向）决定——这就是
%     "航向×里程"的输入分离（P3）；
%   · DR 消费端（drupdate）：dS 沿体 y（前向）投影 = prj·dS；
%   · 刻度误差注入在 DR 侧：drinit(avp0, dinst, 1+dkod)，本函数保持
%     kod=1 出"真值里程"，尺度误差全部由 DR 的 kod 吸收（P4 22 维
%     dKod 自标定辨识的就是它）。

pos0 = trj.avp(1, 7:9)';                  % 起点位置（P4: pos0 = trj[0,6:9]）
pos = [pos0, trj.avp(:,7:9)'];            % n+1 个位置点（起点 + 全程每拍）
n = size(pos, 2);
RMh = zeros(n-1, 1);  clRNh = zeros(n-1, 1);
for k = 1:n-1
    eth = earth(pos(:,k), zeros(3,1));    % 每拍起点地球参数（PSINS 简化）
    RMh(k) = eth.RMh;  clRNh(k) = eth.clRNh;
end
dpos = diff(pos, 1, 2)';                  % 每拍 [Δlat Δlon Δh]（n-1×3）
dxyz = [RMh.*dpos(:,1), clRNh.*dpos(:,2), dpos(:,3)];   % 转米
dS = sqrt(sum(dxyz.^2, 2));               % 每拍位移大小
dSc = [0; cumsum(dS)];                    % 累计里程
od = [diff(dSc/kod), trj.avp(:, 10)];     % 刻度体现在读数；t 对齐真值拍（od 每行 = trj 每拍）
end
