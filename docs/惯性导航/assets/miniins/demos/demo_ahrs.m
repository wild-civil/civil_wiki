function demo_ahrs()
% demo_ahrs - 姿态解算（AHRS）三联演示（Mini-INS M-A 收尾 demo）
%
% 三张图覆盖 Mahony 互补滤波的三个关键行为：
%   [图1 静态收敛]  3~5° 初始误差 + 100°/h 级陀螺零偏
%                   → 姿态误差收敛到 0，且积分项 exyzInt 收敛到真零偏（比值→1）
%   [图2 动态跟踪]  匀速直行 / 左转 2°/s / 缓滚 1°/s
%                   → 机动中姿态误差仍在 0.03° 量级（陀螺零误差，门控生效）
%   [图3 加速度扰动] 前向加速 0.25 m/s² 持续 20 s
%                   → pitch 被拽偏 ~1.5°（原理性盲区），加速结束后回收
%
% 运行：cd docs/惯性导航/assets/miniins/demos; demo_ahrs
% 出图：../assets/demo_ahrs_{static,dynamic,disturb}.png
%       （图内文字全 ASCII：DejaVu 无中文字形会出豆腐块，中文说明见 wiki P5）
% 要求：无工具箱，确定性（零噪声、随机注入关）。

addpath(fullfile(fileparts(mfilename('fullpath')), '..', 'core'));
glv = glvs();  deg = glv.deg;  dph = glv.deg/3600;
ts  = 0.01;  dcy = 10;                              % 采样 0.01 s，出图每 10 拍取一点
outdir = fullfile(fileparts(mfilename('fullpath')), '..', 'assets');
if exist(outdir, 'dir') ~= 7, mkdir(outdir); end

% 公共量：地磁（北京附近典型值）
mH = 28000;  dip = 58*deg;  dec = -7*deg;
pos0 = [29*deg; 106*deg; 450];

fprintf('%s\n', repmat('=', 1, 66));
fprintf('Mini-INS M-A：姿态解算 AHRS 演示（Mahony 互补滤波）\n');
fprintf('%s\n', repmat('=', 1, 66));

%% ========== 图1：静态收敛 + 零偏吸收 ==========
Ct0 = q2cnb(a2qua([0; 0; 0]));                      % 真值姿态 = 水平朝北
ebT = [50; -30; 20] * dph;                          % 真陀螺零偏（°/h）
mag_s = magsimu(Ct0, mH, dip, dec);                 % 静态磁测量（无噪声）
T = 300;  N = round(T/ts);
ahrs = ahrsinit([3*deg; -3*deg; 5*deg], 1.0, 0.3, pos0, dec);
attE = zeros(ceil(N/dcy), 3);  ratE = zeros(ceil(N/dcy), 3);  tt = zeros(ceil(N/dcy), 1);
ki = 0;
for k = 1:N
    wm = (Ct0' * ahrs.wnie + ebT) * ts;             % 静止陀螺真值 = 地球自转 + 零偏
    vm = Ct0' * [0; 0; glv.g0] * ts;                % 静止比力 = 天向 g
    ahrs = mahonyupdate(ahrs, wm, vm, mag_s, ts);
    if mod(k, dcy) == 0                             % 降采样记录（出图轻量）
        ki = ki + 1;
        attE(ki, :) = (q2att(ahrs.qnb))';           % 真值为 0 → 估计值即误差
        ratE(ki, :) = (ahrs.exyzInt ./ ebT)';       % 积分项/真零偏（→1 表示吸收）
        tt(ki) = k * ts;
    end
end
attE = attE(1:ki, :) / deg;  ratE = ratE(1:ki, :);  tt = tt(1:ki);

f = figure('Visible', 'off', 'Position', [100 100 900 560]);
subplot(211), plot(tt, attE(:,1), 'r', tt, attE(:,2), 'g', tt, attE(:,3), 'b', 'LineWidth', 1.2);
grid on; xlabel('t (s)'); ylabel('att error (deg)');
title('Static: attitude error convergence (init 3-5 deg, gyro bias 50/-30/20 deg/h)');
legend('pitch', 'roll', 'yaw', 'Location', 'northeast');
subplot(212), plot(tt, ratE(:,1), 'r', tt, ratE(:,2), 'g', tt, ratE(:,3), 'b', 'LineWidth', 1.2);
grid on; xlabel('t (s)'); ylabel('exyzInt / true bias');
title('Bias absorption: integral term / true gyro bias (converges to 1)');
legend('x', 'y', 'z', 'Location', 'southeast');
print(f, '-dpng', '-r150', fullfile(outdir, 'demo_ahrs_static.png'));
close(f);
fprintf('[1] static  : final att err = [%.4f %.4f %.4f] deg | exyzInt/eb = [%.2f %.2f %.2f]\n', ...
        attE(end,1), attE(end,2), attE(end,3), ratE(end,1), ratE(end,2), ratE(end,3));

%% ========== 图2：动态跟踪（转弯 + 滚转） ==========
WAT = [ 20,  0,  0,       0,       0,   0, 0, 0;           % 静止
        60, 10,  0,       0,       0,   0, 0, 0;           % 匀速直行
        30, 10,  0,       0,  2*deg,   0, 0, 0;           % 左转 2°/s
        20, 10,  0,  1*deg,       0,   0, 0, 0;           % 缓滚 1°/s
        30, 10,  0,       0,       0,   0, 0, 0];         % 匀速直行
avp0 = [0; 0; 0; 0; 0; 0; 29*deg; 106*deg; 450];
trj  = trjsimu(avp0, WAT, ts);
Nd   = size(trj.imu, 1);
ahrs = ahrsinit([0; 0; 0], 1.0, 0.1, avp0(7:9), dec);
attD = zeros(ceil(Nd/dcy), 3);  errD = zeros(ceil(Nd/dcy), 3);  tt2 = zeros(ceil(Nd/dcy), 1);
ki = 0;
for k = 1:Nd
    attk = trj.avp(k, 1:3)';
    Ck   = q2cnb(a2qua(attk));
    ahrs = mahonyupdate(ahrs, trj.imu(k, 1:3)', trj.imu(k, 4:6)', magsimu(Ck, mH, dip, dec), ts);
    if mod(k, dcy) == 0
        ki = ki + 1;
        attD(ki, :) = attk';
        errD(ki, :) = (q2att(ahrs.qnb) - attk)';
        tt2(ki) = k * ts;
    end
end
attD = attD(1:ki, :) / deg;  errD = errD(1:ki, :) / deg;  tt2 = tt2(1:ki);
idx = tt2 >= 20;                                          % 跳过静止段
maxD = max(abs(errD(idx, :)));

f = figure('Visible', 'off', 'Position', [100 100 900 560]);
subplot(211), plot(tt2, attD(:,1), 'r', tt2, attD(:,2), 'g', tt2, attD(:,3), 'b', 'LineWidth', 1.2);
grid on; xlabel('t (s)'); ylabel('true att (deg)');
title('Dynamic: true attitude (straight -> yaw turn 2 deg/s -> roll 1 deg/s)');
legend('pitch', 'roll', 'yaw', 'Location', 'northwest');
subplot(212), plot(tt2, errD(:,1), 'r', tt2, errD(:,2), 'g', tt2, errD(:,3), 'b', 'LineWidth', 1.2);
grid on; xlabel('t (s)'); ylabel('att error (deg)');
title('Attitude error during maneuvers (steady-state max < 0.1 deg)');
legend('pitch', 'roll', 'yaw', 'Location', 'northwest');
print(f, '-dpng', '-r150', fullfile(outdir, 'demo_ahrs_dynamic.png'));
close(f);
fprintf('[2] dynamic : steady-state max err = [%.4f %.4f %.4f] deg\n', maxD(1), maxD(2), maxD(3));

%% ========== 图3：加速度扰动（水平加速对门控不可见） ==========
WATb = [ 20,  0,  0, 0, 0,   0,     0, 0;                 % 静止
         20,  5,  0, 0, 0,   0,  0.25, 0;                 % 前向加速 0.25 m/s²
         60, 10,  0, 0, 0,   0,     0, 0];                % 匀速直行（观察回收）
trjb = trjsimu(avp0, WATb, ts);
Nb   = size(trjb.imu, 1);
ahrs = ahrsinit([0; 0; 0], 1.0, 0.1, avp0(7:9), dec);
errB = zeros(ceil(Nb/dcy), 1);  tt3 = zeros(ceil(Nb/dcy), 1);  a2 = zeros(ceil(Nb/dcy), 1);
ki = 0;
for k = 1:Nb
    attk = trjb.avp(k, 1:3)';
    Ck   = q2cnb(a2qua(attk));
    ahrs = mahonyupdate(ahrs, trjb.imu(k, 1:3)', trjb.imu(k, 4:6)', magsimu(Ck, mH, dip, dec), ts);
    if mod(k, dcy) == 0
        ki = ki + 1;
        errB(ki) = (q2att(ahrs.qnb) - attk)' * [1; 0; 0];  % pitch 误差
        a2(ki)   = trjb.avp(k, 5);                          % 前向速度（看加速/滑行分段）
        tt3(ki)  = k * ts;
    end
end
errB = errB(1:ki) / deg;  a2 = a2(1:ki);  tt3 = tt3(1:ki);
pk   = max(abs(errB(tt3 >= 22 & tt3 <= 40)));
rec  = max(abs(errB(tt3 >= 70)));

f = figure('Visible', 'off', 'Position', [100 100 900 560]);
subplot(211), plot(tt3, a2, 'k', 'LineWidth', 1.4);
grid on; xlabel('t (s)'); ylabel('forward speed (m/s)');
title('Disturbance: 0.25 m/s^2 forward accel during t=20-40 s');
subplot(212), plot(tt3, errB, 'r', 'LineWidth', 1.2);
grid on; xlabel('t (s)'); ylabel('pitch error (deg)');
title('Pitch pulled by horizontal accel (gating blind: |||f||-g| is 2nd-order small)');
print(f, '-dpng', '-r150', fullfile(outdir, 'demo_ahrs_disturb.png'));
close(f);
fprintf('[3] disturb : pitch peak %.2f deg | recovered to %.3f deg (t>70 s)\n', pk, rec);
fprintf('%s\n', repmat('=', 1, 66));
fprintf('figures -> %s\n', outdir);
end
