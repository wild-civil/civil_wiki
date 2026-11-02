function ins = insupdate(ins, imu)
% SINS Updating Alogrithm including attitude, velocity and position
% updating.
%
% Prototype: ins = insupdate(ins, imu)
% Inputs: ins - SINS structure array created by function 'insinit'
%         imu - gyro & acc incremental sample(s)
% Output: ins - SINS structure array after updating
%
% See also  insinit, cnscl, earth, inspure, trjsimu, imuadderr, avpadderr, q2att,
%           inslever, alignvn, aligni0, etm, kffk, kfupdate, insplot.

% Copyright(c) 2009-2014, by Gongmin Yan, All rights reserved.
% Northwestern Polytechnical University, Xi An, P.R.China
% 22/03/2008, 12/01/2013, 18/03/2014, 09/09/2014
global glv
    nn = size(imu,1);
    nts = nn*ins.ts;  nts2 = nts/2;  ins.nts = nts;
    [phim, dvbm] = cnscl(imu,0);    % coning & sculling compensation 圆锥(coning)+划桨(sculling)补偿
    phim = ins.Kg*phim-ins.eb*nts; dvbm = ins.Ka*dvbm-ins.db*nts;  % calibration 标定/扣零偏
    %% earth & angular rate updating 
    vn01 = ins.vn+ins.an*nts2; pos01 = ins.pos+ins.Mpv*vn01*nts2;  % extrapolation at t1/2 用 "半步" 外推出中点 v, pos
    if ins.openloop==0, ins.eth = ethupdate(ins.eth, pos01, vn01); % 用中点值刷 eth(ω_ie/ω_en/g/R). 注意 eth 不是用"更新完的新值"刷的，是用"外推到半拍的中点值"刷的
    elseif ins.openloop==1, ins.eth = ethupdate(ins.eth, ins.pos0, ins.vn0); end
    ins.wib = phim/nts; ins.fb = dvbm/nts;  % same as trjsimu % 增量→变化率(供KF等使用)
    ins.web = ins.wib - ins.Cnb'*ins.eth.wnie;  ins.wbar = 0.9*ins.wbar + 0.1*ins.web; % ω_eb^b = ω_ib^b − C_n^b·ω_ie^n，一阶低通（IIR）
%     ins.wnb = ins.wib - ins.Cnb'*ins.eth.wnin;
    ins.wnb = ins.wib - (ins.Cnb*rv2m(phim/2))'*ins.eth.wnin;  % 2014-11-30 ω_nb 投影用【姿态中点】rv2m(phim/2)
    %% (1)velocity updating             ← 先用旧姿态，但划桨已兜住"姿态在区间内动了"
    ins.fn = qmulv(ins.qnb, ins.fb); % 旧姿态投影 dvbm(含划桨修正)
%     ins.an = qmulv(rv2q(-ins.eth.wnin*nts2),ins.fn) + ins.eth.gcc;
    ins.an = rotv(-ins.eth.wnin*nts2, ins.fn) + ins.eth.gcc;  ins.anbar = 0.9*ins.anbar + 0.1*ins.an; % fn 旋转到中点时刻 + gcc(重力+哥氏/牵连)  然后低通滤波
%    ins.an(1:2)=ins.an(1:2)-2*0.207*glv.ws*ins.vn(1:2);
    vn1 = ins.vn + ins.an*nts; % 速度更新
    %% (2)position updating
%     ins.Mpv = [0, 1/ins.eth.RMh, 0; 1/ins.eth.clRNh, 0, 0; 0, 0, 1];
    ins.Mpv(4)=1/ins.eth.RMh; ins.Mpv(2)=1/ins.eth.clRNh;
%     ins.Mpvvn = ins.Mpv*((ins.vn+vn1)/2+(ins.an-ins.an0)*nts^2/3);  % 2014-11-30
    ins.Mpvvn = ins.Mpv*(ins.vn+vn1)/2; % 旧v与新v的【梯形平均】
    ins.pos = ins.pos + ins.Mpvvn*nts;  
    ins.vn = vn1;
    ins.an0 = ins.an;
    %% (3)attitude updating
    ins.Cnb0 = ins.Cnb;
%     ins.qnb = qupdt(ins.qnb, ins.wnb*nts);  % lower accuracy than the next line
    ins.qnb = qupdt2(ins.qnb, phim, ins.eth.wnin*nts); % q=rv2q(-rv_in)⊗q⊗rv2q(phim)
    [ins.qnb, ins.att, ins.Cnb] = attsyn(ins.qnb);
    ins.avp = [ins.att; ins.vn; ins.pos];

