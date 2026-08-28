function att = q2att(q)
% q2att - 四元数 → 姿态角（PSINS 约定，Mini-INS M4）
%
% 对标 PSINS `base/base0/q2att.m`，逐元素一致；是 a2qua 的逆。
%
% ─── 输入/输出 ─────────────────────────────────────────────────────
%   q   = [w; x; y; z]  4×1 单位四元数
%   att = [pitch; roll; yaw]（弧度）3×1（PSINS 约定：pitch 绕 x、roll 绕 y、yaw 绕 z）
%
% ─── 公式（PSINS q2att.m）──────────────────────────────────────────
%   pitch = asin( 2·(q2·q3 + q0·q1) )
%   roll  = atan2( -2·(q1·q3 − q0·q2),  q0² − q1² − q2² + q3² )
%   yaw   = atan2( -2·(q1·q2 − q0·q3),  q0² − q1² + q2² − q3² )
%   · ±q 表示同一姿态（四元数等价），q2att 输出相同 att。

q0 = q(1);  q1 = q(2);  q2 = q(3);  q3 = q(4);
att = [ asin(2*(q2*q3 + q0*q1));
        atan2(-2*(q1*q3 - q0*q2),  q0^2 - q1^2 - q2^2 + q3^2);
        atan2(-2*(q1*q2 - q0*q3),  q0^2 - q1^2 + q2^2 - q3^2) ];
end
