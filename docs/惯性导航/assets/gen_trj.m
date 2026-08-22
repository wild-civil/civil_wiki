function gen_trj()
% 拆解 PSINS ①：test_SINS_trj 的 wat 表展开 + 关键航段解析值（纯 MATLAB，与 gen_trj.py 双轨）
% =====================================================================================
% test_SINS_trj.m 用 trjsegment 拼了 14 个航段（含复合段展开），最终喂给 trjsimu。
% 本脚本：
%   1) 按 trjsegment 的规则把 14 段展开成完整 wat 表（每行 = [时长, 初速, w(3), a(3)]）
%   2) 解析验证关键物理量：总时长、加速段末速、协调转弯半径、爬升段高度增量
%      （纯解析，两轨逐数字一致；"真值"由 trjsimu 数值积分给出，P2 会验证闭环）
% 无工具箱依赖，运行：gen_trj

DPS = pi / 180.0;    % deg/s -> rad/s
g = 9.8;             % PSINS trjsegment 里的向心加速度参考（cf/9.8）
vel = 0.0;           % 当前段初速（init 段 = 0）
wat = [];

fprintf('%s\n', repmat('=', 1, 70));
fprintf('拆解 PSINS ①：test_SINS_trj wat 表展开 + 解析值（纯 numpy / 纯 MATLAB 双轨）\n');
fprintf('%s\n', repmat('=', 1, 70));

% ---------- 复刻 trjsegment 的 wat 生成逻辑 ----------
    function u(lasting),            wat(end+1,:) = [lasting, vel, 0,0,0, 0,0,0]; end
    function accelerate(lasting,a), wat(end+1,:) = [lasting, vel, 0,0,0, 0,a,0]; vel = vel+lasting*a; end
    function deacc(lasting,a),      wat(end+1,:) = [lasting, vel, 0,0,0, 0,-a,0]; vel = vel-lasting*a; end
    function rl(lasting,w),         wat(end+1,:) = [lasting, vel, 0,-w*DPS,0, 0,0,0]; end
    function rr(lasting,w),         wat(end+1,:) = [lasting, vel, 0, w*DPS,0, 0,0,0]; end
    function tl(lasting,w),         cf=(w*DPS)*vel; wat(end+1,:) = [lasting, vel, 0,0, w*DPS, -cf,0,0]; end
    function tr(lasting,w),         cf=(w*DPS)*vel; wat(end+1,:) = [lasting, vel, 0,0,-w*DPS,  cf,0,0]; end
    function hu(lasting,w),         cf=(w*DPS)*vel; wat(end+1,:) = [lasting, vel, w*DPS,0,0, 0,0, cf]; end
    function hd(lasting,w),         cf=(w*DPS)*vel; wat(end+1,:) = [lasting, vel,-w*DPS,0,0, 0,0,-cf]; end
    function cotl(lasting,w,rollt), cf=(w*DPS)*vel; rw = atan(cf/g)/DPS/rollt; rl(rollt,rw); tl(lasting,w); rr(rollt,rw); end
    function cotr(lasting,w,rollt), cf=(w*DPS)*vel; rw = atan(cf/g)/DPS/rollt; rr(rollt,rw); tr(lasting,w); rl(rollt,rw); end
    function cl(lasting,w,unift),   hu(lasting,w); u(unift); hd(lasting,w); end
    function de(lasting,w,unift),   hd(lasting,w); u(unift); hu(lasting,w); end

% ---------- test_SINS_trj.m 的 14 个航段 ----------
u(100)
accelerate(10, 1)          % 加速 10s, 1 m/s² -> 末速 10 m/s
u(100)
cotl(45, 2, 4)             % 协调左转 45s @ 2°/s（=90°），滚转 4s
u(100)
cotr(50, 9, 4)             % 协调右转 50s @ 9°/s（=450°=1.25 圈），滚转 4s
u(100)
cl(10, 2, 50)              % 爬升：抬头 10s @2°/s + 平飞 50s + 低头 10s
u(100)
de(10, 2, 50)              % 下降：对称
u(100)
deacc(5, 2)                % 减速 5s, 2 m/s² -> 末速 0
u(100)

total = sum(wat(:,1));

% ---------- 1) wat 表 ----------
fprintf('\n[1] 完整 wat 表（每行 = [时长s, 初速m/s, w(°/s), a(m/s²)]，w/a 已转弧度）\n');
fprintf('%3s%7s%8s%7s%7s%7s%7s%7s%7s\n', '#','时长s','初速m/s','w1°','w2°','w3°','a1','a2','a3');
for i = 1:size(wat,1)
    r = wat(i,:);
    fprintf('%3d%8.0f%9.1f%7.2f%7.2f%7.2f%7.3f%7.3f%7.3f\n', ...
        i, r(1), r(2), r(3)/DPS, r(4)/DPS, r(5)/DPS, r(6), r(7), r(8));
end

% ---------- 2) 解析验证 ----------
fprintf('\n[2] 解析验证（纯公式，无仿真）\n');
fprintf('   总时长 Σlasting = %.0f s,  步数 @ts=0.01 = %.0f\n', total, total/0.01);
fprintf('   加速段(10s@1m/s²): 末速 = 0 + 10×1 = %.0f m/s\n', 10*1);
fprintf('   减速段(5s@2m/s²):  末速 = 10 - 5×2 = %.0f m/s\n', 10-5*2);
wL = 2*DPS; vL = 10.0;
fprintf('   coturnleft 45s @2°/s: 转角 = %.0f°, 转弯半径 r = v/ω = %.1f m\n', 45*2, vL/wL);
fprintf('     （cf = ω·v = %.2f m/s² = %.1f%%g，滚转角 = atan(cf/g) = %.1f°）\n', wL*vL, wL*vL/g*100, atan(wL*vL/g)/DPS);
wR = 9*DPS; vR = 10.0;
fprintf('   coturnright 50s @9°/s: 转角 = %.0f° = %.2f 圈, 半径 r = %.1f m\n', 50*9, 50*9/360, vR/wR);
fprintf('     （cf = %.2f m/s² = %.1f%%g，滚转角 ≈ %.1f°）\n', wR*vR, wR*vR/g*100, atan(wR*vR/g)/DPS);
wC = 2*DPS; vC = 10.0; TC = 10.0;
dh_up    = (vC/wC)*(1 - cos(wC*TC));
dh_level = 50*vC*sin(wC*TC);
fprintf('   climb 段高度增量（解析）:\n');
fprintf('     抬头 10s (θ 0→%.0f°): Δh = (v/ω)(1−cosωT) = %.1f m\n', wC*TC/DPS, dh_up);
fprintf('     平飞 50s @%.0f° 仰角:   Δh = t·v·sinθ = %.1f m\n', wC*TC/DPS, dh_level);
fprintf('     低头 10s (对称):               Δh = %.1f m\n', dh_up);
fprintf('     净爬升 ≈ %.1f m（descent 段对称，最终回到原高度）\n', dh_up+dh_level+dh_up);

fprintf('\n[小结]\n');
fprintf('   轨迹 = 航段语言的''程序''：匀速/加减速改速度大小，转弯/滚转/俯仰改方向，\n');
fprintf('   协调转弯用 cf=ω·v 保持向心加速度 → 所有段无缝衔接成一条平滑轨迹。\n');
fprintf('   trjsimu 再按 wat 表数值积分出真值 + IMU 读数（P2 的 test_SINS 将验证闭环）。\n');

end
