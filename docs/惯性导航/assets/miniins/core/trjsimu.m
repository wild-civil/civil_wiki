function trj = trjsimu(avp0, wat, ts)
% trjsimu - 正演机：从"想要的轨迹"反算 IMU 该读到什么（Mini-INS 轨迹生成 M4 版）
%
% ⚠️ M4 起重构为对齐 P4 `assets/gen_sins_dr.py` 的 minitrj（即 PSINS trjsimu.m
% 教学版），M2 的简化版（绕 z Cnt / m2rv 反算 / 单子样）已废弃。与 M2 的差异：
%  ① Cnt 用完整构造（含 pitch 耦合，见公式 5.2'）；
%  ② φm 用"四元数差分"反算（dq = conj(a2qua(att旧))⊗a2qua(att新) → 2·atan2），
%     不是 m2rv(ΔCbn)；
%  ③ wm 做**双子样反解**：wm = inv(I + 1/12·[wm_1×])·φm（PSINS 标准，
%     消费端 insupdate 的圆锥补偿 ½·wm1×wm2 与之精确互逆）；
%  ④ dvbm 用**上一拍** Cbn_1（不是当前 Cnb）、无 rv2m(wnin·ts/2) 因子；
%  ⑤ 位置推进用**中点法**（vn01 = (vn+vn1)/2，PSINS 标准）。
%
% ─── 输入/输出 ─────────────────────────────────────────────────────
%   avp0 = [att0(3); vn0(3); pos0(3)]  初始状态（att 弧度；pos lat/lon 弧度 + h 米）
%   wat  = 航段表 N×8 [lasting vel wx wy wz ax ay az]（与 P4 WAT 同格式）
%   ts   = 采样间隔（s）
%   trj  = struct：avp(N×10) 真值 [att vn pos t] / imu(N×7) [wm vm t] / ts / len / avp0
%        （od 里程由 odsimu.m 单独生成——M4 起职责分离）
%
% ─── ⚠️ 机体系约定（M4 统一）───────────────────────────────────────
%   x 右、y 前、z 上。wat 的加速度 at = [a1; a2; a3]：**a2 = 前向**（沿体 y）、
%   a1 = 侧向（沿体 x）。yaw 增大 = 车头左转（北→西）。
%
% ─── 正演六步（公式编号对应拆解系列；与 P4 minitrj 逐行一致）──────
%   ① att 推进   att ← att + w_t·ts
%   ② 速度推进   a_n = C_nt·a_t（Cnt 完整含 pitch 耦合）；vn¹ = vn + a_n·ts
%   ③ 位置推进   中点法 vn01 → dpos01 → pos ← pos + 2·dpos01
%   ④ 陀螺增量   dq = conj(a2qua(att−w·ts))⊗a2qua(att)；φm = 2·atan2(dq)
%                 φm += (Cbn_1 + Cnb')·wnin·ts/2；wm = inv(I+1/12[wm_1×])·φm
%   ⑤ 加计增量   dvbm = Cbn_1·(a_n − gcc)·ts；vm = inv(I + ½[wm×])·dvbm
%   ⑥ 输出       avp(k,:) / imu(k,:)

% ---- 解析输入 ----
att = avp0(1:3);  vn = avp0(4:6);  pos = avp0(7:9);
len = round(sum(wat(:,1)) / ts);          % 总拍数
ts2 = ts/2;                                % 半拍（中点法用）

% 预分配
avp = zeros(len, 10);  imu = zeros(len, 7);

% 主循环（逐拍；wat 每行一段，段内 w/a 恒定）
ki = 0;  t = 0;
qnb = a2qua(att);
Cbn_1 = q2cnb(qnb)';                      % C_n^b（上一拍，转置 = 体←导航）
wm_1 = zeros(3,1);                          % 上一拍 wm（双子样反解需要）
for i = 1:size(wat,1)
    lenk = round(wat(i,1)/ts);             % 本段拍数
    wt = wat(i,3:5)';  at = wat(i,6:8)';   % 段内恒定角速度/加速度
    for kk = 1:lenk
        % ① att 推进（公式 5.1）
        si = sin(att(1)); ci = cos(att(1)); sk = sin(att(3)); ck = cos(att(3));
        Cnt = [ck, -ci*sk,  si*sk;          % 轨迹系→导航系（完整，含 pitch 耦合）
               sk,  ci*ck, -si*ck;
               0,   si,     ci];
        att = att + wt*ts;
        Cnb = q2cnb(a2qua(att));            % 推进后的 C_n^b（体→导航）

        % ② 速度推进（公式 5.2）：中点法 vn01
        an = Cnt * at;
        vn1 = vn + an*ts;  vn01 = (vn + vn1)/2;

        % ③ 位置推进（公式 5.3'，中点法）
        eth = earth(pos, vn01);             % 用中点速度算地球参数
        dpos01 = [vn01(2)/eth.RMh; vn01(1)/eth.clRNh; vn01(3)] * ts2;
        pos = pos + 2*dpos01;

        % ④ 陀螺增量反算（公式 5.4'，四元数差分 + 双子样反解）
        dq = qmul(qconj(a2qua(att - wt*ts)), a2qua(att));   % 姿态差四元数
        phim = 2*[atan2(dq(2),dq(1)); atan2(dq(3),dq(1)); atan2(dq(4),dq(1))];
        phim = phim + (Cbn_1 + Cnb') * (eth.wnin*ts2);      % wnin 补偿
        wm = inv(eye(3) + 1/12*skew(wm_1)) * phim;          % 双子样反解（PSINS 标准）

        % ⑤ 加计增量反算（公式 5.5'）：用上一拍 Cbn_1（PSINS 标准）
        dvbm = Cbn_1 * (an - eth.gcc) * ts;
        vm = inv(eye(3) + 0.5*skew(wm)) * dvbm;

        % ⑥ 输出
        ki = ki + 1;
        avp(ki,:) = [att; vn1; pos; t]';
        imu(ki,:) = [wm; vm; t]';
        wm_1 = wm;  Cbn_1 = Cnb';  vn = vn1;  t = t + ts;
    end
end

% 打包（截断到实际行数）
avp = avp(1:ki,:);  imu = imu(1:ki,:);
trj = struct('avp', avp, 'imu', imu, 'ts', ts, 'len', ki, 'avp0', avp0);
end
