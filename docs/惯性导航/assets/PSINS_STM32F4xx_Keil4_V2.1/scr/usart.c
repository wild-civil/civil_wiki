#include "main.h"

#define DEG1 (3.141592653589793/180.0)

u8 GPS_send_once=0;

void GPS_PVT_Decode(void)
{
	s32 GPS_temp;
	
	gps_Data_value.GPS_ITOW=(u32)((Rx2_data[9]<<24)+(Rx2_data[8]<<16)+(Rx2_data[7]<<8)+Rx2_data[6]);
	///////////////////////////////////////////////////GPS_vleE/N/U	
	GPS_temp=((Rx2_data[61]<<24)+(Rx2_data[60]<<16)+(Rx2_data[59]<<8)+(Rx2_data[58]));
	gps_Data_value.GPS_Vn[0]=GPS_temp/1000.0;
	GPS_temp=((Rx2_data[57]<<24)+(Rx2_data[56]<<16)+(Rx2_data[55]<<8)+(Rx2_data[54]));
	gps_Data_value.GPS_Vn[1]=GPS_temp/1000.0;
	GPS_temp=((Rx2_data[65]<<24)+(Rx2_data[64]<<16)+(Rx2_data[63]<<8)+(Rx2_data[62]));
	gps_Data_value.GPS_Vn[2]=GPS_temp/-1000.0;
	///////////////////////////////////////////////////GPS_Lon/Lat/Hgt
	GPS_temp=((Rx2_data[33]<<24)+(Rx2_data[32]<<16)+(Rx2_data[31]<<8)+(Rx2_data[30]));
	gps_Data_value.GPS_Pos[1]=GPS_temp*DEG1/10000000.0;
	GPS_temp=((Rx2_data[37]<<24)+(Rx2_data[36]<<16)+(Rx2_data[35]<<8)+(Rx2_data[34]));
	gps_Data_value.GPS_Pos[0]=GPS_temp*DEG1/10000000.0;
  GPS_temp=((Rx2_data[45]<<24)+(Rx2_data[44]<<16)+(Rx2_data[43]<<8)+(Rx2_data[42]));
	gps_Data_value.GPS_Pos[2]=GPS_temp/1000.0;

	GPS_temp=((Rx2_data[73]<<24)+(Rx2_data[72]<<16)+(Rx2_data[71]<<8)+(Rx2_data[70]));//headMot
	gps_Data_value.GPS_Mot=GPS_temp/100000.0;
	if(gps_Data_value.GPS_Mot>180.0)
	{
		gps_Data_value.GPS_Mot -= 360.0;
	}
	gps_Data_value.GPS_Mot*=DEG1;
	gps_Data_value.GPS_fixType=Rx2_data[26]&0x07;//GPS_fixType
	gps_Data_value.GPS_flags=Rx2_data[27]&0x01;//GPS_flags
	gps_Data_value.GPS_numSV=Rx2_data[29];//GPS_numSV

	GPS_temp=((Rx2_data[83]<<24)+(Rx2_data[82]<<16))>>16; //GPS_pDOP	
	gps_Data_value.GPS_pDOP=GPS_temp/100.0;
	
	GPS_temp=((Rx2_data[49]<<24)+(Rx2_data[48]<<16)+(Rx2_data[47]<<8)+(Rx2_data[46]));
	gps_Data_value.GPS_hAcc=GPS_temp/1000.0;
	GPS_temp=((Rx2_data[53]<<24)+(Rx2_data[52]<<16)+(Rx2_data[51]<<8)+(Rx2_data[50]));
	gps_Data_value.GPS_vAcc=GPS_temp/1000.0;
	GPS_temp=((Rx2_data[81]<<24)+(Rx2_data[80]<<16)+(Rx2_data[79]<<8)+(Rx2_data[78]));
	gps_Data_value.GPS_headAcc=GPS_temp/100000.0;
	GPS_temp=((Rx2_data[77]<<24)+(Rx2_data[76]<<16)+(Rx2_data[75]<<8)+(Rx2_data[74]));
	gps_Data_value.GPS_sAcc=GPS_temp/1000.0;
	GPS_temp=((Rx2_data[69]<<24)+(Rx2_data[68]<<16)+(Rx2_data[67]<<8)+(Rx2_data[66]));
	gps_Data_value.GPS_gSpeed=GPS_temp/1000.0;
	GPS_send_once = 1;
}

void Uart1_Out_Frame(void)
{
	float Data_F, *pf;
	double Data_D;
	u32 Data_U;
	u8 *pcheck, i;

//	outFrame.head=0x56aa55aa;
	outFrame.t=(float)(MCU_ms_cnt/1000.0f);
	outFrame.Gyro[0]=(float)mpu_Data_value.Gyro[0];
	outFrame.Gyro[1]=(float)mpu_Data_value.Gyro[1];
	outFrame.Gyro[2]=(float)mpu_Data_value.Gyro[2];
	
	outFrame.Accel[0]=(float)(mpu_Data_value.Accel[0]*9.8f);
	outFrame.Accel[1]=(float)(mpu_Data_value.Accel[1]*9.8f);
	outFrame.Accel[2]=(float)(mpu_Data_value.Accel[2]*9.8f);
	
	outFrame.Magn[0]=(float)mpu_Data_value.Mag[0];
	outFrame.Magn[1]=(float)mpu_Data_value.Mag[1];
	outFrame.Magn[2]=(float)mpu_Data_value.Mag[2];
	
	outFrame.mBar=(float)(mpu_Data_value.Pressure);
	
	if(GPS_send_once==1)
	{
		outFrame.GPS_Vn[0]=(float)(gps_Data_value.GPS_Vn[0]);
		outFrame.GPS_Vn[1]=(float)(gps_Data_value.GPS_Vn[1]);
		outFrame.GPS_Vn[2]=(float)(gps_Data_value.GPS_Vn[2]);
		
		Data_D=gps_Data_value.GPS_Pos[1]/DEG1;
		Data_U=(u32)Data_D;
		Data_F=(float)(Data_D-(double)Data_U);
		outFrame.GPS_Pos[0]=(float)Data_U;
		outFrame.GPS_Pos[1]=Data_F;
		
		Data_D=gps_Data_value.GPS_Pos[0]/DEG1;
		Data_U=(u32)Data_D;
		Data_F=(float)(Data_D-(double)Data_U);
		outFrame.GPS_Pos[2]=(float)Data_U;
		outFrame.GPS_Pos[3]=Data_F;
		
		outFrame.GPS_Pos[4]=(float)gps_Data_value.GPS_Pos[2];
		
		if(gps_Data_value.GPS_pDOP>99) {gps_Data_value.GPS_pDOP=99;}
		outFrame.GPS_status=(float)gps_Data_value.GPS_numSV+gps_Data_value.GPS_pDOP/100.0f;
		
		outFrame.GPS_delay=GPS_Delay/10000.0f;   // in s
		if(outFrame.GPS_delay<1.0)
		{
			if(outFrame.GPS_delay>0.75) outFrame.GPS_delay-=0.75;
			else if(outFrame.GPS_delay>0.5) outFrame.GPS_delay-=0.5;
			else if(outFrame.GPS_delay>0.25) outFrame.GPS_delay-=0.25;
		}
		
		GPS_send_once=0;
	}
	else
	{
		outFrame.GPS_Vn[0]=outFrame.GPS_Vn[1]=outFrame.GPS_Vn[2]=0.0f;
		outFrame.GPS_Pos[0]=outFrame.GPS_Pos[1]=outFrame.GPS_Pos[2]=outFrame.GPS_Pos[3]=outFrame.GPS_Pos[4]=0.0f;
		outFrame.GPS_status=outFrame.GPS_delay=0.0f;
//		for(pf=outFrame.GPS_Vn, i=0; i<8; i++,pf++) { *pf = timtest[i]; }  // for debug test
	}
	outFrame.Temp=mpu_Data_value.Temp;
	
	for(outFrame.chksum=0, pcheck=(u8*)&outFrame.t; pcheck<(u8*)&outFrame.chksum; pcheck++) {
		outFrame.chksum += *pcheck;
	}
}

void MainProcessDone(void)
{
	timtest_debug(5);
}
