/* GCC startup for STM32G031F8P6.
 *
 * Replaces Startup/startup_stm32g031xx.s (armasm, Keil MDK). Vector order is
 * taken from that file verbatim so the produced image has the same interrupt
 * table as the armclang build.
 */
#include <stdint.h>

extern uint32_t _estack;
extern uint32_t _sidata;
extern uint32_t _sdata;
extern uint32_t _edata;
extern uint32_t _sbss;
extern uint32_t _ebss;

void Reset_Handler(void);
void SystemInit(void);
void __libc_init_array(void);
int main(void);

void Default_Handler(void)
{
    for (;;) {
    }
}

#define WEAK_HANDLER(name) void name(void) __attribute__((weak, alias("Default_Handler")))

WEAK_HANDLER(NMI_Handler);
WEAK_HANDLER(HardFault_Handler);
WEAK_HANDLER(SVC_Handler);
WEAK_HANDLER(PendSV_Handler);
WEAK_HANDLER(SysTick_Handler);
WEAK_HANDLER(WWDG_IRQHandler);
WEAK_HANDLER(PVD_IRQHandler);
WEAK_HANDLER(RTC_TAMP_IRQHandler);
WEAK_HANDLER(FLASH_IRQHandler);
WEAK_HANDLER(RCC_IRQHandler);
WEAK_HANDLER(EXTI0_1_IRQHandler);
WEAK_HANDLER(EXTI2_3_IRQHandler);
WEAK_HANDLER(EXTI4_15_IRQHandler);
WEAK_HANDLER(DMA1_Channel1_IRQHandler);
WEAK_HANDLER(DMA1_Channel2_3_IRQHandler);
WEAK_HANDLER(DMA1_Ch4_5_DMAMUX1_OVR_IRQHandler);
WEAK_HANDLER(ADC1_IRQHandler);
WEAK_HANDLER(TIM1_BRK_UP_TRG_COM_IRQHandler);
WEAK_HANDLER(TIM1_CC_IRQHandler);
WEAK_HANDLER(TIM2_IRQHandler);
WEAK_HANDLER(TIM3_IRQHandler);
WEAK_HANDLER(LPTIM1_IRQHandler);
WEAK_HANDLER(LPTIM2_IRQHandler);
WEAK_HANDLER(TIM14_IRQHandler);
WEAK_HANDLER(TIM16_IRQHandler);
WEAK_HANDLER(TIM17_IRQHandler);
WEAK_HANDLER(I2C1_IRQHandler);
WEAK_HANDLER(I2C2_IRQHandler);
WEAK_HANDLER(SPI1_IRQHandler);
WEAK_HANDLER(SPI2_IRQHandler);
WEAK_HANDLER(USART1_IRQHandler);
WEAK_HANDLER(USART2_IRQHandler);
WEAK_HANDLER(LPUART1_IRQHandler);

typedef void (*vector_t)(void);

__attribute__((section(".isr_vector"), used))
const vector_t g_vectors[] = {
    (vector_t)&_estack,
    Reset_Handler,
    NMI_Handler,
    HardFault_Handler,
    0, 0, 0, 0, 0, 0, 0,
    SVC_Handler,
    0, 0,
    PendSV_Handler,
    SysTick_Handler,
    WWDG_IRQHandler,
    PVD_IRQHandler,
    RTC_TAMP_IRQHandler,
    FLASH_IRQHandler,
    RCC_IRQHandler,
    EXTI0_1_IRQHandler,
    EXTI2_3_IRQHandler,
    EXTI4_15_IRQHandler,
    0,
    DMA1_Channel1_IRQHandler,
    DMA1_Channel2_3_IRQHandler,
    DMA1_Ch4_5_DMAMUX1_OVR_IRQHandler,
    ADC1_IRQHandler,
    TIM1_BRK_UP_TRG_COM_IRQHandler,
    TIM1_CC_IRQHandler,
    TIM2_IRQHandler,
    TIM3_IRQHandler,
    LPTIM1_IRQHandler,
    LPTIM2_IRQHandler,
    TIM14_IRQHandler,
    0,
    TIM16_IRQHandler,
    TIM17_IRQHandler,
    I2C1_IRQHandler,
    I2C2_IRQHandler,
    SPI1_IRQHandler,
    SPI2_IRQHandler,
    USART1_IRQHandler,
    USART2_IRQHandler,
    LPUART1_IRQHandler,
    0,
    0,
};

void Reset_Handler(void)
{
    uint32_t *src = &_sidata;
    uint32_t *dst = &_sdata;

    while (dst < &_edata) {
        *dst++ = *src++;
    }
    for (dst = &_sbss; dst < &_ebss; ++dst) {
        *dst = 0u;
    }

    SystemInit();
    __libc_init_array();
    (void)main();

    for (;;) {
    }
}
