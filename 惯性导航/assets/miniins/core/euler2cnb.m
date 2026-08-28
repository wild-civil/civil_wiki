function Cnb = euler2cnb(att)
% euler2cnb - 姿态角 → 姿态阵 Cnb（体→导航，PSINS 约定，Mini-INS M4）
%
% ⚠️ M4 起全库切换到 PSINS 约定（等价于 a2mat）：机体系 **x 右、y 前、z 上**，
% pitch 绕 x、roll 绕 y、yaw 绕 z。与 M1 的"航空 NED（x 前 y 右 z 下，
% pitch 绕 y）"**不是同一约定**——对拍 PSINS（P4/P5）必须用本约定，
% 两者对纯 yaw 相同、对 pitch/roll 差一个转置级。
%
% ─── 公式 ──────────────────────────────────────────────────────────
%   Cnb = q2cnb( a2qua(att) )   （即 PSINS a2mat(att)）
%   直接写开：
%     Cnb = | c2·c1 + s2·s3·s0,   −s2·c1 + c2·s3·s0,  c3·s0 |   （0=pitch 1=roll 2=yaw 3=…）
%   不需要背——a2qua 是唯一"att→四元数"入口，本函数只是它的姿态阵形式。
%
% ─── 新手备注 ───────────────────────────────────────────────────────
%   · 自检：att=[0;0;0] → 单位阵；att=[0;0;90°] → 绕 z 转 90°；
%     att=[90°;0;0] → 绕 **x** 轴转 90°（右翼轴，不是航空的 y 轴！）。
%   · 输出名用 Cnb（体→导航）避免与旧 Cbn 混淆；变量名 Cbn 在 PSINS 里
%     也常指"体→导航"（如 ins.Cbn），语义以注释为准。

Cnb = q2cnb(a2qua(att));
end
