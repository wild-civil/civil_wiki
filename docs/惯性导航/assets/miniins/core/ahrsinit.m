function ahrs = ahrsinit(att0, Kp, Ki, pos0, dec)
% ahrsinit - Mahony AHRS 结构体初始化（Mini-INS 姿态解算 M-A）
%
% 对标 PSINS `base/AHRS/MahonyInit.m`（思路一致，实现按本库约定自写）。
% 返回的 ahrs 结构体供 mahonyupdate 单步推进，与 insupdate/drupdate 同风格。
%
% ─── 公式层（Mahony 互补滤波参数）───────────────────────────────────
%   互补滤波思想：高频信陀螺（积分）、低频信加计/磁（PI 反馈拉回）：
%     e   = 天向误差 + 磁向误差                       （公式 6.2，pred × meas）
%     ė_I = Ki·e                                     （公式 6.3，积分项≈陀螺零偏估计）
%     ω_corr = Kp·e + ė_I                            （公式 6.3，反馈角速度）
%     q⁺ = q ⊗ rv2q(φm − (Cbn'·wnie + ω_corr)·ts)   （公式 6.4，姿态更新）
%
% ─── 输入/输出 ─────────────────────────────────────────────────────
%   att0 = [pitch; roll; yaw]（弧度）   初始姿态，默认 [0;0;0]
%   Kp / Ki                 比例/积分增益，默认 1.0 / 0.3（PSINS 同量级）
%   pos0 = [lat; lon; h]（弧度+米）     位置（算地球自转 wnie 用），默认北京附近
%   dec                      磁偏角（rad，东偏为正），默认 0——磁北≠真北时，
%                            yaw 的磁参考必须按 dec 修正，否则 yaw 系统性
%                            偏差恰为 −dec（verify_ahrs ③ 曾用它暴露此坑）
%   ahrs - 结构体：qnb/Cbn（体→导航）、Kp/Ki、exyzInt（PI 积分项）、
%          wnie（地球自转，ENU）、dec（磁偏角）、g0、tk
%
% ─── 新手备注 ───────────────────────────────────────────────────────
%   · Kp 大 → 加计/磁拉得快、但对机动加速度敏感；Ki 负责把陀螺零偏
%     "吸收"进积分项（稳态时 e→0，ė_I→0，此时 exyzInt 恰好抵消零偏）；
%   · wnie 在初始化时按 pos0 算好（姿态解算不导航，位置近似不动）；
%   · 机体系约定：x 右、y 前、z 上（全库统一，见 README）。

glv = glvs();
if nargin < 1 || isempty(att0), att0 = [0; 0; 0]; end
if nargin < 2 || isempty(Kp),  Kp  = 1.0;           end
if nargin < 3 || isempty(Ki),  Ki  = 0.3;           end
if nargin < 4 || isempty(pos0), pos0 = [29*glv.deg; 106*glv.deg; 450]; end
if nargin < 5 || isempty(dec),  dec  = 0;            end

eth = earth(pos0, [0; 0; 0]);                    % 地球参数（只需 wnie，静态近似）

ahrs.qnb     = a2qua(att0);                      % 初始姿态四元数（体→导航）
ahrs.Cbn     = q2cnb(ahrs.qnb);                  % 姿态阵（体→导航）
ahrs.Kp      = Kp;                               % 比例增益（公式 6.3）
ahrs.Ki      = Ki;                               % 积分增益（公式 6.3）
ahrs.exyzInt = zeros(3, 1);                      % PI 积分项（稳态≈−陀螺零偏，公式 6.3）
ahrs.wnie    = eth.wnie;                         % 地球自转（ENU，公式 3.3）
ahrs.dec     = dec;                              % 磁偏角（mahonyupdate 磁参考用）
ahrs.g0      = glv.g0;                           % 重力常量（准静态门控判据用）
ahrs.pos0    = pos0;                             % 保存初始化位置（可追溯）
ahrs.tk      = 0;                                % 内部时钟（s）
end
