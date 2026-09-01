function mag = magsimu(Cbn, mH, dip, dec, mb, sg)
% magsimu - 磁力计测量仿真：导航系地磁场 → 体坐标输出（Mini-INS M-A）
%
% 与 trjsimu（IMU 正演）配套：trjsimu 反算加计/陀螺，本函数反算磁强计。
%
% ─── 公式层（地磁场模型，公式 6.5）──────────────────────────────────
%   导航系（ENU）地磁向量（mH = 水平强度，dip = 磁倾角，dec = 磁偏角）：
%     m_n = [ mH·sin(dec) ;  mH·cos(dec) ;  −mH·tan(dip) ]
%           ── 东分量        ── 北分量         ── 天分量（北半球 dip>0 → 向下）
%   体坐标测量（无误差时）：mag_b = Cbn' · m_n      （导航向量投到体系）
%   注入误差：mag_b += mb（体磁偏置/硬铁）+ sg·randn（噪声）
%
% ─── 输入/输出 ─────────────────────────────────────────────────────
%   Cbn  3×3 姿态阵（体→导航）或 4×1 四元数（自动转换）
%   mH   水平磁场强度（nT，北京 ~28000；仿真里单位无所谓，一致即可）
%   dip  磁倾角（rad，向下为正；北京 ≈ 58°）
%   dec  磁偏角（rad，东偏为正；北京 ≈ −7°）
%   mb   3×1 体磁偏置（硬铁干扰，默认 0）
%   sg   3×1 或标量 噪声标准差（默认 0，保持确定性）
%   mag  3×1 体坐标磁测量
%
% ─── 新手备注 ───────────────────────────────────────────────────────
%   · dip>0 时天分量取负号：北半球磁力线扎向地面，ENU 的 z 轴朝上，
%     所以地磁向量的 z 分量是负的——这就是"磁倾角"名字的由来；
%   · dec ≠ 0 时磁北 ≠ 真北：Mahony/TRIAD 的参考向量必须用带 dec 的
%     m_n，否则 yaw 会系统性偏一个 dec（软铁/硬铁干扰见 wiki 页）；
%   · 确定性约定：默认 mb=0、sg=0，与全库"随机注入默认关"一致。

glv = glvs();
if nargin < 2 || isempty(mH),  mH  = 28000;              end
if nargin < 3 || isempty(dip), dip = 58 * glv.deg;       end
if nargin < 4 || isempty(dec), dec = 0; end
if nargin < 5 || isempty(mb),  mb  = zeros(3, 1); end
if nargin < 6 || isempty(sg),  sg  = 0; end

if numel(Cbn) == 4                               % 传四元数则先转姿态阵
    Cbn = q2cnb(Cbn);
end

m_n = [mH * sin(dec);                            % 地磁向量（ENU，公式 6.5）
       mH * cos(dec);
       -mH * tan(dip)];

mag = Cbn' * m_n + mb + sg * randn(3, 1);        % 体坐标测量（公式 6.5）
end
