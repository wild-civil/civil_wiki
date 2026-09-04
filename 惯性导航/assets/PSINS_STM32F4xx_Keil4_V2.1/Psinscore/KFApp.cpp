#include "KFApp.h"

/***************************  class CKFApp  *********************************/
CKFApp::CKFApp(double ts):CSINSGNSS(19, 6, ts)
{
//state: 0-2 phi; 3-5 dvn; 6-8 dpos; 9-11 eb; 12-14 db; 15-17 lever; 18 dt
//meas:  0-2 dvn; 3-5 dpos
	SetCalcuBurden(100,-1);
}

void CKFApp::Init(const CSINS &sins0, int grade)
{
	CSINSGNSS::Init(sins0);
	Pmax.Set2(fPHI(600,600),  fXXX(500),  fdPOS(1e6),  fDPH3(5000),  fMG3(10), fXXX(10),  0.1);
	Pmin.Set2(fPHI(1,10.0),  fXXX(0.01),  fdPOS(0.1),  fDPH3(50.0),  fUG3(500), fXXX(0.01),  0.0001);
	Pk.SetDiag2(fPHI(600,600),  fXXX(1.0),  fdPOS(200.0),  fDPH3(1000),  fMG3(10.0), fXXX(1.0),  0.01);
	Qt.Set2(fDPSH3(10.1),  fUGPSHZ3(100.0),  fOOO,  fOO6,	fOOO, 0.0);
	Rt.Set2(fXXZ(0.5,1.0),   fdLLH(10.0,30.0));
	Rmax = Rt*100;  Rmin = Rt*0.01;  Rb = 0.6;
	FBTau.Set(fXX9(0.1),  fXX6(1.0),  fINF3, INF);
}

void AVPUartOut(const CKFApp &kf)
{
	AVPUartOut(kf.sins.att, kf.sins.vn, kf.sins.pos);
}

void AVPUartOut(const CVect3 &att, const CVect3 &vn, const CVect3 &pos)
{
	outFrame.Att[0] = att.i/DEG; outFrame.Att[1] = att.j/DEG; outFrame.Att[2] = CC180C360(att.k)/DEG;
	outFrame.Vn[0] = vn.i; outFrame.Vn[1] = vn.j; outFrame.Vn[2] = vn.k;
	int deg;
	deg = (int)(pos.j/DEG);
	outFrame.Pos[0] = deg;  outFrame.Pos[1] = pos.j/DEG-deg;
	deg = (int)(pos.i/DEG);
	outFrame.Pos[2] = deg;  outFrame.Pos[3] = pos.i/DEG-deg;
	outFrame.Pos[4] = pos.k;		
}
