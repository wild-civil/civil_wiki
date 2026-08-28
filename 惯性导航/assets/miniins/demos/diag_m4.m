function diag_m4()
% diag_m4 - 组合链关键量诊断（定位 MATLAB 组合 267 vs P4 参考 45.5 的差异）
%
% 与 Python 参考（kffk.m 逐行翻译 + P4 主循环）同格式打印量测时刻的
% z / xk(φ·δv·δr) / dKod / dT——逐行对比即可定位差异来源。
%
% 运行：cd docs/惯性导航/assets/miniins/demos; diag_m4
% 参考（Python 45.5 版）关键值：
%   量测#9500 t=950s: z=[-313.6,+84.5,+50.8]m | φ≈+1085,+609,+1159" | δr≈-269,-249,+179m | dKod=+0.1002 | dT=-75.7ms

addpath(fullfile(fileparts(mfilename('fullpath')), '..', 'core'));
glv = glvs();  deg = glv.deg;  dph = deg/3600;  ug = 1e-6*glv.g0;
ts = 0.01;  nn = 2;  nts = nn*ts;

WAT = [ 100,  0,  0,          0,      0,         0,      0,      0;
         10,  0,  0,          0,      0,         0,      1,      0;
        100, 10,  0,          0,      0,         0,      0,      0;
          4, 10,  0, -0.51*deg,      0,         0,      0,      0;
         45, 10,  0,          0, 2.00*deg, -0.349,      0,      0;
          4, 10,  0,  0.51*deg,      0,         0,      0,      0;
        100, 10,  0,          0,      0,         0,      0,      0;
          4, 10,  0,  2.28*deg,      0,         0,      0,      0;
         50, 10,  0,          0,-9.00*deg,  1.571,      0,      0;
          4, 10,  0, -2.28*deg,      0,         0,      0,      0;
        100, 10,  0,          0,      0,         0,      0,      0;
         10, 10, 2.00*deg,    0,      0,         0,      0, 0.349;
         50, 10,  0,          0,      0,         0,      0,      0;
         10, 10,-2.00*deg,    0,      0,         0,      0,-0.349;
        100, 10,  0,          0,      0,         0,      0,      0;
         10, 10,-2.00*deg,    0,      0,         0,      0,-0.349;
         50, 10,  0,          0,      0,         0,      0,      0;
         10, 10, 2.00*deg,    0,      0,         0,      0, 0.349;
        100, 10,  0,          0,      0,         0,      0,      0;
          5, 10,  0,          0,      0,         0,     -2,      0;
        100,  0,  0,          0,      0,         0,      0,      0];
avp0 = [0;0;0; 0;0;0; 29*deg; 106*deg; 450.0];
trj = trjsimu(avp0, WAT, ts);
od  = odsimu(trj, zeros(3,1), 1.0);

eb   = [0.01; 0.01; 0.01]*dph;
db   = [100; 100; 100]*ug;
davp = [0.5; 0.5; 5.0]*(deg/60);
imu_e = trj.imu;
imu_e(:,1:3) = imu_e(:,1:3) + (eb*ts)';
imu_e(:,4:6) = imu_e(:,4:6) + (db*ts)';
avp0e = [avp0(1:3)+davp; 0.1;0.1;0.1; ...
         avp0(7)+10/glv.Re; avp0(8)+10/(glv.Re*cos(avp0(7))); avp0(9)+10];
dinst = [15; 0; 10]*(deg/60);
dkod  = 0.05;

N = 22;
web = (0.001*deg)/sqrt(3600);
wdb = 5e-6*glv.g0/sqrt(1.0);
Qk = diag([repmat(web^2,3,1); repmat(wdb^2,3,1); repmat(1e-14,16,1)]);
Rk = diag([(10/glv.Re)^2; (10/glv.Re)^2; 10^2]);
dposP0 = [(100/glv.Re)^2; (100/glv.Re)^2; 100^2];
P0 = diag([(davp*10).^2; zeros(3,1); dposP0; (eb*10).^2; (db*10).^2; dposP0; ...
           (dinst([1;3])*10).^2; (dkod*10)^2; (0.01*10)^2]);
kf = kfinit(N, ts);
kf.Pk = P0;  kf.Qk = Qk;  kf.Rk = Rk;  kf.xk = zeros(N,1);

ins = data_classes('ins');
ins.qnb = a2qua(avp0e(1:3));  ins.vn = avp0e(4:6);  ins.pos = avp0e(7:9);
dr  = drinit(avp0e, dinst, 1.0*(1+dkod), ts);
m = floor(trj.len/nn);
nmeas = 0;
for ki = 1:m
    k = (ki-1)*nn + 1;
    wm = imu_e(k:k+1, 1:3);  vm = imu_e(k:k+1, 4:6);
    ins = insupdate(ins, wm, vm, ts);
    dr.qnb = ins.qnb;
    dS = od(k,1) + od(k+1,1);
    dr = drupdate(dr, wm, dS);
    kf.Phikk_1 = kffk(ins);
    kf.Pk = kf.Phikk_1 * kf.Pk * kf.Phikk_1' + kf.Qk;   % 只推 P（对齐 P4 kf_predict）
    if mod(ki, 5) == 0
        z = ins.pos - dr.pos;
        H = zeros(3, N);
        H(1:3,7:9)   =  eye(3);
        H(1:3,16:18) = -eye(3);
        RMh = ins.eth.RMh;  RNh = ins.eth.RNh;
        Mpvvn = [ins.vn(2)/RMh; ins.vn(1)/(RNh*cos(ins.pos(1))); ins.vn(3)];
        H(1:3,22) = -Mpvvn;
        % ★ 量测更新前保存预测态 xk（诊断：xfb = xk_pred(4:6)+K·(z−H·xk_pred)）
        x_pred = kf.xk;
        kf.Hk = H;
        % ★ 量测更新前手动算 K（kfupdate 内部不返回）——诊断用
        PHT = kf.Pk * H';
        S = H * PHT + kf.Rk;
        K = PHT / S;                          % 22×3
        K6 = K(6,:)';                         % K 第 6 行（δvU 增益）
        kf = kfupdate(kf, z);
        xfb = kf.xk(4:6);
        xfb_fb = xfb;                        % 保存反馈量（清零前）
        ins.vn = ins.vn - xfb;
        kf.xk(4:6) = 0;
        nmeas = nmeas + 1;
        if nmeas <= 5 || (nmeas >= 100 && mod(nmeas, 50) == 0)
            zm = [z(1)*glv.Re; z(2)*glv.Re*cos(avp0(7)); z(3)];
            fprintf('量测#%d t=%7.1fs | z(m)=[%+9.2f,%+9.2f,%+8.2f] | ', ...
                nmeas, trj.imu(k+1,7), zm(1), zm(2), zm(3));
            fprintf('xfb(m/s)=%+.4f,%+.4f,%+.4f | ', xfb_fb(1), xfb_fb(2), xfb_fb(3));
            fprintf('x_pred(δv)=%+.6f,%+.6f,%+.6f | ', x_pred(4), x_pred(5), x_pred(6));
            fprintf('K6=[%+.3e,%+.3e,%+.3e] | ', K6(1), K6(2), K6(3));
            fprintf('xk(φ)=%+.1f,%+.1f,%+.1f" | ', ...
                kf.xk(1)/deg*3600, kf.xk(2)/deg*3600, kf.xk(3)/deg*3600);
            fprintf('xk(δv)=%+.3f,%+.3f,%+.3f | ', kf.xk(4), kf.xk(5), kf.xk(6));
            fprintf('δr(m)=%+.1f,%+.1f,%+.1f | ', ...
                kf.xk(7)*glv.Re, kf.xk(8)*glv.Re*cos(avp0(7)), kf.xk(9));
            fprintf('P66=%+.3e P67=%+.3e P69=%+.3e P6D=%+.3e,%+.3e,%+.3e P622=%+.3e | dKod=%+.4f dT=%+.1fms\n', ...
                kf.Pk(6,6), kf.Pk(6,7)*glv.Re, kf.Pk(6,9), ...
                kf.Pk(6,16)*glv.Re, kf.Pk(6,17)*glv.Re*cos(avp0(7)), kf.Pk(6,18), ...
                kf.Pk(6,22), ...
                kf.xk(21), kf.xk(22)*1000);
        end
    end
end
fprintf('（参考：量测#9500 t=950s: z=[-313.6,+84.5,+50.8]m | φ≈+1085,+609,+1159" | δr≈-269,-249,+179m | dKod=+0.1002 | dT=-75.7ms）\n');
end
