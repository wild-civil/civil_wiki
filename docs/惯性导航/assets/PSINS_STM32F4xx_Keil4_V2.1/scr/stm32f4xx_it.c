/**
  ******************************************************************************
  * @file    Project/STM32F4xx_StdPeriph_Template/stm32f4xx_it.c 
  * @author  MCD Application Team
  * @version V1.0.1
  * @date    13-April-2012
  * @brief   Main Interrupt Service Routines.
  *          This file provides template for all exceptions handler and 
  *          peripherals interrupt service routine.
  ******************************************************************************
  * @attention
  *
  * <h2><center>&copy; COPYRIGHT 2012 STMicroelectronics</center></h2>
  *
  * Licensed under MCD-ST Liberty SW License Agreement V2, (the "License");
  * You may not use this file except in compliance with the License.
  * You may obtain a copy of the License at:
  *
  *        http://www.st.com/software_license_agreement_liberty_v2
  *
  * Unless required by applicable law or agreed to in writing, software 
  * distributed under the License is distributed on an "AS IS" BASIS, 
  * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
  * See the License for the specific language governing permissions and
  * limitations under the License.
  *
  ******************************************************************************
  */

/* Includes ------------------------------------------------------------------*/
#include "stm32f4xx_it.h"
#include "main.h"

/** @addtogroup Template_Project
  * @{
  */

/* Private typedef -----------------------------------------------------------*/
/* Private define ------------------------------------------------------------*/
/* Private macro -------------------------------------------------------------*/
/* Private variables ---------------------------------------------------------*/
/* Private function prototypes -----------------------------------------------*/
/* Private functions ---------------------------------------------------------*/

/******************************************************************************/
/*            Cortex-M4 Processor Exceptions Handlers                         */
/******************************************************************************/

/**
  * @brief   This function handles NMI exception.
  * @param  None
  * @retval None
  */
void NMI_Handler(void)
{
}

/**
  * @brief  This function handles Hard Fault exception.
  * @param  None
  * @retval None
  */
void HardFault_Handler(void)
{
  /* Go to infinite loop when Hard Fault exception occurs */
  while (1)
  {
  }
}

/**
  * @brief  This function handles Memory Manage exception.
  * @param  None
  * @retval None
  */
void MemManage_Handler(void)
{
  /* Go to infinite loop when Memory Manage exception occurs */
  while (1)
  {
  }
}

/**
  * @brief  This function handles Bus Fault exception.
  * @param  None
  * @retval None
  */
void BusFault_Handler(void)
{
  /* Go to infinite loop when Bus Fault exception occurs */
  while (1)
  {
  }
}

/**
  * @brief  This function handles Usage Fault exception.
  * @param  None
  * @retval None
  */
void UsageFault_Handler(void)
{
  /* Go to infinite loop when Usage Fault exception occurs */
  while (1)
  {
  }
}

/**
  * @brief  This function handles SVCall exception.
  * @param  None
  * @retval None
  */
void SVC_Handler(void)
{
}

/**
  * @brief  This function handles Debug Monitor exception.
  * @param  None
  * @retval None
  */
void DebugMon_Handler(void)
{
}

/**
  * @brief  This function handles PendSVC exception.
  * @param  None
  * @retval None
  */
void PendSV_Handler(void)
{
}

/**
  * @brief  This function handles SysTick Handler.
  * @param  None
  * @retval None
  */
void SysTick_Handler(void)
{
 // TimingDelay_Decrement();
}

/******************************************************************************/
/*                 STM32F4xx Peripherals Interrupt Handlers                   */
/*  Add here the Interrupt Handler for the used peripheral(s) (PPP), for the  */
/*  available peripheral interrupt handler's name please refer to the startup */
/*  file (startup_stm32f4xx.s).                                               */
/******************************************************************************/

/**
  * @brief  This function handles PPP interrupt request.
  * @param  None
  * @retval None
  */
/*void PPP_IRQHandler(void)
{
}*/

/** */
void EXTI0_IRQHandler(void)   // PPS IRQ, 1Hz
{
	if(EXTI_GetITStatus(EXTI_Line0) != RESET)
  {	
		EXTI_ClearITPendingBit(EXTI_Line0);
		PPS_cnt = MCU_ms_cnt*10+TIM2->CNT;  // PPS_cnt in 100us
	}	
}

/**
 * @brief TIM2中断 @ 100Hz 每10ms进一次
 * TIM2中断(第N次):
 * 先: Uart1_Out_Frame()      ← 打包的是第N-1次的计算结果
 *      DMA发送到PC
 * 后: READ_MPU9250()          ← 读新的原始数据
 *      GAMT_OK_flag=1         ← 通知主循环
 *
 * 主循环:
 * poll到flag → 算法用新数据 → 结果写outFrame → 等下一次中断
 * 
 */
void TIM2_IRQHandler(void)
{
	if(TIM_GetITStatus(TIM2, TIM_IT_Update) != RESET)  // TIM_IT_Update IRQ
  {
		TIM_ClearITPendingBit(TIM2, TIM_IT_Update);  // clear IRQ
		timtest_debug(0);
		MCU_ms_cnt += 10;   // 系统时间戳 MCU_ms_cnt in ms
		if(MCU_ms_cnt>10 && mcu_init_gpscfg==0)
		{
			Uart1_Out_Frame();   // NOTE: send out previous sampling & navigation infomation 打包上一帧的outFrame数据
			USART1_DIA_OUT_Configuration();  // DMA发送outFrame到PC
		}
		Delay(0);  // set totalDly=0 清零耗时统计
		
		timtest_debug(1);
		READ_MPU9250_A_T_G();                       // read MPU9250: IMU-Acc/Temp/Gyro SPI读加速度+温度+陀螺
		timtest_debug(2);
		READ_MPU9250_MAG();                         // read MPU9250: Mag I2C读磁力计(分3次)
		timtest_debug(3);
 		GAMT_OK_flag=1;                             // ★★★ 关键！通知主循环数据就绪

		if(Rx2_complete==1) // GPS收到完整帧
		{
			Rx2_complete = 0;
			GPS_OK_flag = 1;
			GPS_Delay = MCU_ms_cnt*10-PPS_cnt;
			GPS_PVT_Decode(); // 解析UBX得到经纬度/速度
		}
		timtest_debug(4);
	}
}
/**
 * @brief TIM3中断 @ 5s0Hz 每20ms进一次
 * 
 */
void TIM3_IRQHandler(void)
{	
	if (TIM_GetITStatus(TIM3, TIM_IT_Update) != RESET) 
	{	
		//TIM_ClearITPendingBit(TIM3, TIM_IT_Update);
		MS5611_cnt++;
		if(MS5611_cnt==1)                      // 分5步读温度和气压，10Hz输出 循环
		{
			MS561101BA_start_Temperature();    // 1: 启动温度ADC
		}
		if(MS5611_cnt==2)
		{
			MS561101BA_getTemperature();       // 2: 读温度
		}
		if(MS5611_cnt==3)
		{
			MS561101BA_start_Pressure();       // 3: 启动压力ADC
		}
		if(MS5611_cnt==4)
		{
			MS561101BA_getPressure();		   // 4: 读压力 + 算高度			
		}
		if(MS5611_cnt==5)
		{
			Bar_OK_flag=1;                     // 5: Bar_OK_flag=1
			MS5611_cnt=0;
		}
		TIM_ClearITPendingBit(TIM3, TIM_IT_Update);
		TIM_SetCounter(TIM3, 0);
	}	 
}

void USART2_IRQHandler(void)   // GPS input IRQ 每来1字节触发
{
	char temp;

	if(mcu_init_gpscfg)  // for u-center
	{		
		if(USART_GetITStatus(USART2, USART_IT_RXNE) != RESET)
		{	
				USART_ClearITPendingBit(USART2, USART_IT_RXNE);
				temp = USART_ReceiveData(USART2);
				USART_SendData(USART1, temp);
		}
		return;
	}
	
	if(USART_GetITStatus(USART2, USART_IT_RXNE) != RESET)
  {	
      USART_ClearITPendingBit(USART2, USART_IT_RXNE);
      temp = USART_ReceiveData(USART2);
		
			Rx2_data1[Length2]=temp;
			Length2++;
			if((Length2==1)&&(Rx2_data1[0]!=0xb5)) // 0xb562: u-center->View->Message View->UBX->NAV->PVT, 4Hz
			{
				Rx2_data1[0]=0;
				Length2=0;
			}
			if((Length2==2)&&(Rx2_data1[1]!=0x62))
			{
				Rx2_data1[0]=Rx2_data1[1]=0;
				Length2=0;
			}	
			if(Length2==100)
			{
				if(Rx2_data1[2]==0x01&&Rx2_data1[3]==0x07)
				{
					memcpy(Rx2_data, Rx2_data1, 100); // 逐字节拼UBX帧(0xB5 0x62 ...)
					Rx2_complete=1;                   // 收满100字节 → Rx2_complete=1
				}
				Length2=0;
			}		
  }	
}

void USART1_IRQHandler(void)    // COM1/USB input IRQ
{
	char temp;
	static int ii=0;
	if(USART_GetITStatus(USART1, USART_IT_RXNE) != RESET)
	{	
		USART_ClearITPendingBit(USART1, USART_IT_RXNE);
		temp=USART_ReceiveData(USART1);
		if(mcu_init_gpscfg) USART_SendData(USART2, temp);
		PC_cmd[ii++] = temp; if(ii>=32||temp==0) ii=0;
	}
}

/**
  * @}
  */ 


/************************ (C) COPYRIGHT STMicroelectronics *****END OF FILE****/
