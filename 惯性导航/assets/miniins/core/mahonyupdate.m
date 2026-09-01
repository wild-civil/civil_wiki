function ahrs = mahonyupdate(ahrs, wm, vm, mag, ts)
% mahonyupdate - Mahony 互补滤波姿态更新（单拍，Mini-INS M-A 核心）
%
% 对标 PSINS `base/AHRS/MahonyUpdate.m`（同思想：陀螺积分为主、
% 加计/磁 PI 反馈拉回），按本库约定（qnb 体→导航、x右 y前 z上）自写。
% PSINS 的自适应 tau / iirflt 低通为进阶特性，本教学版改用更直观的
% "准静态门控"（见 ②），差异在 wiki 页对照表里说明。
%
% ─── 公式层（Mahony PI 反馈，公式 6.2–6.4）──────────────────────────
%   ① 比力方向   acc = f/|f|（准静态下 ≈ 导航天向在体系投影）
%   ② 准静态门控 λ：|‖f‖−g| < 0.05 全信，> 0.2 全不信（PSINS 自适应 tau
%      同思路：|‖f‖−g|>0.1 即把时间常数拉到 10⁵ s ≈ 冻结加计修正）。
%      ⚠️ 教学实测（verify_ahrs ④）：前向加速 0.25 m/s² 时若门控半开
%      （λ≈0.56），pitch 会被"假天向"拽偏 ~1.5°（=atan(a/g)+积分过冲）
%      ——线性加速度是 Mahony 的头号天敌，门控必须足够果断。
%   ③ 磁参考     m_pred = Cbn'·[水平指向磁北]（只取磁航向，磁偏角 dec 补偿：
%                 磁北 ≠ 真北，参考方向 = 真北左偏 dec，不补则 yaw 偏 −dec）
%   ④ 误差合成   e = λ·(Cbn(3,:)'×acc) + (m_pred×m̂)   （pred × meas，公式 6.2）
%   ⑤ PI 反馈    exyzInt += Ki·e·ts；ω_corr = Kp·e + exyzInt   （公式 6.3）
%   ⑥ 姿态更新   q⁺ = q ⊗ rv2q(wm − (Cbn'·wnie + ω_corr)·ts)   （公式 6.4）
%
% ─── 输入/输出 ─────────────────────────────────────────────────────
%   ahrs  ahrsinit 创建的结构体（原位更新返回）
%   wm    3×1 本拍陀螺角增量（rad）
%   vm    3×1 本拍加计速度增量（m/s）
%   mag   3×1 本拍体磁测量（单位任意；传 [] 表示无磁、只靠加计）
%   ts    本拍时长（s）
%
% ─── 新手备注 ───────────────────────────────────────────────────────
%   · 为什么 e 要 "pred × meas"？两个近似平行的向量叉乘，模 ≈ 夹角、
%     方向 = 把 pred 转到 meas 需要的旋转轴——天然就是"姿态误差向量"；
%   · 为什么磁要强制水平 + 补磁偏角？地磁有磁倾角，若直接拿整个磁向量
%     当参考，pitch/roll 会被磁倾角带偏（磁倾角 ≠ 重力方向！）——强制
%     水平化后磁只贡献 yaw，加计只贡献 pitch/roll，职责清晰；而磁场
%     水平分量指向**磁北**（真北西偏 dec），参考方向必须写成
%     [sin(dec); cos(dec)]，否则 yaw 会系统性偏差 −dec（仿真 dec=−7°
%     时实测 yaw 卡在 −6.9°——verify_ahrs ③ 就是这么抓到这个坑的）；
%   · 门控是 AHRS 的"保命符"——但它只拦得住**垂直**加速度：|‖f‖−g|
%     对水平加速度是二阶小量（0.25 m/s² 前向加速只让模长变 0.003），
%     持续水平加速仍会把 pitch 拽偏 atan(a/g)（verify_ahrs ④ 实测
%     ~1.5°）。这是 Mahony 的原理性盲区（PSINS 自适应 tau 同样如此），
%     工程上要靠 GNSS 速度/杆臂补偿或升级 KF——见 wiki 页"局限"一节；
%   · 陀螺项里减 Cbn'·wnie：陀螺测的是相对惯性系的旋转，姿态相对
%     地球，必须扣掉地球自转（表达式见 earth.m 公式 3.3）。

%% ① 比力方向（加计"投票"的原始信息）
f = vm / ts;                                     % 本拍平均比力（m/s²）
nmf = norm(f);
if nmf > 0
    acc = f / nmf;                               % 归一化比力方向（体）
else
    acc = [0; 0; 0];                             % 静默拍（理论不出现，防 0/0）
end

%% ② 准静态门控 λ：|‖f‖−g| < 0.05 全信，> 0.2 全不信，中间线性过渡
nm1 = abs(nmf - ahrs.g0);                        % 比力模偏离重力的量（机动强度）
if nm1 <= 0.05
    lam = 1;
elseif nm1 >= 0.2
    lam = 0;
else
    lam = (0.2 - nm1) / 0.15;                    % 线性衰减（公式 6.2 的 λ）
end

%% ③④ 误差向量 e（公式 6.2）：天向项 + 磁向项
e = zeros(3, 1);
if lam > 0
    e = lam * cross(ahrs.Cbn(3, :)', acc);       % 预测天向（Cbn 第 3 行=nav z 在体系）× 实测
end
if isempty(mag) == false && norm(mag) > 0
    m = mag / norm(mag);                         % 实测磁方向（体）
    mb_n = ahrs.Cbn * m;                         % 体磁 → 导航系
    mh = norm(mb_n(1:2));                        % 水平分量模（垂直分量=磁倾角，丢弃）
    mb_n(1:2) = mh * [sin(ahrs.dec); cos(ahrs.dec)];  % 磁参考：水平指向磁北（含 dec 补偿）
    m_pred = ahrs.Cbn' * mb_n;                   % 磁航向参考投回体系（预测体磁）
    e = e + cross(m_pred, m);                    % 磁误差（pred × meas，只约束 yaw）
end

%% ⑤ PI 反馈（公式 6.3）：积分项稳态吸收陀螺零偏
ahrs.exyzInt = ahrs.exyzInt + e * ahrs.Ki * ts;  % ∫Ki·e
eb = ahrs.Kp * e + ahrs.exyzInt;                 % 反馈角速度（rad/s）

%% ⑥ 姿态更新（公式 6.4）：陀螺积分 − 地球自转 − PI 反馈
phim = wm - (ahrs.Cbn' * ahrs.wnie + eb) * ts;   % 等效旋转矢量（体）
ahrs.qnb = qmul(ahrs.qnb, rv2q(phim));           % 右乘体轴增量（与 insupdate ⑥ 同构）
ahrs.qnb = ahrs.qnb / norm(ahrs.qnb);            % 归一化（防模长漂移，P2 坑 8）
ahrs.Cbn = q2cnb(ahrs.qnb);                      % 同步姿态阵
ahrs.tk = ahrs.tk + ts;                          % 时钟推进
end
