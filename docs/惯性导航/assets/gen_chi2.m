function gen_chi2()
% 一致性检验 NEES/NIS：χ² 门限与错配诊断（纯 MATLAB，与 gen_chi2.py 双轨）
% =====================================================================
% 核心事实：
%   若滤波器声称的协方差 P（及 R）与真实误差统计一致，则
%     NEES = dx' P^{-1} dx  ~  chi2(n_x)     （dx = x_true - x_hat，需真值）
%     NIS  = r'  S^{-1} r   ~  chi2(m)       （r = z - h(x_hat)，S = H P H' + R，在线可算）
%   因此 E[NEES]=n_x、E[NIS]=m：长时间平均偏离 m 就说明 P/R 与真实不符。
%
% 本脚本做三件事：
%   1) χ² 分布性质蒙特卡洛：标准正态平方和 -> 样本均值≈m、95% 分位≈理论值
%   2) NIS 均值 = 一致性闸门：R/P 声称值对/错配 三场景（解析期望 + MC 确认）
%   3) NEES 批检验（有真值场景）：N 时刻 ΣNEES ~ chi2(N*n_x) 的 95% 区间判定
% 无工具箱依赖（分位数用 sort 手动算），运行：gen_chi2

rng(42);            % 与 Python default_rng(42) 不同 PRNG：统计量一致，逐样本不同

% ---------- 理论 χ² 分位数（对照用）：m=1,2,3 的 95% / 99% 上侧分位数 ----------
chi2_theo_95 = [3.841, 5.991, 7.815];

fprintf('%s\n', repmat('=', 1, 70));
fprintf('一致性检验 NEES/NIS：χ² 门限与错配诊断（纯 numpy / 纯 MATLAB 双轨）\n');
fprintf('%s\n', repmat('=', 1, 70));

% ---------- 1) χ² 分布性质（MC） ----------
fprintf('\n[1] χ² 分布性质（MC: N=200000，标准正态平方和 → 自由度 m）\n');
N_MC = 200000;
for m = 1:3
    samples = sum(randn(N_MC, m).^2, 2);        % 标准正态平方和 ~ chi2(m)
    mean_mc = mean(samples);
    s = sort(samples);
    q95_mc = s(ceil(0.95 * N_MC));              % 手动分位数，避免工具箱依赖
    fprintf('   m=%d: 样本均值=%.3f (理论 %d),  95%% 分位=%.2f (理论 %.3f)\n', ...
            m, mean_mc, m, q95_mc, chi2_theo_95(m));
end
fprintf('   -> 均值=m：若 P 真是误差协方差，NEES/NIS 就服从 χ²(m) —— 这是检验的根基\n');

% ---------- 2) NIS 均值 = 一致性闸门 ----------
fprintf('\n[2] NIS 均值 = 一致性闸门（m=2 位置量测；真实新息协方差 Σ_true = P+R = 41·I₂）\n');
P_true = 16.0;  R_true = 25.0;                  % 真实预测误差 4 m、量测噪声 5 m
Sigma_true = (P_true + R_true) * eye(2);
fprintf('   真实: P_true=%.0f (4m), R_true=%.0f (5m), Σ_true=(%.0f)·I₂\n', ...
        P_true, R_true, P_true + R_true);
scen = { '一致    (S=41·I₂)',   16.0, 25.0, '✓ 通过 (≈m)';
         '过自信  (S=8·I₂)',     4.0,  4.0, '✗ 偏高 → P/R 被低估';
         '过保守  (S=200·I₂)', 100.0,100.0, '✗ 偏低 → P/R 被高估' };
fprintf('   %-16s%12s%10s   判定\n', '场景', 'E[NIS] 解析', 'MC 均值');
for i = 1:size(scen, 1)
    P_c = scen{i,2};  R_c = scen{i,3};
    S_claim = (P_c + R_c) * eye(2);
    E_nis = trace(inv(S_claim) * Sigma_true);   % E[r' S^-1 r] = tr(S^-1 Σ_true)
    r = sqrt(P_true + R_true) * randn(2, N_MC); % r ~ N(0, Σ_true)
    nis = sum(r .* (inv(S_claim) * r), 1);      % 逐样本 NIS
    fprintf('   %-16s%10.2f%10.2f   %s\n', scen{i,1}, E_nis, mean(nis), scen{i,4});
end

% ---------- 3) NEES 批检验（有真值场景） ----------
fprintf('\n[3] NEES 批检验（有真值才可算：N=50 时刻, 状态维 d=2）\n');
N = 50;  d = 2;
lo = 74.22;  hi = 129.56;                       % chi2(100) 的 2.5%/97.5% 分位（理论）
fprintf('   ΣNEES ~ χ²(N·d) = χ²(100)，95%% 区间 [%.2f, %.2f]\n', lo, hi);
fprintf('   一致滤波器:  E[ΣNEES] = N·d = %d ∈ [%.2f, %.2f] → ✓ 通过\n', N*d, lo, hi);
ratio = 4.0;                                    % 过自信：声称 P = P_true/4
fprintf('   过自信(P/4): E[ΣNEES] = %d >> %.2f → ✗ 拒绝（声称 P 太小，误差被高估 4 倍）\n', ...
        N*d*ratio, hi);
fprintf('   -> 实机没有真值用 NIS；仿真/SIL 有真值才用 NEES（本项目 matlab_sim 即此场景）\n');

fprintf('\n[小结]\n');
fprintf('   一致性 = 声称的 P/R 与真实误差统计相符；NIS 均值 ≈ m 即通过。\n');
fprintf('   NIS 偏高 → 过自信（P/R 被低估）；NIS 偏低 → 过保守（P/R 被高估）。\n');
fprintf('   单次 NIS 波动大，须时间平均 / 批检验 / χ² 门限（gating 即单次门限的工程化）。\n');

end
