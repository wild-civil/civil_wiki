function Cbn = euler2cnb(att)
% euler2cnb - 欧拉角 → 姿态阵 Cbn（Mini-INS 基础转换系列）
%
% ─── 公式 2.5（符号表）─────────────────────────────────────────────
%   att = [pitch; roll; yaw]  欧拉角（弧度）  3×1
%     pitch 俯仰（绕体 y 轴），roll 横滚（绕体 x 轴），yaw 航向（绕体 z 轴）
%   Cbn                       姿态阵（体→导航）  3×3
%
%   Cbn = Rz(yaw)·Ry(pitch)·Rx(roll)
%       | cy·cp    cy·sp·sr − sy·cr    cy·sp·cr + sy·sr |
%     = | sy·cp    sy·sp·sr + cy·cr    sy·sp·cr − cy·sr |
%       | −sp      cp·sr               cp·cr            |
%   其中 c·=cos(·), s·=sin(·)
%
% ─── 新手备注 ───────────────────────────────────────────────────────
%   · **本库约定（对齐 PSINS）**：att 顺序是 [pitch; roll; yaw]，
%     与很多输出习惯（yaw-pitch-roll）不同，对拍前先重排；
%   · 合成顺序 = "先滚转 → 再俯仰 → 后航向"（体轴内旋，等价于外旋
%     Rz·Ry·Rx）——想象飞机先滚一圈、再抬头、最后转航向，方向就对了；
%   · 自检：att=[0;0;0] → 单位阵；att=[0;0;90°] → 绕 z 转 90°。

% ─── 代码（公式 2.5 逐行）───────────────────────────────────────────
sp = sin(att(1));  cp = cos(att(1));   % 俯仰角正/余弦（公式 2.5 的 sp, cp）
sr = sin(att(2));  cr = cos(att(2));   % 横滚角正/余弦
sy = sin(att(3));  cy = cos(att(3));   % 航向角正/余弦
Cbn = [cy*cp,             cy*sp*sr - sy*cr,  cy*sp*cr + sy*sr;  % 第 1 行
       sy*cp,             sy*sp*sr + cy*cr,  sy*sp*cr - cy*sr;  % 第 2 行
       -sp,               cp*sr,             cp*cr];            % 第 3 行
end
