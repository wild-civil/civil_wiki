function kf = kfupdate(kf, z)
% kfupdate - 卡尔曼滤波更新（时间更新 + 量测更新，Mini-INS M4）
%
% 对标 PSINS `base/kf/kfupdate.m`，本库教学版（Joseph 形式保协方差对称）。
%
% ─── 用法 ─────────────────────────────────────────────────────────
%   kf = kfupdate(kf);          % 时间更新（仅预测）：用 Phikk_1 推进 xk/Pk
%   kf = kfupdate(kf, z);       % 量测更新（+ 校正）：用 Hk/Rk/z 修正 xk/Pk
%
% ─── 更新公式 ─────────────────────────────────────────────────────
%   时间更新（公式 7.1）：
%     xk⁻ = Phikk_1·xk⁺            （先验状态 = 状态转移 × 后验状态）
%     Pk⁻ = Phikk_1·Pk⁺·Phikk_1' + Qk（先验协方差 + 过程噪声）
%   量测更新（公式 7.2，Joseph 形式）：
%     K = Pk⁻·Hk'·(Hk·Pk⁻·Hk' + Rk)⁻¹   （卡尔曼增益：信谁）
%     xk⁺ = xk⁻ + K·(z − Hk·xk⁻)        （修正量 ∝ 新息 × 增益）
%     Pk⁺ = (I−KH)·Pk⁻·(I−KH)' + K·Rk·K' （Joseph：数值稳定，保对称）
%
% ─── 新手备注 ───────────────────────────────────────────────────────
%   · **时间更新 = "模型预测"**（什么也没测，只是按状态转移推一步）；
%     **量测更新 = "用观测量纠偏"**（z 进来，按 H 投影后修正）；
%   · Joseph 形式（(I−KH)P(I−KH)'+KRK'）比标准式（(I−KH)P）数值更稳、
%     保证 Pk 对称正定——P4 的迷你实现就用它；
%   · 增益 K 的分母 (H·P·H'+R) 是"预测不确定性"，分子 P·H' 是"状态与
%     量测的相关"——K 大 = 信量测（R 小），K 小 = 信模型（P 小）。

if nargin < 2
    % --- 时间更新（公式 7.1）---
    kf.xk = kf.Phikk_1 * kf.xk;                       % 状态预测
    kf.Pk = kf.Phikk_1 * kf.Pk * kf.Phikk_1' + kf.Qk; % 协方差预测
else
    % --- 量测更新（公式 7.2，Joseph）---
    PHT = kf.Pk * kf.Hk';                             % P·H'（预计算）
    S   = kf.Hk * PHT + kf.Rk;                        % 新息协方差 H·P·H'+R
    K   = PHT / S;                                    % 卡尔曼增益（左除 = 乘逆）
    kf.xk = kf.xk + K * (z - kf.Hk * kf.xk);          % 状态修正（新息 × 增益）
    IKH = eye(size(kf.Pk)) - K * kf.Hk;               % I − K·H
    kf.Pk = IKH * kf.Pk * IKH' + K * kf.Rk * K';      % Joseph 协方差更新
end
end
