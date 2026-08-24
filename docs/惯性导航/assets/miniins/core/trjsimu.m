function trj = trjsimu(avp0, wat, ts)
% trjsimu - 正演机：从"想要的轨迹"反算 IMU 该读到什么（Mini-INS 轨迹生成 M2）
%
% 对标 PSINS `base/base1/trjsimu.m`，本库教学简化版（零依赖，复用 M1 模块）。
% 输入 avp0（12×1）、wat 表（trjsegment 产出）、ts；输出 trj 结构（数据母版）。
%
% ─── 输入/输出 ─────────────────────────────────────────────────────
%   avp0 = [att0(3); vn0(3); pos0(3)]  初始状态（att 弧度；pos lat/lon 弧度 + h 米）
%   wat  = trjsegment 产出的航段表（N×8）[lasting vel wx wy wz ax ay az]
%   ts   = 采样间隔（s）
%   trj  = struct：avp(N×10) 真值 [att vn pos t] / imu(N×7) 读数 [wm vm t]
%          / od(N×2) / ts / len / avp0
%
% ─── 正演数学（六步，与 insupdate 互逆；公式编号对应拆解系列）─────
%   ① att 推进   att ← att + w_t·ts                （公式 5.1，轨迹系欧拉增量）
%   ② 速度推进   a_n = C_nt·a_t；vn ← vn + a_n·ts  （公式 5.2，轨迹系→导航系）
%   ③ 位置推进   p ← p + [vN/RMh; vE/(RNh·cosL); vU]·ts   （公式 5.3）
%   ④ 陀螺增量   φm = m2rv(Cbn_1'·Cbn) + (Cbn_1+Cbn')·wnin·ts/2   （公式 5.4）
%   ⑤ 加计增量   Δvbm = Cbn·rv2m(wnin·ts/2)·(a_n − gcc)·ts      （公式 5.5）
%   ⑥ 输出       avp(k,:) / imu(k,:)
%
% ─── 新手备注 ───────────────────────────────────────────────────────
%   · 本质 = insupdate 的"逆"：insupdate 从 wm/vm 积分回 avp，本函数
%     从 avp 反算 wm/vm——两者共享同一套 earth 模型（复用 M1 earth.m）；
%   · ④ 的 wm 是**增量**（rad），不是角速度；⑤ 的 vm 是速度增量（m/s）；
%   · 本版每拍输出单子样（wm/vm），双子样圆锥补偿在 insupdate 消费时做
%     （PSINS trjsimu 输出双子样，教学简化为单子样，自洽测试用 P2 坑 5 对齐）。

% ---- 解析输入 ----
att0 = avp0(1:3);  vn0 = avp0(4:6);  pos0 = avp0(7:9);
len = round(sum(wat(:,1)) / ts);      % 总拍数 = 总时长 / ts
Nseg = size(wat, 1);

% 预分配
avp = zeros(len, 10);  imu = zeros(len, 7);

% 逐段展开航段参数表：把 wat 的 N×8 展成 len×7（每拍 [w_t(3) a_t(3)]）
[wt_all, at_all] = expand_wat(wat, ts, len);   % len×3 各一拍

% 主循环（六步）
att = att0;  vn = vn0;  pos = pos0;  t = 0;
Cbn_1 = euler2cnb(att);                        % 上一拍姿态阵（初始）
for k = 1:len
    wt = wt_all(k,:)';   at = at_all(k,:)';     % 本拍轨迹系角速度/加速度

    % ① att 推进（公式 5.1）：轨迹系欧拉角增量
    att = att + wt*ts;

    % ② 速度推进（公式 5.2）：轨迹系→导航系（C_nt 由 pitch/yaw 构造，忽略 roll）
    %     内联 roty(pitch)*rotz(yaw)，避免工具箱依赖（零依赖铁律）
    cp = cos(att(1));  sp = sin(att(1));  cy = cos(att(3));  sy = sin(att(3));
    Cnt = [cp*cy, -cp*sy,  sp;
           sy,     cy,     0;
          -sp*cy,  sp*sy,  cp];
    an  = Cnt * at;                            % 导航系加速度
    vn  = vn + an*ts;                          % 速度积分

    % ③ 位置推进（公式 5.3，ENU 标准微分）
    eth  = earth(pos, vn);                     % 复用 M1 earth.m（RMh/RNh/wnin/gcc）
    dpos = [vn(2)/eth.RMh;  vn(1)/(eth.RNh*cos(pos(1)));  vn(3)];  % [dlat;dlon;dh]
    pos  = pos + dpos*ts;

    % ④ 陀螺增量反算（公式 5.4）：姿态差 + wnin 补偿
    %     ⚠️ 转置方向：Cbn_1'*Cbn（上一拍转置 × 当前拍）才是"从 Cbn_1 转到
    %     Cbn 的体轴增量"；写成 Cbn_1*Cbn' 会得到 −φ（方向反 → 解算姿态反转）。
    %     （2026-08-24 实测踩坑：verify_trj 姿态 RMS 0.92 rad，即此符号错）
    Cbn = euler2cnb(att);                      % 推进后的姿态阵
    phim = m2rv(Cbn_1' * Cbn) + (Cbn_1 + Cbn') * eth.wnin * ts/2;   % 公式 5.4
    wm = phim;                                 % 单子样（教学简化）

    % ⑤ 加计增量反算（公式 5.5）：(a_n − gcc) 是导航系比力，转到体轴
    %     ⚠️ 方向：比力在导航系，转体轴必须用 Cnb = Cbn'（体←导航）。
    %     若误用 Cbn（体→导航），insupdate 里 fn=qmulv(qnb,dvbm) 会得到
    %     Rz(2·yaw)·(a−g) → 方向错 2 倍航向，速度/位置爆（姿态却 PASS）。
    %     （2026-08-24 实测踩坑：与 ④ 转置错构成"双错误抵消"——
    %     之前 wm 反号 + 此处 Cbn 恰好互消，位置/速度假 PASS；wm 修正后
    %     此错暴露。两个转置必须同时正确。）
    Cnb = Cbn';
    dvbm = Cnb * rv2m(eth.wnin*ts/2) * (an - eth.gcc) * ts;       % 公式 5.5
    vm = dvbm;

    % ⑥ 输出
    avp(k,:) = [att; vn; pos; t]';
    imu(k,:) = [wm; vm; t]';
    Cbn_1 = Cbn;   t = t + ts;
end

% 打包
trj = struct('avp', avp, 'imu', imu, 'od', [zeros(len,1), imu(:,end)], ...
             'ts', ts, 'len', len, 'avp0', avp0);
end

%% 局部函数：把航段表展成逐拍参数（每拍一组角速度/加速度）
function [wt_all, at_all] = expand_wat(wat, ts, len)
% 输入 wat N×8 [lasting vel wx wy wz ax ay az]；输出 len×3 逐拍 w 和 a
Nseg = size(wat, 1);
wt_all = zeros(len, 3);  at_all = zeros(len, 3);
k = 1;
for i = 1:Nseg
    n = round(wat(i,1)/ts);                    % 本段拍数
    wt_all(k:k+n-1, :) = repmat(wat(i,3:5), n, 1);   % 段内角速度恒定
    at_all(k:k+n-1, :) = repmat(wat(i,6:8), n, 1);   % 段内加速度恒定
    k = k + n;
end
end
