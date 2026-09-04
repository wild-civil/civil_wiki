#include "KFApp.h"

void Mahony_main(void);						// Example-1
void SINSGPS_static_main(void);		// Example-2
void SINSGPS_moving_main(void);		// Example-3
void GPSCFG_main(void);						// Example-4

struct PCCMD {
	u16 cmd1,cmd2;
} *pcmd=(PCCMD*)&PC_cmd;
CVect3 wm, vm, eb, db;

int main(void)
{
	eb = CVect3(-4.0,1.3,0.0)*DPS;  // 陀螺零偏 deg/s
	db = O31;                       // 加计零偏，暂设0
	
	mcu_init();                     // mcu_init() 之后，三个中断就开始独立工作，一直在后台跑
	pcmd->cmd1 = 0; pcmd->cmd2 = 0x1111; // 选模式
	while(1)	{
		switch(pcmd->cmd2)	{
				case 0x1111:	pcmd->cmd2=0;	outFrame.head=0x56aa55aa; Mahony_main(); break;
				case 0x2222:	pcmd->cmd2=0;	outFrame.head=0x57aa55aa; SINSGPS_static_main(); break;
				case 0x3333:	pcmd->cmd2=0;	outFrame.head=0x58aa55aa; SINSGPS_moving_main(); break;
				case 0x4444:	pcmd->cmd2=0;	GPSCFG_main(); break;
		}
	}
	return 0;
}

/**
 *@brief：中断100Hz采数据 → 置flag → 主循环poll到flag → 跑算法 → flag清零 → 等下一次
 */
void Mahony_main(void)
{
	CMahony mahony(10.0); // 创建AHRS对象，tau=10s
	
	USART1_Configuration(0);
	while(1)
	{
		if(pcmd->cmd1==0xa5a5) { pcmd->cmd1=0; break; } // PC发命令退出
		if(GAMT_OK_flag==0) continue; // ★ 等中断给标志位 GAMT_OK_flag为0则直接跳回while开头，不往下走
		GAMT_OK_flag = 0;             // 能走到这行，说明flag一定=1，现在把它清零 取走标志，开始处理 
		// C数组mpu_Data_value.Gyro → 强转成C++的CVect3 double[3] → CVect3
		wm = (*(CVect3*)mpu_Data_value.Gyro*glv.dps-eb)*TS; //   陀螺ω→  ×°/s转弧度/s → 减零偏 → ×TS得角增量
		vm = (*(CVect3*)mpu_Data_value.Accel*glv.g0-db)*TS; //  加速度g →  ×9.78 m/s2   → 减零偏 → ×TS得速度增量
		mahony.Update(wm, vm, TS);
		AVPUartOut(q2att(mahony.qnb)); // 四元数→欧拉角→打包outFrame
		MainProcessDone(); // 标记完成(调试用)
	}
}

///////////////////////////////////////////////////////////////////////////
void SINSGPS_static_main(void)
{
	CKFApp kf(TS);

//	CVect3 gpspos=LLH(34.2485845,108.910097,403.0), gpsvn=O31;  // MyHome pos
	CVect3 gpspos=LLH(34.228022,108.880422,422.0), gpsvn=O31;  // JingZhun pos
	kf.Init(CSINS(O31, gpsvn, gpspos));      // 请正确初始化位置
		 
	USART1_Configuration(0);
	while(1)
	{
		if(pcmd->cmd1==0xa5a5) { pcmd->cmd1=0; break; }
		if(GAMT_OK_flag==0) continue;
		GAMT_OK_flag = 0;
		wm = (*(CVect3*)mpu_Data_value.Gyro*DPS-eb)*TS;
		vm = (*(CVect3*)mpu_Data_value.Accel*G0-db)*TS;
		if(GPS_OK_flag)
		{
			GPS_OK_flag = 0;
			if(gps_Data_value.GPS_numSV>6&&gps_Data_value.GPS_pDOP<5.0f)
			{
				CVect3 gpos = *(CVect3*)gps_Data_value.GPS_Pos, gvn = *(CVect3*)gps_Data_value.GPS_Vn;
				kf.SetMeasGNSS(gpos, gvn);
			}
		}
		if(GPS_Delay/10000>10 && MCU_ms_cnt%250==0)  // if GPS lost, using fix position
		{
			kf.SetMeasGNSS(gpspos, CVect3(0,0,0.01));
		}
		kf.Update(&wm, &vm, 1, TS, 5);		// 5steps ~= 2ms
		AVPUartOut(kf);
		MainProcessDone();
	}
}

///////////////////////////////////////////////////////////////////////////
void SINSGPS_moving_main(void)
{
	CKFApp kf(TS);

	int yawinit = 0;
	kf.Init(CSINS(O31, O31, posNWPU));
		 
	USART1_Configuration(0);
	while(1)
	{
		if(pcmd->cmd1==0xa5a5) { pcmd->cmd1=0; break; }
		if(GAMT_OK_flag==0) continue;
		GAMT_OK_flag = 0;
		wm = (*(CVect3*)mpu_Data_value.Gyro*DPS-eb)*TS;
		vm = (*(CVect3*)mpu_Data_value.Accel*G0-db)*TS;
		if(GPS_OK_flag)
		{
			GPS_OK_flag = 0;
			if(gps_Data_value.GPS_numSV>6&&gps_Data_value.GPS_pDOP<5.0f)
			{
				CVect3 gpos = *(CVect3*)gps_Data_value.GPS_Pos, gvn = *(CVect3*)gps_Data_value.GPS_Vn;
				if(yawinit) {
					kf.posGNSSdelay = kf.vnGNSSdelay = -outFrame.GPS_delay;
					kf.SetMeasGNSS(gpos, gvn);
				}
				else	{
					if(normXY(gvn)>3.0)	{  // if vel>3.0m/s, init yaw by tracking angle
						kf.Init(CSINS(a2qua(CVect3(0.0,0.0,atan2(-gvn.i,gvn.j))), gvn, gpos));
						yawinit = 1;	continue; }
				}
			}
		}
		if(yawinit) kf.Update(&wm, &vm, 1, TS, 5);		// 5steps ~= 2ms
		AVPUartOut(kf);
		MainProcessDone();
	}
}

///////////////////////////////////////////////////////////////////////////
void GPSCFG_main(void)
{
	USART1_Configuration(1);
	while(1)	{
		if(pcmd->cmd1==0xa5a5) { pcmd->cmd1=0; break; }
	}
}
