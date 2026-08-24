function att = cnb2euler(Cbn)
% cnb2euler - 姿态阵 → 欧拉角 att=[pitch;roll;yaw]（euler2cnb 的逆）
%
% ─── 公式 2.6（符号表）─────────────────────────────────────────────
%   Cbn   姿态阵（体→导航）  3×3
%   att   = [pitch; roll; yaw] 欧拉角（弧度）  3×1
%
%   由公式 2.5 的第三行反解（-sp 在 C(3,1)，cp·sr 在 C(3,2)…）：
%     pitch = −asin( C(3,1) )
%     roll  =  atan2( C(3,2), C(3,3) )
%     yaw   =  atan2( C(2,1), C(1,1) )
%
% ─── 新手备注 ───────────────────────────────────────────────────────
%   · atan2(y,x) 是"四象限反正切"，能正确区分 ±90° 附近的象限，
%     这是取姿态角必须用 atan2 而不是 atan 的原因；
%   · pitch 用 asin 而非 atan2：俯仰定义域 [-90°, 90°]，asin 天然安全
%     （若超出会因 arcsin 值域产生伪解，工程上需防 C(3,1) 越界 clip）；
%   · 自检：cnb2euler(euler2cnb(att)) 应 ≈ att（弧度制，数值误差 ~1e-16）。

% ─── 代码（公式 2.6 逐行）───────────────────────────────────────────
att = zeros(3,1);                        % 预分配输出
att(1) = -asin(max(min(Cbn(3,1), 1), -1));  % pitch = −asin(C(3,1))（clip 防越界）
att(2) =  atan2(Cbn(3,2), Cbn(3,3));     % roll  = atan2(C(3,2), C(3,3))
att(3) =  atan2(Cbn(2,1), Cbn(1,1));     % yaw   = atan2(C(2,1), C(1,1))
end
