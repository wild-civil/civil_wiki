#include "main.h"

const u32 IIC_DELAY=5;
u16 MS561101BA_Cal_C[7];
u32 D1_Pres, D2_Temp;
s32 dT;
float TEMP, T2;
double OFF, SENS, OFF2, SENS2;
float Pressure, Altitude;
u8 MS5611_cnt=0;

/***************************************************************
// SDA_Out2Input SDA引脚的从输出变换成输入，与MCU类型有关，以下以
// ST的STM32 MCU为例.
****************************************************************/
void IIC_SDA_Out2Input(void)
{
	GPIO_InitTypeDef GPIO_InitStructure;
	GPIO_InitStructure.GPIO_Pin = GPIO_Pin_9;
	GPIO_InitStructure.GPIO_PuPd = GPIO_PuPd_NOPULL ;
	GPIO_InitStructure.GPIO_Mode = GPIO_Mode_IN;
	GPIO_Init(GPIOC, &GPIO_InitStructure);
}

/***************************************************************
// SDA_Input2Out SDA引脚的从输入变换成输出，与MCU类型有关，以下以
// ST的STM32 MCU为例.
****************************************************************/
void IIC_SDA_Input2Out(void)
{
	GPIO_InitTypeDef GPIO_InitStructure;
	GPIO_InitStructure.GPIO_Pin =  GPIO_Pin_9;
	GPIO_InitStructure.GPIO_Mode = GPIO_Mode_OUT;
	GPIO_InitStructure.GPIO_OType = GPIO_OType_PP;
	GPIO_InitStructure.GPIO_PuPd = GPIO_PuPd_UP;
	GPIO_InitStructure.GPIO_Speed = GPIO_Speed_50MHz;
	GPIO_Init(GPIOC, &GPIO_InitStructure);
}

/***************************************************************
// i2c_Delay 延时程序，其延时时间与MCU型号有关.
****************************************************************/
void IIC_Delay(u32 u32Delay)
{
	vu32 i;
	
	for(i=0; i<u32Delay; i++)	{	;	}	 
}

/***************************************************************
// 当SCL为高电平时，SDA由高电平向低电平跳变，产生开始信号.
// i2c_Start 模拟i2c发出一个start condition.
****************************************************************/
void IIC_Start(void) 
{
	IIC_SDA_HIGH;        // SDA --|___
	IIC_SCL_HIGH;        // SCL ----__
	IIC_Delay(IIC_DELAY);
	IIC_SDA_LOW;
	IIC_Delay(IIC_DELAY);
}

/****************************************************************
// 当SCL为高电平时，SDA产生由低电平向高电平的跳变，产生停止信号.
// i2c_Stop 模拟i2c发出一个stop condition.
****************************************************************/
void IIC_Stop(void)
{
	IIC_SDA_LOW;
	IIC_SCL_HIGH;
	IIC_Delay(IIC_DELAY);
	IIC_SDA_HIGH;
}
/****************************************************************
// 在一个CLK周期内， 通过拉SDA电平来产生应答信号.
// i2c_Ack 模拟i2c发出一个应答.
****************************************************************/
void IIC_Ack(void)
{
	IIC_SDA_LOW;
	IIC_SCL_HIGH;
	IIC_Delay(IIC_DELAY);
	IIC_SCL_LOW;
}

/****************************************************************
// 在一个CLK周期内， 保持SDA为高电平来产生非应答信号.
// i2c_NoAck 模拟i2c发出一个非应答信号.
****************************************************************/
void IIC_NoAck(void)
{
	IIC_SDA_HIGH;
	IIC_SCL_HIGH;
	IIC_Delay(IIC_DELAY);
	IIC_SCL_LOW;
}

/****************************************************************
// i2c_SalveAck 模拟i2c判断对方设备是否发出一个应答. 低电平为应答.
****************************************************************/
u8 IIC_isSalveAck(void)
{
	vu8 lu8Tmp = 0, i;       // 当不定义volatile时，优化时会出现问题。
		
	IIC_SDA_HIGH;
  IIC_SDA_Out2Input(); // SDA转换为输入模式.
	IIC_SCL_HIGH;
   
   for( i = 0; i < 10; i ++ )
   {
	   if( IIC_SDA_VALUE == 0 )	// 对方回应ACK？。
	   {
		   lu8Tmp = 1;
       break;
	   }
	   IIC_Delay( IIC_DELAY );
	}
	IIC_SCL_LOW;
	IIC_SDA_Input2Out();
	
	return lu8Tmp;
}

/****************************************************************
// i2c_Send 模拟i2c发送一个字节数据.
****************************************************************/
void IIC_Send(u8 u8Snd)
{
	u8 i;
	
	IIC_SCL_LOW;
	// 从高位发到低位, MSB在前.
	for( i = 0; i < 8; i ++ )
	{
		if( (u8Snd & 0x80) == 0x80 )		// 发送最高位.
		{
			IIC_SDA_HIGH;
		}
		else
		{
			IIC_SDA_LOW;
		}
		IIC_Delay( IIC_DELAY );	// 保证数据线的稳定.
		
		IIC_SCL_HIGH;				// 数据稳定后，SCL为高电平
		u8Snd = u8Snd << 1;		// 准备发下一位.
		IIC_Delay( IIC_DELAY ); // 延时以确保对方采样到SDA电平.
		IIC_SCL_LOW;				// SCL置低，保证下一位数据变化时SCL为低电平.
	}
}

/****************************************************************
// i2c_Read 模拟i2c读一个字节数据.
****************************************************************/
u8 IIC_Read(void)
{
	u8 i;
	vu8 lu8Val = 0;
	
	IIC_SDA_Out2Input(); // SDA转换为输入模式.
   for( i = 0; i < 8; i ++ )
   {
      IIC_SCL_HIGH;
      IIC_Delay( IIC_DELAY );
      
      lu8Val = lu8Val << 1;
      if( IIC_SDA_VALUE != 0 )
      {
         lu8Val = lu8Val | 0x01;
      }
      else
      {
        lu8Val = lu8Val & 0xfe;
      }
      
      IIC_SCL_LOW;
      IIC_Delay( IIC_DELAY );
   }
	IIC_SDA_Input2Out();		// SDA转换为输出模式.

	return (u8)lu8Val;
}

u8 MS561101BA_RESET(void)
{
	IIC_Start();
	IIC_Send(MS561101BA_SlaveAddress);
	if( 0 == IIC_isSalveAck() )
	{
		return 0;                       // 设备不响应.
	}
	IIC_Send(MS561101BA_RST);
	if( 0 == IIC_isSalveAck() )
	{
		return 0;                       // 设备不响应.
	}
	IIC_Stop();
	return 1; 
}

u8 MS561101BA_PROM_READ(void)
{
	u8 d1,d2,i;
	
	for(i=0;i<7;i++)
	{
		IIC_Start();
		IIC_Send(MS561101BA_SlaveAddress);
		if( 0 == IIC_isSalveAck() )
	  {
			return 0;                       // 设备不响应.
	  }
		IIC_Send(MS561101BA_PROM_RD+i*2);
		if( 0 == IIC_isSalveAck() )
	  {
			return 0;                       // 设备不响应.
	  }
		IIC_Stop();		
		
		IIC_Start();
		IIC_Send(MS561101BA_SlaveAddress+1);
		if( 0 == IIC_isSalveAck() )
	  {
			return 0;                       // 设备不响应.
	  }
		d1 = IIC_Read();           
	  IIC_Ack(); 
		d2 = IIC_Read();
		IIC_NoAck();
		IIC_Stop();
		
		MS561101BA_Cal_C[i]=(d1<<8)+d2;
		Delay(1000);
	}
	
  return 1; 	
}

u8 MS561101BA_start_Temperature(void)
{
		IIC_Start();
		IIC_Send(MS561101BA_SlaveAddress);
		if( 0 == IIC_isSalveAck() )
	  {
			return 0;                       // 设备不响应.
	  }
		IIC_Send(MS561101BA_D2_OSR_4096);
		if( 0 == IIC_isSalveAck() )
	  {
			return 0;                       // 设备不响应.
	  }
		IIC_Stop();	
		
		return 1; 
}

u8 MS561101BA_getTemperature(void)
{
	  u8 d1,d2,d3;
		
		IIC_Start();
		IIC_Send(MS561101BA_SlaveAddress);
		if( 0 == IIC_isSalveAck() )
	  {
			return 0;                       // 设备不响应.
	  }
		IIC_Send(MS561101BA_ADC_RD);
		if( 0 == IIC_isSalveAck() )
	  {
			return 0;                       // 设备不响应.
	  }
		IIC_Stop();	

	  IIC_Start();
		IIC_Send(MS561101BA_SlaveAddress+1);
		if( 0 == IIC_isSalveAck() )
	  {
			return 0;                       // 设备不响应.
	  }
		d1 = IIC_Read();           
	  IIC_Ack(); 
		d2 = IIC_Read();
		IIC_Ack(); 
		d3 = IIC_Read();
		IIC_NoAck();
		IIC_Stop();
		
		D2_Temp=(d1<<16)+(d2<<8)+d3;
	  dT=D2_Temp - (((u32)MS561101BA_Cal_C[5])<<8);
		TEMP=(s32)((float)2000+(float)dT*((float)MS561101BA_Cal_C[6])/(float)8388608);
		
		return 1; 
}

u8 MS561101BA_start_Pressure(void)
{
	  IIC_Start();
		IIC_Send(MS561101BA_SlaveAddress);
		if( 0 == IIC_isSalveAck() )
	  {
			return 0;                       // 设备不响应.
	  }
		IIC_Send(MS561101BA_D1_OSR_4096);
		if( 0 == IIC_isSalveAck() )
	  {
			return 0;                       // 设备不响应.
	  }
		IIC_Stop();
		
		return 1; 
}

u8 MS561101BA_getPressure(void)
{
	  u8 d1,d2,d3;	

    IIC_Start();
		IIC_Send(MS561101BA_SlaveAddress);
		if( 0 == IIC_isSalveAck() )
	  {
			return 0;                       // 设备不响应.
	  }
		IIC_Send(MS561101BA_ADC_RD);
		if( 0 == IIC_isSalveAck() )
	  {
			return 0;                       // 设备不响应.
	  }
		IIC_Stop();			

	  IIC_Start();
		IIC_Send(MS561101BA_SlaveAddress+1);
		if( 0 == IIC_isSalveAck() )
	  {
			return 0;                       // 设备不响应.
	  }
		d1 = IIC_Read();           
	  IIC_Ack(); 
		d2 = IIC_Read();
		IIC_Ack(); 
		d3 = IIC_Read();
		IIC_NoAck();
		IIC_Stop();
		
	  D1_Pres=(d1<<16)+(d2<<8)+d3;
		OFF=(double)MS561101BA_Cal_C[2]*(double)65536+(((double)MS561101BA_Cal_C[4]*dT)/(double)128);
    SENS=(double)MS561101BA_Cal_C[1]*(double)32768+(((double)MS561101BA_Cal_C[3]*dT)/(double)256);
		
		if(TEMP>=2000)
		{
			T2=0;
			OFF2=0;
			SENS2=0;
		}
		else 
		{
			T2=(dT*dT)/(float)0x80000000;
			OFF2=(float)2.5*(TEMP-(float)2000)*(TEMP-(float)2000);
			SENS2=(float)1.25*(TEMP-(float)2000)*(TEMP-(float)2000);
			if(TEMP<-1500)
			{
				OFF2=OFF2+(float)7.0*(TEMP+(float)1500)*(TEMP+(float)1500);
				SENS2=SENS2+(float)5.5*(TEMP+(float)1500)*(TEMP+(float)1500);
			}
		}
		
		TEMP=TEMP-T2;
		OFF=OFF-OFF2;
		SENS=SENS-SENS2;	
		
		Pressure=(D1_Pres*SENS/(float)2097152.0-OFF)/(float)3276800;
	  Altitude=((float)1013.25-Pressure)*(float)9.0;
		
    mpu_Data_value.Pressure=Pressure;
		mpu_Data_value.Altitude=Altitude;
		
		return 1; 
}


