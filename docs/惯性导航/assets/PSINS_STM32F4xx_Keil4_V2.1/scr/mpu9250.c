#include "main.h"

u8 BUF[14];       //数据缓冲
u8 MAG_x_axis, MAG_y_axis, MAG_z_axis;
u8 ST1_temp;
u8 MAG_cnt=0;

void WriteTo9250(u8 TxData)
{
	while (SPI_I2S_GetFlagStatus(SPI1, SPI_I2S_FLAG_TXE) == RESET){;}
  SPI_I2S_SendData(SPI1, TxData);
	while (SPI_I2S_GetFlagStatus(SPI1, SPI_I2S_FLAG_RXNE) == RESET){;}
	SPI_I2S_ReceiveData(SPI1);
}

u8 ReadToMpu9250(u8 reg)
{
  u8 ReadData = 0;
  while (SPI_I2S_GetFlagStatus(SPI1, SPI_I2S_FLAG_TXE) == RESET);
  SPI_I2S_SendData(SPI1, reg);
  while (SPI_I2S_GetFlagStatus(SPI1, SPI_I2S_FLAG_RXNE) == RESET);					  
  ReadData = SPI_I2S_ReceiveData(SPI1);
  return(ReadData);
}

void MPU9250_Write_Reg(u8 reg, u8 value)
{
	GPIO_ResetBits(GPIOC,GPIO_Pin_4);  // enable
  Delay(100);
	WriteTo9250(reg);
	WriteTo9250(value);
	GPIO_SetBits(GPIOC,GPIO_Pin_4);  // disenable
	Delay(100);
}

u8 MPU9250_Read_Reg(u8 reg)
{
	u8 val;
	GPIO_ResetBits(GPIOC,GPIO_Pin_4);  // enable
  Delay(100);
	WriteTo9250(reg|0x80); //reg地址+读使能
	val = ReadToMpu9250(0xff);//数据
	GPIO_SetBits(GPIOC,GPIO_Pin_4);  // disenable
	Delay(100);
	return val;
}

/***************************************************************/
// MPU内部i2c写入
//I2C_SLVx_ADDR:  MPU9250_AK8963_ADDR
//I2C_SLVx_REG:   reg
//I2C_SLVx_Data out:  value
/***************************************************************/
void i2c_Mag_write(u8 reg, u8 value)
{
	MPU9250_Write_Reg(I2C_SLV0_ADDR ,MPU9250_AK8963_ADDR);//设置磁力计地址,mode: write
	MPU9250_Write_Reg(I2C_SLV0_REG ,reg);//set reg addr
	MPU9250_Write_Reg(I2C_SLV0_DO ,value);//send value	
}

/***************************************************************/
// MPU内部i2c 读
//I2C_SLVx_ADDR:  MPU9250_AK8963_ADDR
//I2C_SLVx_REG:   reg
//return value:   EXT_SENS_DATA_00 register value
/***************************************************************/
u8 i2c_Mag_read(u8 reg)
{
	u8 val;
	MPU9250_Write_Reg(I2C_SLV0_ADDR ,MPU9250_AK8963_ADDR|0x80); //设置磁力计地址,mode:read
	MPU9250_Write_Reg(I2C_SLV0_REG ,reg);// set reg addr
	MPU9250_Write_Reg(I2C_SLV0_DO ,0xff);//read
	Delay(20000);  // =1ms
	val = MPU9250_Read_Reg(EXT_SENS_DATA_00);
	return val;
}

//****************初始化MPU9250************************
#define AKM_REG_WHOAMI      (0x00)
void Init_MPU9250(void)
{
	BUF[0]=MPU9250_Read_Reg(WHO_AM_I);
	BUF[1]=i2c_Mag_read(AKM_REG_WHOAMI);
	MPU9250_Write_Reg(PWR_MGMT_1, 0x80);	//解除休眠状态
	Delay(500000);
	//MPU9250_Write_Reg(PWR_MGMT_1, 0x00);//原来
	MPU9250_Write_Reg(PWR_MGMT_1, 0x01);
	BUF[0]=MPU9250_Read_Reg(PWR_MGMT_1);

	/**********************Init SLV0 i2c**********************************/	
  //Use SPI-bus read slave0
	MPU9250_Write_Reg(INT_PIN_CFG ,0x02);//  Bypass Enable Configuration  
	MPU9250_Write_Reg(56 ,0x01);
	MPU9250_Write_Reg(I2C_MST_CTRL,0x4d);//I2C MAster mode and Speed 400 kHz
	MPU9250_Write_Reg(USER_CTRL ,0x20); // I2C_MST _EN 
	MPU9250_Write_Reg(I2C_MST_DELAY_CTRL ,0x01);//延时使能I2C_SLV0 _DLY_ enable 
//  MPU9250_Write_Reg(I2C_MST_DELAY_CTRL ,0x03);	
	MPU9250_Write_Reg(I2C_SLV0_CTRL ,0x81); //enable IIC	and EXT_SENS_DATA==1 Byte
//	MPU9250_Write_Reg(I2C_SLV1_CTRL ,0x82); 
		
		/**********************Init MAG **********************************/
	 BUF[0]=i2c_Mag_read(AK8963_WHOAMI_REG);
   i2c_Mag_write(AK8963_CNTL2_REG,AK8963_CNTL2_SRST); // Reset AK8963
	 // BUF[0]=i2c_Mag_read(AK8963_CNTL2_REG);
	 Delay(500000);
	 i2c_Mag_write(AK8963_CNTL1_REG,0x16); // use i2c to set AK8963 working on Continuous measurement mode1 & 16-bit output	
	
	 MAG_x_axis=i2c_Mag_read(AK8963_ASAX);
	 MAG_y_axis=i2c_Mag_read(AK8963_ASAY);
	 MAG_z_axis=i2c_Mag_read(AK8963_ASAZ);
	 
	 ST1_temp=i2c_Mag_read(AK8963_ST1_REG);
		
/////////////////////////////////////////////////////////////////////////////	
	/*******************Init GYRO and ACCEL******************************/	
   //MPU9250_Write_Reg(SMPLRT_DIV, 0x07);//原  //陀螺仪采样率,典型值:0x07(1kHz) (SAMPLE_RATE= Internal_Sample_Rate / (1 + SMPLRT_DIV) )
	MPU9250_Write_Reg(SMPLRT_DIV, 0x0);  //陀螺仪采样率,典型值:0x07(1kHz) (SAMPLE_RATE= Internal_Sample_Rate / (1 + SMPLRT_DIV) )
//	MPU9250_Write_Reg(CONFIG, 0x47); //原     //低通滤波时间典型值07（3600Hz）Internal_Sample_Rate==8K
	MPU9250_Write_Reg(CONFIG, 0x43);      //低通滤波时间典型值07（3600Hz）Internal_Sample_Rate==8K
	BUF[1]=MPU9250_Read_Reg(CONFIG);
	MPU9250_Write_Reg(GYRO_CONFIG, 0x08); //陀螺仪自检及测量范围,典型值:0x18(不自检,2000deg/s)               0x08  500deg/s
	MPU9250_Write_Reg(ACCEL_CONFIG, 0x08);//加速度计自检及测量范围，高通滤波频率，典型值:0x18(不自检,16G)    0x08  4G
	MPU9250_Write_Reg(ACCEL_CONFIG_2, 0x48);//加速度计滤波频率 1K OUT   200平滑
	MPU9250_Write_Reg(FIFO_EN, 0xf8); 
  //MPU9250_Write_Reg(105, 0x40); 
}


/**
 * @brief 读加速度、读温度、读陀螺
 * 
 */
void READ_MPU9250_A_T_G(void)
{ 
   while(! GPIO_ReadInputDataBit(GPIOA,GPIO_Pin_15)) {;}   // 0-9 %

   BUF[0]=MPU9250_Read_Reg(ACCEL_XOUT_L);                   // 读低8位
   BUF[1]=MPU9250_Read_Reg(ACCEL_XOUT_H);                   // 读高8位
   mpu_AD_value.Accel[0]=	(BUF[1]<<8)|BUF[0];             // 拼成16位整数
   mpu_Data_value.Accel[0] = mpu_AD_value.Accel[0]/8192.0f; // 除以灵敏度（±4g对应8192，±8g对应4096），LSB = Least Significant Bit。实际加速度(g) = 原始读数 / 8192
   BUF[2]=MPU9250_Read_Reg(ACCEL_YOUT_L);
   BUF[3]=MPU9250_Read_Reg(ACCEL_YOUT_H);
   mpu_AD_value.Accel[1]=	(BUF[3]<<8)|BUF[2];
   mpu_Data_value.Accel[1] = mpu_AD_value.Accel[1]/8192.0f;
   BUF[4]=MPU9250_Read_Reg(ACCEL_ZOUT_L); 
   BUF[5]=MPU9250_Read_Reg(ACCEL_ZOUT_H);
   mpu_AD_value.Accel[2]=  (BUF[5]<<8)|BUF[4];
   mpu_Data_value.Accel[2] = mpu_AD_value.Accel[2]/8192.0f; 

	 BUF[0]=MPU9250_Read_Reg(TEMP_OUT_L); 
   BUF[1]=MPU9250_Read_Reg(TEMP_OUT_H);
   mpu_AD_value.Temp=	(BUF[1]<<8)|BUF[0];
	 mpu_Data_value.Temp = mpu_AD_value.Temp/333.87f+21.0f;  // T(°C) = TEMP_OUT / 333.87 + 21，其中 333.87 是温度灵敏度（LSB/°C），21 是参考室温偏移。
	
	 BUF[0]=MPU9250_Read_Reg(GYRO_XOUT_L); 
   BUF[1]=MPU9250_Read_Reg(GYRO_XOUT_H);
   mpu_AD_value.Gyro[0]=	(BUF[1]<<8)|BUF[0];
   mpu_Data_value.Gyro[0] = mpu_AD_value.Gyro[0]/65.5f; 	 // （±500°/s对应65.5） 。实际角速度(°/s) = 原始读数 / 65.5   
   BUF[2]=MPU9250_Read_Reg(GYRO_YOUT_L);
   BUF[3]=MPU9250_Read_Reg(GYRO_YOUT_H);
   mpu_AD_value.Gyro[1]=	(BUF[3]<<8)|BUF[2];
   mpu_Data_value.Gyro[1] = mpu_AD_value.Gyro[1]/65.5f;  						   
   BUF[4]=MPU9250_Read_Reg(GYRO_ZOUT_L); 
   BUF[5]=MPU9250_Read_Reg(GYRO_ZOUT_H);
   mpu_AD_value.Gyro[2]=  (BUF[5]<<8)|BUF[4];
   mpu_Data_value.Gyro[2] = mpu_AD_value.Gyro[2]/65.5f;  
}

//************************read MAG**************************/
void READ_MPU9250_MAG(void)
{ 
	ST1_temp=i2c_Mag_read(AK8963_ST1_REG);
	if((ST1_temp & AK8963_ST1_DRDY)==AK8963_ST1_DRDY)
	{
		if(MAG_cnt==0)
		{			
			BUF[0]=i2c_Mag_read(MAG_XOUT_L);			
			BUF[1]=i2c_Mag_read(MAG_XOUT_H);
			mpu_AD_value.Mag[0]=(BUF[1]<<8)|BUF[0];
			mpu_Data_value.Mag[0]=mpu_AD_value.Mag[0]*0.25f*(1.0+(MAG_x_axis-128)/256.0f);
			MAG_cnt=1;				
		}
		else if(MAG_cnt==1)
		{
			BUF[2]=i2c_Mag_read(MAG_YOUT_L);
			BUF[3]=i2c_Mag_read(MAG_YOUT_H);
			mpu_AD_value.Mag[1]=(BUF[3]<<8)|BUF[2];
			mpu_Data_value.Mag[1]=mpu_AD_value.Mag[1]*0.25f*(1.0+(MAG_y_axis-128)/256.0f);
			MAG_cnt=2;	
		}
		else if(MAG_cnt==2)
		{
			BUF[4]=i2c_Mag_read(MAG_ZOUT_L);
			BUF[5]=i2c_Mag_read(MAG_ZOUT_H);
			mpu_AD_value.Mag[2]=(BUF[5]<<8)|BUF[4];
			mpu_Data_value.Mag[2]=mpu_AD_value.Mag[2]*0.25f*(1.0+(MAG_z_axis-128)/256.0f);
			MAG_cnt=0;
		}
	  i2c_Mag_write(AK8963_CNTL1_REG,0x11);
	}
}
