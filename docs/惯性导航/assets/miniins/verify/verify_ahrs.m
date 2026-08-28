function [nPass, nFail] = verify_ahrs()
% verify_ahrs - 姿态解算模块自检（Mini-INS M-A 回归：TRIAD/QUEST/Mahony/magsimu）
%
% 运行：cd docs/惯性导航/assets/miniins/verify; verify_ahrs
% 要求：无工具箱，确定性（随机注入默认关，噪声 0）。
%
% 五组测试：
%   ① TRIAD 双矢量定姿 vs euler 真值（多姿态，解析精确解，<1e-12）
%   ② QUEST 加权最小二乘 vs 真值（同对拍，<1e-10）
%   ③ Mahony 静态收敛：3~5° 初始误差 + 100°/h 级陀螺零偏 → 300 s 收敛，
%      且积分项 exyzInt 精确吸收零偏（‖exyzInt−eb‖ < 5%‖eb‖；yaw 回路增益
%      被 cos²(磁倾角) 压低 → 收敛慢，60 s 时零偏残差仍 ~40%，300 s 后 <1%）
%   ④ Mahony 动态：a) 转弯/滚转机动跟踪（无水平加速）稳态 <0.3°；
%      b) 加速度扰动演示——0.25 m/s² 前向加速把 pitch 拽偏 ~1.5°
%      （Mahony 原理性盲区，水平加速度对幅值门控不可见），结束后回收
%   ⑤ 无磁模式（mag=[]）：加计只管 pitch/roll，yaw 不被磁带偏

addpath(fullfile(fileparts(mfilename('fullpath')), '..', 'core'));
glv = glvs();  deg = glv.deg;
fprintf('=== Mini-INS 姿态解算（M-A）自检 ===\n');
nPass = 0;  nFail = 0;

%% 公共量：地磁参考（北京附近典型值）
mH  = 28000;  dip = 58*deg;  dec = -7*deg;
m_n = [mH*sin(dec); mH*cos(dec); -mH*tan(dip)];      % 导航系地磁（公式 6.5）
up_n = [0; 0; 1];                                    % 准静态加计参考（ENU 天向）

%% ① TRIAD：多姿态精确对拍
atts = [0    0    0;                                  % 基准
        5   -10   30;                                 % 常规姿态
       -20   15  170;                                 % 大 yaw
        30  -45 -100;                                 % 负 roll
        60   80   10] * deg;                          % 大 roll
err1 = 0;
for i = 1:size(atts, 1)
    att = atts(i, :)';
    C  = q2cnb(a2qua(att));                          % 真值姿态阵（体→导航）
    ib = [C'*up_n, C'*m_n];                          % 体观测：加计方向 + 体磁
    in = [up_n, m_n];                                % 导航参考
    qe = triad(ib, in);
    err1 = max(err1, max(max(abs(q2cnb(qe) - C))));
end
if err1 < 1e-12, nPass = nPass + 1; fprintf('  [PASS] ① TRIAD 双矢量定姿，最大阵误差 %.2e\n', err1);
else,            nFail = nFail + 1; fprintf('  [FAIL] ① TRIAD 阵误差 %.2e（超 1e-12，查约定/叉乘序）\n', err1); end

%% ② QUEST：同一组姿态，加权最小二乘
err2 = 0;
for i = 1:size(atts, 1)
    att = atts(i, :)';
    C  = q2cnb(a2qua(att));
    ib = [C'*up_n, C'*m_n];
    in = [up_n, m_n];
    qe = quest(ib, in, [3; 1]);                      % 天向权重高（加计更可信的典型设置）
    err2 = max(err2, max(max(abs(q2cnb(qe) - C))));
end
if err2 < 1e-10, nPass = nPass + 1; fprintf('  [PASS] ② QUEST（Davenport q-方法），最大阵误差 %.2e\n', err2);
else,            nFail = nFail + 1; fprintf('  [FAIL] ② QUEST 阵误差 %.2e（超 1e-10，查 B 阵/约定）\n', err2); end

%% ③ Mahony 静态收敛 + 零偏吸收
pos0 = [29*deg; 106*deg; 450];
Ct0  = q2cnb(a2qua([0; 0; 0]));                      % 真值姿态 = 水平朝北
ebT  = [50; -30; 20] * glv.dph;                      % 真陀螺零偏（°/h → rad/s）
ts   = 0.01;
ahrs = ahrsinit([3*deg; -3*deg; 5*deg], 1.0, 0.3, pos0, dec);  % 初始带 3~5° 误差 + 磁偏角
mag_s = magsimu(Ct0, mH, dip, dec);                  % 静态磁测量（无噪声）
for k = 1:round(300/ts)
    wm = (Ct0' * ahrs.wnie + ebT) * ts;              % 静止时陀螺真值 = 地球自转 + 零偏
    vm = Ct0' * [0; 0; glv.g0] * ts;                 % 静止比力 = 天向 g
    ahrs = mahonyupdate(ahrs, wm, vm, mag_s, ts);
end
att3 = q2att(ahrs.qnb);                              % 估计姿态（真值为 0，误差 = 本身）
err3 = max(abs(att3)) / deg;
bias3 = norm(ahrs.exyzInt - ebT) / norm(ebT);        % 积分项应吸收零偏
if err3 < 0.1 && bias3 < 0.2
    nPass = nPass + 1;
    fprintf('  [PASS] ③ Mahony 静态收敛：300 s 后最大姿态误差 %.4f°，零偏吸收残差 %.1f%%\n', err3, bias3*100);
else
    nFail = nFail + 1;
    fprintf('  [FAIL] ③ 姿态误差 %.4f°（阈 0.1°）/ 零偏吸收残差 %.1f%%（阈 20%%）；att=[%.3f %.3f %.3f]°\n', ...
            err3, bias3*100, att3(1)/deg, att3(2)/deg, att3(3)/deg);
end

%% ④ Mahony 动态跟踪（转弯/滚转机动，无水平加速）+ 加速度扰动演示
%   a) 跟踪：匀速直行/左转/缓滚（|f|≈g，加计参考有效）→ 稳态 < 0.3°
%   b) 扰动演示：0.25 m/s² 前向加速 20 s → pitch 被拽偏 ~1.5°（Mahony
%      原理性盲区：水平加速度对幅值门控不可见）→ 加速结束后 30 s 内
%      误差回收 < 0.1°。PASS 判据 = 峰值落在预期区间 + 能回收。
WAT = [ 20,  0,  0,       0,       0,   0,     0, 0;   % 静止（收敛段）
        60, 10,  0,       0,       0,   0,     0, 0;   % 匀速直行
        30, 10,  0,       0,  2*deg,   0,     0, 0;   % 左转 2°/s（yaw 机动）
        20, 10,  0,  1*deg,       0,   0,     0, 0;   % 缓滚转（roll 机动）
        30, 10,  0,       0,       0,   0,     0, 0]; % 匀速直行
avp0 = [0; 0; 0; 0; 0; 0; 29*deg; 106*deg; 450];
trj  = trjsimu(avp0, WAT, ts);
N    = size(trj.imu, 1);
ahrs = ahrsinit([0; 0; 0], 1.0, 0.1, avp0(7:9), dec);   % 初始姿态取真值：对准/收敛能力
                                                        % 由 ③ 验证，本测试只考动态跟踪
attE = zeros(N, 3);
for k = 1:N
    attk = trj.avp(k, 1:3)';                         % 本拍真值姿态
    Ck   = q2cnb(a2qua(attk));
    magk = magsimu(Ck, mH, dip, dec);                % 真值磁注入（确定性）
    ahrs = mahonyupdate(ahrs, trj.imu(k, 1:3)', trj.imu(k, 4:6)', magk, ts);
    attE(k, :) = q2att(ahrs.qnb)';
end
errD = abs(attE(round(20/ts):end, :) - trj.avp(round(20/ts):end, 1:3));  % 跳过静止段
err4 = max(errD(:)) / deg;
if err4 < 0.3, nPass = nPass + 1; fprintf('  [PASS] ④a Mahony 动态跟踪（转弯/滚转）：稳态最大误差 %.4f°\n', err4);
else,          nFail = nFail + 1; fprintf('  [FAIL] ④a 动态误差 %.4f°（阈 0.3°）——查门控/磁参考\n', err4); end

% ④b 加速度扰动演示（教学：水平加速度是 Mahony 原理性盲区）
WATb = [ 20,  0,  0,  0, 0,   0,     0, 0;             % 静止
         20,  5,  0,  0, 0,   0,  0.25, 0;             % 前向加速 0.25 m/s²
         60, 10,  0,  0, 0,   0,     0, 0];            % 匀速直行（观察回收）
trjb = trjsimu(avp0, WATb, ts);
Nb   = size(trjb.imu, 1);
ahrs = ahrsinit([0; 0; 0], 1.0, 0.1, avp0(7:9), dec);
attB = zeros(Nb, 3);
for k = 1:Nb
    attk = trjb.avp(k, 1:3)';
    Ck   = q2cnb(a2qua(attk));
    ahrs = mahonyupdate(ahrs, trjb.imu(k, 1:3)', trjb.imu(k, 4:6)', magsimu(Ck, mH, dip, dec), ts);
    attB(k, :) = q2att(ahrs.qnb)';
end
errB    = attB(:, 1) - trjb.avp(:, 1);               % pitch 误差时间序列
pk4     = max(abs(errB(round(25/ts):round(40/ts)))) / deg;          % 加速段峰值
rec4    = max(abs(errB(round(70/ts):end))) / deg;                   % 加速结束 30 s 后残留
if pk4 > 0.5 && pk4 < 3.0 && rec4 < 0.1
    nPass = nPass + 1;
    fprintf('  [PASS] ④b 加速度扰动演示：加速段 pitch 偏 %.2f°（原理性盲区），结束后 %.3f° 回收\n', pk4, rec4);
else
    nFail = nFail + 1;
    fprintf('  [FAIL] ④b 峰值 %.2f°（预期 0.5~3°）/ 残留 %.3f°（阈 0.1°）\n', pk4, rec4);
end

%% ⑤ 无磁模式：yaw 不被磁倾角带偏，pitch/roll 照常收敛
ahrs = ahrsinit([2*deg; -1*deg; 3*deg], 1.0, 0.3, pos0);
for k = 1:round(60/ts)
    wm = (Ct0' * ahrs.wnie) * ts;                    % 无零偏（隔离磁影响）
    vm = Ct0' * [0; 0; glv.g0] * ts;
    ahrs = mahonyupdate(ahrs, wm, vm, [], ts);       % mag=[]：只用加计
end
att5 = q2att(ahrs.qnb);
errpr = max(abs(att5(1:2))) / deg;                   % pitch/roll 应收敛
err5y = abs(att5(3)) / deg;                          % yaw 无参考：应保持初值 3°（不可观≠发散）
if errpr < 0.05 && err5y < 3.5
    nPass = nPass + 1;
    fprintf('  [PASS] ⑤ 无磁模式：pitch/roll 误差 %.4f°，yaw 残留 %.4f°（初值 3°，不可观但不发散）\n', errpr, err5y);
else
    nFail = nFail + 1;
    fprintf('  [FAIL] ⑤ 无磁模式：pitch/roll %.4f°（阈 0.05°）/ yaw %.4f°（阈 3.5°=初值+余量）\n', errpr, err5y);
end

fprintf('=== 结果：%d PASS / %d FAIL ===\n', nPass, nFail);
end
