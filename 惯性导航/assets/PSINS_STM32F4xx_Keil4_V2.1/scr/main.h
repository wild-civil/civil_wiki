#ifndef __MAIN_H
#define __MAIN_H

#include "mcu_init.h"
#include "stm32f4xx.h"
#include "arm_math.h" 
#include "stm32f4xx_it.h"
#include "mpu9250.h"

extern MPU_AD_value		mpu_AD_value;
extern MPU_Data_value mpu_Data_value;
extern GPS_Data_value gps_Data_value; 
extern Out_Frame			outFrame;

extern u8 MS5611_cnt;

extern u8 mcu_init_gpscfg;

extern u8  Rx2_data[120], Rx2_data1[120];                     
extern u8  Rx2_complete;                 
extern u16 Length2;

extern u32  PPS_cnt;

extern u32 MCU_ms_cnt;
extern u32 GPS_Delay;

extern u8  GAMT_OK_flag;
extern u8  GPS_OK_flag;
extern u8  Bar_OK_flag;

extern u32	totalDly;
extern u16 	timtest[10];
#define timtest_debug(i)  { timtest[i]=TIM2->CNT; }
//#define timtest_debug(i)  { ; }
extern u8 	PC_cmd[32];

#endif /* __MAIN_H */

