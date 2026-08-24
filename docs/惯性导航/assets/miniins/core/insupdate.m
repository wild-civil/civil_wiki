function ins = insupdate(ins, wm, vm, ts)
% insupdate - 机械编排六步：姿态 / 速度 / 位置更新（逐行注释教学版）
%
% 对标 PSINS `base/base1/insupdate.m`，本库自写、零依赖、逐行注释。
% 每 nn=2 拍（双子样）调用一次，把 ins 推进一步。
%
% ─── 公式层总览（六步，全系列核心）─────────────────────────────────
%   ① 圆锥/划桨补偿   φm = Σwm + ½·wm1×wm2        (公式 4.1)
%                     Δvbm = Σvm + ½·(wm1+wm2)×(vm1+vm2)
%   ② 标定            φm = Kg·φm − eb·nts          (公式 4.2)
%                     Δvbm = Ka·Δvbm − db·nts
%   ③ 地球参数         eth = earth(pos, vn)         (公式 3.1–3.6)
%   ④ 速度更新         fn = Cbn·f;  an = rotv(−wnin·nts/2, fn) + gcc
%                     vn⁺ = vn⁻ + an·nts            (公式 4.3)
%   ⑤ 位置更新         p⁺ = p⁻ + Mpv·(vn⁻+vn⁺)/2·nts  (公式 4.4)
%   ⑥ 姿态更新         qnb⁺ = rv2q(−wnin·nts) ⊗ qnb⁻ ⊗ rv2q(φm)  (公式 4.5)
%
% ─── 新手备注 ───────────────────────────────────────────────────────
%   · ①②是"预处理"（补偿/标定），③是"查表"，④⑤⑥是"积分"；
%   · ④ = 科普 03 的比力方程 f = a − g（fn 转导航系、加 gcc 得运动
%     加速度）；⑤ = 科普 09 的位置微分（Mpv 由曲率半径构成）；
%     ⑥ = 科普 07 的四元数姿态更新（先右乘体轴增量、再左乘导航系
%     旋转补偿，两个 rv2q 夹住 qnb）；
%   · **与 P1 的 trjsimu 互逆**：trjsimu 从"想要的姿态/速度/位置"
%     反算 wm/vm；本函数从 wm/vm 积分回姿态/速度/位置。无误差时，
%     trjsimu 的 imu 喂给本函数应完美复现 trj.avp（自洽性测试）。
%   · 输入输出全部走 ins 结构体（字段见 data_classes.m）。

% ─── 代码（六步逐行）────────────────────────────────────────────────
nts = 2*ts;                                     % 双子样总时长 nts = 2ts

%% ① 圆锥/划桨补偿（公式 4.1）
wm1 = wm(1,:)';  wm2 = wm(2,:)';                % 两个子样的角增量（rad）
vm1 = vm(1,:)';  vm2 = vm(2,:)';                % 两个子样的速度增量（m/s）
phim = (wm1 + wm2) + 0.5*cross(wm1, wm2);       % 等效旋转矢量（公式 4.1，圆锥项 ½·wm1×wm2）
dvbm = (vm1 + vm2) + 0.5*cross(wm1 + wm2, vm1 + vm2); % 等效速度增量（划桨项，公式 4.1）

%% ② 标定：把刻度/零偏误差"洗掉"（公式 4.2；教学默认 Kg=Ka=I、eb=db=0）
phim = ins.Kg * phim - ins.eb * nts;            % 角增量标定（公式 4.2）
dvbm = ins.Ka * dvbm - ins.db * nts;            % 速度增量标定（公式 4.2）

%% ③ 地球参数更新（公式 3.1–3.6）
eth = earth(ins.pos, ins.vn);               % 曲率半径/wnin/gcc（随位置每步更新）

%% ④ 速度更新：比力方程（公式 4.3）
fn   = qmulv(ins.qnb, dvbm) / nts;          % 比力转导航系（Δv/nts = 平均比力 f）
an   = rotv(-eth.wnin * nts/2, fn) + eth.gcc; % 补偿半拍导航系旋转 + 重力/哥氏/向心（公式 4.3）
vn1  = ins.vn + an * nts;                       % 速度积分：vn⁺ = vn⁻ + an·nts

%% ⑤ 位置更新（公式 4.4）
lat = ins.pos(1);                               % 当前纬度（弧度，Mpv 需要）
Mpv = [0,            1/eth.RMh,          0;     % 位置微分阵：d(lat)=vN/RMh
       1/(eth.RNh*cos(lat)),  0,         0;     %              d(lon)=vE/(RNh·cosL)
       0,            0,               1];       %              d(h)  =vU
pos1 = ins.pos + Mpv * (ins.vn + vn1)/2 * nts;  % 梯形积分（用 vn⁻ 与 vn⁺ 均值，公式 4.4）

%% ⑥ 姿态更新：四元数版"旋转矢量积分"（公式 4.5）
qnb1 = rv2q(-eth.wnin * nts);               % 导航系旋转补偿（左乘因子，公式 4.5）
qnb1 = qmul(qnb1, ins.qnb);                 % qnb1 = rv2q(−wnin·nts) ⊗ qnb⁻
qnb1 = qmul(qnb1, rv2q(phim));          % 再右乘体轴增量 rv2q(φm)：完整公式 4.5
qnb1 = qnb1 / norm(qnb1);                       % 归一化（防长期积分模长漂移，P2 坑 8）

%% 写回 ins
ins.qnb = qnb1;                                 % 更新后姿态
ins.vn  = vn1;                                  % 更新后速度
ins.pos = pos1;                                 % 更新后位置
ins.eth = eth;                                  % 保存地球参数（后续步骤/绘图可用）
ins.wib = phim / nts;                           % 陀螺测量角速度（体轴，含补偿后）
ins.t   = ins.t + nts;                          % 时间推进 nts
end
