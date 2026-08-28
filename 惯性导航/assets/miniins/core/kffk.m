function Phikk_1 = kffk(ins)
% kffk - 构造 22 维离散状态转移阵（Mini-INS 组合导航 M4）
%
% 对齐 P4 `assets/gen_sins_dr.py` 的 build_F（即 PSINS `etm.m` 逐块展开），
% 本库显式分块构造，避免 etm.m 线性索引的列主序陷阱（P4 坑 2）。
%
% ─── 状态布局 ─────────────────────────────────────────────────────
%   x = [φ(3) δv(3) δr(3) eb(3) db(3) | dposD(3) dinst(2) dKod(1) dT(1)]
%        1:3   4:6   7:9   10:12 13:15 | 16:18    19:20    21      22
%   单位：φ/eb 弧度，δv m/s，δr/dposD [lat;lon](rad)+h(m)，dinst rad，
%         dKod 无量纲（比例），dT s
%
% ─── 分块含义（φ 角 SINS 误差模型，ENU）───────────────────────────
%   Maa = −[wnin×]            φ 自身（导航系旋转）
%   Mav                       φ-δv（位置速率→姿态）
%   Map = Mp1+Mp2             φ-δr（位置→姿态，含地球曲率/纬度项）
%   Mva = [fn×]               δv-φ（比力叉乘）
%   Mvv = [vn×]Mav − [wnin×]  δv 自身（哥氏）
%   Mvp                       δv-δr（含重力梯度修正）
%   Mpv                       δr-δv（位置微分）
%   Mpp                       δr-δr（曲率随位置变化）
%   −Cbn / +Cbn               eb/db 是体轴零偏，乘 Cbn 转到导航系
%   dposD 块（MpaD/MppD/MpkD）DR 位置误差与 φ/δr/安装角/尺度耦合
%   dT 无动力学耦合（仅在量测 H(1:3,22) = −Mpv·vn）
%
% ─── 离散化：Phikk_1 = I + F·nts（一阶欧拉，nts 短时足够）──────────

eth = ins.eth;  fn = ins.fn;  nts = ins.nts;
qnb = ins.qnb;  vn = ins.vn;  pos = ins.pos;
glv = glvs();                                   % 重力常数 g0（重力梯度修正用）
Cbn = q2cnb(qnb);                                   % 体→导航（eb/db 转导航系用）
lat = pos(1);  sl = sin(lat);  cl = cos(lat);  tl = tan(lat);  secl = 1/cl;
f_RMh = 1/eth.RMh;  f_RNh = 1/eth.RNh;  f_clRNh = 1/(eth.RNh*cl);
f_RMh2 = f_RMh^2;  f_RNh2 = f_RNh^2;
vE = vn(1);  vN = vn(2);
vE_clRNh = vE*f_clRNh;  vE_RNh2 = vE*f_RNh2;  vN_RMh2 = vN*f_RMh2;
wnie = eth.wnie;

% --- SINS 15 维分块（etm.m 逐块）---
Maa = -skew(eth.wnin);
Mav = [0, -f_RMh, 0;  f_RNh, 0, 0;  f_RNh*tl, 0, 0];
Mp1 = [0,0,0;  -wnie(2),0,0;  wnie(1),0,0];
Mp2 = [0,0,vN_RMh2;  0,0,-vE_RNh2;  vE_clRNh*secl, 0, -vE_RNh2*tl];
Map = Mp1 + Mp2;
Mva = skew(fn);
Mvv = skew(vn)*Mav - skew(eth.wnin);
Mvp = skew(vn)*(Mp1 + Map);
scl = sl*cl;
Mvp(3,1) = Mvp(3,1) - glv.g0 * (2*5.2790414e-3 + 4*2.32718e-5*sl*sl) * scl;  % 纬度重力梯度
Mvp(3,3) = Mvp(3,3) + 3.086e-6;                                              % 高度重力梯度
Mpv = [0, f_RMh, 0;  f_clRNh, 0, 0;  0, 0, 1];
Mpp = [0,0,-vN_RMh2;  vE_clRNh*tl, 0, -vE_RNh2*secl;  0,0,0];

F = zeros(22);
F(1:3,1:3)   = Maa;  F(1:3,4:6)   = Mav;  F(1:3,7:9) = Map;   F(1:3,10:12) = -Cbn;
F(4:6,1:3)   = Mva;  F(4:6,4:6)   = Mvv;  F(4:6,7:9) = Mvp;   F(4:6,13:15) = Cbn;
F(7:9,4:6)   = Mpv;  F(7:9,7:9)   = Mpp;
F(10:12,10:12) = diag([-1e-4, -1e-4, -1e-4]);   % eb 一阶马尔可夫（tau 大→≈0）
F(13:15,13:15) = diag([-1e-4, -1e-4, -1e-4]);   % db

% --- DR 扩展 7 维（dposD/dinst/dKod；dT 只在 H）---
F(16:18,1:3)    = Mpv * skew(vn);               % MpaD：φ → dposD
F(16:18,16:18)  = Mpp;                          % MppD
MvkD = norm(vn) * [-Cbn(:,3), Cbn(:,2), Cbn(:,1)];   % 安装角/尺度 → DR 位置速率
MpkD = Mpv * MvkD;
F(16:18,19:20)  = MpkD(:,[1,3]);                % dpitch, dyaw → dposD
F(16:18,21)     = MpkD(:,2);                    % dKod → dposD

Phikk_1 = eye(22) + F * nts;                    % 一阶离散化
end
