function eth = earth(pos, vn)
% earth - 地球参数：曲率半径 / 自转分量 / 运动旋转 / 重力（ENU，新手可读版）
%
% ─── 公式 3.x（符号表）─────────────────────────────────────────────
%   pos  = [lat; lon; h]  位置（lat/lon 弧度，h 米）  3×1
%   vn   = [vE; vN; vU]   速度（ENU）                3×1
%
%   RMh = Re(1−e²)/(1−e²·sin²L)^1.5 + h    子午圈曲率半径（南北向）  公式 3.1
%   RNh = Re/√(1−e²·sin²L) + h             卯酉圈曲率半径（东西向）  公式 3.2
%   wnie = [0; ωie·cosL; ωie·sinL]         地球自转在导航系分量       公式 3.3
%   wnen = [−vN/RMh; vE/RNh; vE·tanL/RNh]  载体运动引起导航系旋转    公式 3.4
%   wnin = wnie + wnen                     导航系相对惯性系角速度     公式 3.5
%   gcc  = gn − (2·wnie + wnen) × vn       重力+哥氏+向心合成（比力方程用）公式 3.6
%
% ─── 新手备注 ───────────────────────────────────────────────────────
%   · 曲率半径：地球是椭球，南北走"子午圈"（RM 小）、东西走"卯酉圈"
%     （RN 大），位置微分和 wnen 都靠它们把"米"换算成"弧度变化"；
%   · wnie 是地球自转在导航系的分量（纬度越高，自转轴的投影越偏向
%     垂直）；wnen 是"你在球面上移动导致导航系跟着转"；
%   · **gcc 是比力方程的关键**：加计测的是比力 f，要得到运动加速度 a
%     必须 f + gcc（gcc 里"−2wnie×v"是哥氏、"−wnen×v"是向心）；静止时
%     f=−gn → a=0（[P2 机械编排 ④](P2_纯惯导_拆解test_SINS.md) 互逆）。
%   · 教学简化：重力用 g0 常数（严格版有纬度/高度修正，见 PSINS eth.m）。

% ─── 代码（公式 3.1–3.6 逐行）───────────────────────────────────────
glv = glvs();                          % 取地球常量（本库不强制 global）
lat = pos(1);  h = pos(3);                 % 纬度（弧度）、高度（米）
sl = sin(lat);  cl = cos(lat);             % 纬度的正/余弦
e2 = glv.e^2;                              % 第一偏心率平方

% --- 曲率半径（公式 3.1、3.2）---
tmp = 1 - e2*sl*sl;                        % 中间量 1−e²sin²L（两式共用）
RMh = glv.Re*(1-e2) / tmp^1.5 + h;         % 子午圈半径 + 高度（公式 3.1）
RNh = glv.Re / sqrt(tmp) + h;              % 卯酉圈半径 + 高度（公式 3.2）

% --- 角速度（公式 3.3、3.4、3.5）---
wnie = [0; glv.wie*cl; glv.wie*sl];        % 自转分量（公式 3.3）
wnen = [-vn(2)/RMh; vn(1)/RNh; vn(1)*tan(lat)/RNh];  % 运动旋转（公式 3.4）
wnin = wnie + wnen;                        % 合成（公式 3.5）

% --- 重力合成（公式 3.6）---
gn = [0; 0; -glv.g0];                      % ENU 下重力向下 = −z
gcc = gn - cross(2*wnie + wnen, vn);       % 重力+哥氏+向心（公式 3.6）

% --- 打包输出 ---
eth = struct('RMh',RMh, 'RNh',RNh, 'clRNh',cl*RNh, 'wnie',wnie, 'wnen',wnen, ...
             'wnin',wnin, 'gn',gn, 'gcc',gcc, 'lat',lat, 'h',h);
% clRNh = cosL·RNh（东向位置微分 dlon=dE/clRNh 常用；M4 起 odsimu/drupdate 用它）
end
