function gen_fdi()
% 多传感器冗余 + FDI 演示（纯 MATLAB，与 gen_fdi.py 双轨）
% =====================================================
% 三个演示，对应 15 篇三个核心论断：
%   1) 一路 IMU 故障时：单路 / 均值 / 中值 的误差对比
%      -> 中值天然剔除离群（无故障时略逊均值，有故障时完胜）
%   2) 2oo3 表决：三路两两残差矩阵，故障路被"少数服从多数"隔离
%   3) NIS 门限捕获缓变漂移：慢漂移让 NIS 单调上升，越过 χ² 门限触发告警
%      （14 篇的 NIS 从"体检"升级为"在线故障检测"）
% 确定性演示（无随机），两轨逐数字一致。运行：gen_fdi

fprintf('%s\n', repmat('=', 1, 70));
fprintf('多传感器冗余 + FDI：中值表决 / 2oo3 / NIS 漂移检测（纯 numpy / 纯 MATLAB 双轨）\n');
fprintf('%s\n', repmat('=', 1, 70));

% ---------- 1) 单路 / 均值 / 中值 对比 ----------
fprintf('\n[1] 一路故障时怎么融合？（真实角速度 w_true = 100.0 °/s，无噪声确定性）\n');
w_true = 100.0;
w = [100.0, 120.0, 100.1];                    % 路 2 = 故障（+20% 刻度误差）
err_single = abs(w(2) - w_true);              % 单路：拿故障路
err_mean   = abs(mean(w) - w_true);           % 均值：被故障路拉偏
err_med    = abs(median(w) - w_true);         % 中值：取排序中间值 100.1
fprintf('   三路读数: [%.1f %.1f %.1f]  (路2 故障: +20%%)\n', w(1), w(2), w(3));
fprintf('   单路(选路2): 误差 %5.1f °/s  ->  ✗ 最差\n', err_single);
fprintf('   均值:        %6.2f °/s, 误差 %5.1f °/s  ->  ✗ 被污染 (6.7%%)\n', mean(w), err_mean);
fprintf('   中值:        %6.2f °/s, 误差 %5.1f °/s  ->  ✓ 最稳 (0.1%%)\n', median(w), err_med);
fprintf('   -> 一路故障下：中值 ≈ 正常值，均值被拉偏，单路可能全错。\n');

% ---------- 2) 2oo3 表决（残差矩阵） ----------
fprintf('\n[2] 2oo3 表决：三路两两残差，多数票隔离故障路\n');
eps_th = 0.5;                                  % 残差门限：|wi - wj| > eps 记为不一致
D = abs(w' - w);                               % 3x3 两两差矩阵
vote = D > eps_th;
fprintf('   两两残差矩阵 (°/s):\n');
disp(D);
fprintf('   不一致矩阵 (> %.1f °/s):\n', eps_th);
disp(double(vote));
for i = 1:3
    bad = sum(vote(i, :));                     % 路 i 与其他几路不一致的票数
    if bad >= 2,     tag = '故障 ✗ 隔离';
    elseif bad == 0, tag = '正常 ✓';
    else,            tag = '可疑 ?';
    end
    fprintf('   路%d: 不一致票数 = %d  ->  %s\n', i, bad, tag);
end
fprintf('   -> 故障路与其余两路都冲突（2 票），被表决隔离；正常两路互相一致。\n');

% ---------- 3) NIS 门限捕获缓变漂移 ----------
fprintf('\n[3] NIS 门限捕获缓变漂移（m=1 量测：漂移 b(t)=0.02·t °/s, σ=1 °/s）\n');
b_rate = 0.02;  sigma = 1.0;
gate = 3.841;                                  % χ²(1) 的 95% 分位（14 篇门限表）
k_trigger = ceil(sqrt(gate) / b_rate);         % NIS = (b·t)²/σ² = gate 的解（向上取整）
fprintf('   NIS(t) = (0.02·t)²/1²，门限 χ²(1,95%%) = %.3f\n', gate);
for k = [50, k_trigger, 100]
    nis = (b_rate * k)^2 / sigma^2;
    if nis > gate, flag = '已触发'; else, flag = '未触发'; end
    fprintf('   t = %3d 步: NIS = %6.2f  %s\n', k, nis, flag);
end
fprintf('   -> 在第 %d 步跨过门限（持续漂移 vs 偶发尖峰：看 NIS 是否单调上升）\n', k_trigger);
fprintf('   （步数按整数步计算，两轨一致；实机用滑动窗口 + 健康标志，避免单步误报）\n');

fprintf('\n[小结]\n');
fprintf('   硬故障(卡死/断线) -> 方差≈0 / 通信错误位(SM_ERR_*) 即检。\n');
fprintf('   软故障(偏差/漂移) -> 中值表决(3 路) + 2oo3 表决 + NIS 门限(在线)。\n');
fprintf('   中值抗 1 路故障、均值不抗；2oo3 抗任意 1 路、怕 2 路同源共因。\n');

end
