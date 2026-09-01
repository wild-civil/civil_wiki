function qnb = quest(ib, in, w)
% quest - Wahba 问题 q-方法（加权最小二乘定姿，Mini-INS M-A）
%
% 对标 PSINS `base/AHRS/angle3d.m` / QUEST 思想，按 Davenport q-方法自写。
% TRIAD 是"硬解"（两矢量、等权、噪声照单全收）；QUEST 是"软解"——
% N≥2 对矢量、可加权，最优意义下最小化 Wahba 损失。
%
% ─── 公式层（Wahba 问题与 Davenport K 矩阵，公式 6.1'）──────────────
%   Wahba 损失：  L(Cbn) = Σ wᵢ·|nᵢ − Cbn·bᵢ|²        （min over Cbn∈SO(3)）
%   姿态轮廓阵：  B = Σ wᵢ·nᵢ·bᵢ'                      （参考 ⊗ 观测）
%   Davenport K 阵（4×4，最大特征值对应的特征向量 = 最优四元数）：
%     K = [ σ,  Z' ]
%         [ Z,  S − σI ]      σ = tr(B)，S = B + B'，Z = Σ wᵢ·(nᵢ×bᵢ)
%   取 K 最大特征值的特征向量 → q*（标量在前，归一化）
%
% ─── 输入/输出 ─────────────────────────────────────────────────────
%   ib / in  3×N 矩阵（N≥2 列观测/参考对，列数须一致）
%   w        N×1 权重（默认全 1；噪声大的对给小权重）
%   qnb      4×1 姿态四元数（体→导航）
%
% ─── 新手备注 ───────────────────────────────────────────────────────
%   · "最小二乘"怎么理解：每对向量都投一票，票多的（权重大）说了算，
%     两票冲突时取折中——不像 TRIAD 无条件牺牲第 2 列的平行分量；
%   · 本实现用 MATLAB 自带 eig 解 4×4 对称阵（基础 MATLAB，零工具箱）；
%     嵌入式上可用 QUEST 幂迭代/雅可比迭代代替，后续 C 移植时再写；
%   · 特征向量符号不定（±q 同一个旋转），统一取 w 分量为正。

if nargin < 3 || isempty(w), w = ones(size(ib, 2), 1); end
n = size(ib, 2);
if size(in, 2) ~= n
    error('quest: ib/in 列数不一致');
end

B = zeros(3, 3);                                 % 姿态轮廓阵（公式 6.1'）
for i = 1:n
    bi = ib(:, i) / norm(ib(:, i));              % 观测归一化
    ni = in(:, i) / norm(in(:, i));              % 参考归一化
    B = B + w(i) * (ni * bi');                   % B += wᵢ·nᵢ·bᵢ'
end

S = B + B';                                      % 对称部分（公式 6.1'）
sigma = trace(B);                                % 迹
Z = [B(2,3) - B(3,2);                            % Z = Σ wᵢ·(nᵢ×bᵢ)
     B(3,1) - B(1,3);
     B(1,2) - B(2,1)];

K = [sigma,  Z';                                 % Davenport K 阵（4×4 对称）
     Z,  S - sigma * eye(3)];

[V, D] = eig(K);                                 % 特征分解（基础 MATLAB）
[~, idx] = max(real(diag(D)));                   % 最大特征值 = Wahba 最优
q = V(:, idx);                                   % 特征向量即四元数（标量在前）
q = q / norm(q);
if q(1) < 0, q = -q; end                         % 符号规范化（w>0，与 cnb2q 一致）

% ⚠️ 约定换算（数值对拍确认，err 1e-15）：Davenport 原生 q* 在 B=Σw·n·b'
% 构造下旋转方向是"参考→体"（nav→body），本库统一体→导航，取共轭：
qnb = qconj(q);                                  % 体→导航四元数（q2cnb 直接可用）
end
