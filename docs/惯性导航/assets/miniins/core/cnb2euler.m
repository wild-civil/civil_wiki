function att = cnb2euler(Cnb)
% cnb2euler - 姿态阵 → 姿态角 att=[pitch;roll;yaw]（PSINS 约定，Mini-INS M4）
%
% ⚠️ 与 euler2cnb 配套，M4 起用 PSINS 约定（等价于 q2att）：
% 机体系 x 右、y 前、z 上；pitch 绕 x、roll 绕 y、yaw 绕 z。
%
% ─── 公式 ──────────────────────────────────────────────────────────
%   att = q2att( cnb2q(Cnb) )    （即 PSINS q2att∘cnb2q）
%   · cnb2q 强制 w>0，但 ±q 同一姿态，q2att 输出不变，故无影响。
%
% ─── 新手备注 ───────────────────────────────────────────────────────
%   · 自检：cnb2euler(euler2cnb(att)) ≈ att（数值误差 ~1e-16）；
%   · pitch 用 asin（定义域 [-90°,90°]），roll/yaw 用四象限 atan2。

att = q2att(cnb2q(Cnb));
end
