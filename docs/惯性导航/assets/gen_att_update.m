% gen_att_update.m — PSINS 轨：圆锥运动下 6 种姿态更新方法误差对比
% 用法: matlab -batch "run('gen_att_update.m')"
% 依赖: PSINS (glvs / conesimu / cnscl / qupdt / rv2q / qrk4 / btzrk4 / btzpicard / dcmtaylor)
% 输出: att_update_compare.png（3 子图误差曲线）+ att_update_res.csv（误差数据，供 Python 对照）
% 对应 wiki: 惯性导航/02_解算篇/07_姿态更新算法.md
addpath('D:/WorkSpace/Code/MATLAB/psins260705/base');
glvs;
[nn, ts, nts] = nnts(4, 0.01);   % 4 子样, 采样 100Hz
afa = 90*glv.deg;  f = 2;  T = 1;   % 圆锥运动: 半锥角90°, 2Hz, 1s
[wm, qr] = conesimu(afa, f, ts, T);  % 生成角增量 + 解析真值四元数
len = length(wm); res = zeros(fix(len/nn), 18);
q1 = qr(1,:)'; q2 = q1; q3 = q1; q4 = q1; q5 = q1; q6 = q1; ki = 1;
for k=1:nn:len-nn+1
    k1 = k+nn-1;
    wmi = wm(k:k1, :);  q0 = qr(k1+1,:)';
    phim = cnscl(wmi, 1);  q1 = qmul(q1, rv2q(phim));   % 1 最优 coning 补偿
    phim = cnscl(wmi, 2);  q2 = qmul(q2, rv2q(phim));   % 2 未补偿(单子样)
    q3 = qrk4(q3, wmi, nts);                             % 3 四元数 RK4
    q4 = qmul(q4, rv2q(btzrk4(wmi, nts)));               % 4 Bortz RK4
    q5 = qmul(q5, rv2q(btzpicard(wmi'*wm2wtcoef(ts,nn), nts)));  % 5 Bortz Picard
    q6 = qmul(q6, m2qua(dcmtaylor(wmi'*wm2wtcoef(ts,nn), nts))); % 6 DCM Taylor
    res(ki,:) = [qq2phi(q1,q0); qq2phi(q2,q0); qq2phi(q3,q0); qq2phi(q4,q0); qq2phi(q5,q0); qq2phi(q6,q0)]';
    ki = ki+1;
end
% 保存数据供 Python 对照（列: 6 方法 x 3 轴误差, 单位 arcsec）
dlmwrite('att_update_res.csv', [ (1:size(res,1))'*nts, res/glv.sec ], 'precision', '%.8e');
% 出图
fig = figure('Visible','off','Position',[100 100 900 300]);
t = (1:size(res,1))*nts;
methods = {'1 最优coning','2 未补偿','3 四元数RK4','4 BortzRK4','5 BortzPicard','6 DCMTaylor'};
clrs = {'b','r','g','m','c','k'};
subplot(131); hold on; grid on;
for j=1:6, plot(t, res(:,3*(j-1)+1)/glv.sec, clrs{j}, 'LineWidth',1.5); end
xlabel('t/s'); ylabel('\phi_x / arcsec'); title('x 轴误差 (圆锥运动)');
subplot(132); hold on; grid on;
for j=1:6, plot(t, res(:,3*(j-1)+2)/glv.sec, clrs{j}, 'LineWidth',1.5); end
xlabel('t/s'); ylabel('\phi_y / arcsec'); title('y 轴误差');
subplot(133); hold on; grid on;
for j=1:6, plot(t, res(:,3*(j-1)+3)/glv.sec, clrs{j}, 'LineWidth',1.5); end
xlabel('t/s'); ylabel('\phi_z / arcsec'); title('z 轴误差');
legend(methods, 'Location','best', 'FontSize',7);
saveas(fig, 'att_update_compare.png');
fprintf('saved att_update_compare.png + att_update_res.csv (len=%d, nn=%d)\n', len, nn);
