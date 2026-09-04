
#ifndef __INIT_H
#define __INIT_H

/* Includes ------------------------------------------------------------------*/
#include "stm32f4xx.h"
#include "arm_math.h" 
#include "stm32f4xx_it.h"

#ifdef __cplusplus
 extern "C" {
#endif

typedef struct{
	short Accel[3];//Accel X,Y,Z
	short Temp;
	short Gyro[3];//Gyro X,Y,Z
	short Mag[3];	//Mag X,Y,Z	
} MPU_AD_value;

typedef struct{
	double Accel[3];//Accel X,Y,Z
	double Temp;
	double Gyro[3];//Gyro X,Y,Z
	double Mag[3];	//Mag X,Y,Z	
	double Pressure;
  double Altitude;
} MPU_Data_value;

typedef struct{
  u32 GPS_ITOW;
  double GPS_Vn[3];
  double GPS_Pos[3];
  double GPS_Mot;
  u8 GPS_fixType;
  u8 GPS_flags;
  u8 GPS_numSV;
  float GPS_pDOP;
  double GPS_hAcc;
  double GPS_vAcc;
  double GPS_headAcc;
  double GPS_sAcc;
  double GPS_gSpeed;
} GPS_Data_value;

typedef struct{
	u32 head;
	float t;
	float Gyro[3];
	float Accel[3];
	float Magn[3];
	float mBar;
	float Att[3];
	float Vn[3];
	float Pos[5];
	float GPS_Vn[3];
	float GPS_Pos[5];
	float GPS_status;
	float GPS_delay;
	float Temp;
	u32 chksum;
} Out_Frame;

void Delay(__IO uint32_t nTime);
void mcu_init(void);
void RCC_Configuration(void);
void GPIO_Configuration(void);
void USART1_Configuration(u8 gpscfg);
void USART1_DIA_OUT_Configuration(void);
void USART2_Configuration(void);
void SPI1_Configuration(void);
void Init_MPU9250(void);
void READ_MPU9250_A_T_G(void);
void READ_MPU9250_MAG(void);

u8 MS561101BA_RESET(void);
u8 MS561101BA_PROM_READ(void);
u8 MS561101BA_start_Temperature(void);
u8 MS561101BA_getTemperature(void);
u8 MS561101BA_start_Pressure(void);
u8 MS561101BA_getPressure(void);

void TIM2_Configuration(void);
void TIM3_Configuration(void);
void USART1_DIA_OUT_Configuration(void);
void NVIC_Configuration(void);

void GPS_PVT_Decode(void);
void Uart1_Out_Frame(void);
void MainProcessDone(void);

#ifdef __cplusplus
}
#endif

#endif /* __INIT_H */

/************************ (C) COPYRIGHT STMicroelectronics *****END OF FILE****/
