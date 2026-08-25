function [kf, ins] = kffeedback(kf, ins, fb_scale, fb_mode)
% kffeedback - 滤波反馈：把估计出的误差回灌修正 SINS（Mini-INS M4）
%
% 对标 PSINS `base/kf/kffeedback.m`，本库教学版实现 'v'（速度闭环）。
%
% ─── 用法 ─────────────────────────────────────────────────────────
%   [kf, ins] = kffeedback(kf, ins, 1, 'v');
%     fb_scale = 1（反馈系数，一般取 1）
%     fb_mode  = 'v'：仅速度闭环（P4 用的模式）
%
% ─── 'v' 模式做什么（公式 7.3）───────────────────────────────────
%   ins.vn = ins.vn − x(4:6)     % 把估计的 δv 从解算速度里减掉
%   kf.x(4:6) = x(4:6) − x(4:6)  % 只清零"已回灌"的 δv
%                                % （坑 1！其他状态 φ/δr/dKod 继续累积）
%
% ─── 新手备注 ───────────────────────────────────────────────────────
%   · **只清零已回灌的 δv，其余状态跨时间累积**——这是 dKod 等慢参数
%     能被在线辨识的前提（P4 坑 1：若把整个 x 清零，滤波器只剩 0.1s
%     记忆，尺度误差永远辨识不出，组合解 = DR-only）；
%   · 为什么只回灌速度、不回灌姿态/位置？P4 的选择：姿态和位置靠
%     "被修正的速度积分"自然收敛（速度闭环足够抑制 SINS 漂移），
%     避免全闭环的耦合振荡；
%   · 回灌后必须同步清零对应 x 分量，否则同一误差被反复回灌（双倍修正）。

if nargin < 3, fb_scale = 1; end
if nargin < 4, fb_mode = 'v'; end

switch lower(fb_mode)
    case 'v'                                        % 仅速度闭环（公式 7.3）
        xfb = kf.xk(4:6) * fb_scale;                % 本次要回灌的 δv
        ins.vn = ins.vn - xfb;                      % 修正 SINS 速度
        kf.xk(4:6) = kf.xk(4:6) - xfb;              % 清零已回灌（坑 1：其他状态不动）
    otherwise
        error('kffeedback: 未知反馈模式 %s（当前支持 ''v''）', fb_mode);
end
end
