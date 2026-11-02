#include "board.h"
#include "stm32g0xx.h"
#include "imu.h"
#include "protocol.h"
#include "control_table.h"
#include <stdio.h>

static proto_context protocol;

static void send_packet(void *user, const uint8_t *data, uint16_t length)
{
    proto_context *context = (proto_context *)user;
    if (board_bus_send(data, length) != 0) ++context->cancelled_replies;
}

/* USART2 pin diagnostics: dump the exact GPIO/USART register state so that a
 * dead TX/RX pin can be told apart from a firmware configuration mistake. */
static void print_pins(void)
{
    char text[220];
    (void)snprintf(text, sizeof(text),
        "DBG MODER=%08lX AFR0=%08lX PUPDR=%08lX IDR=%04lX CR1=%08lX BRR=%08lX APBENR1=%08lX\r\n",
        (unsigned long)GPIOA->MODER, (unsigned long)GPIOA->AFR[0], (unsigned long)GPIOA->PUPDR,
        (unsigned long)GPIOA->IDR,
        (unsigned long)USART2->CR1, (unsigned long)USART2->BRR, (unsigned long)RCC->APBENR1);
    board_log(text);
}

/* SPI / sensor-pin diagnostics: separate a dead chip from a wrong SPI setup. */
static void print_spi(void)
{
    char text[220];
    (void)snprintf(text, sizeof(text),
        "SPI MODER=%08lX AFR0=%08lX PUPDR=%08lX IDR=%04lX CR1=%08lX CR2=%08lX SR=%08lX\r\n",
        (unsigned long)GPIOA->MODER, (unsigned long)GPIOA->AFR[0], (unsigned long)GPIOA->PUPDR,
        (unsigned long)GPIOA->IDR,
        (unsigned long)SPI1->CR1, (unsigned long)SPI1->CR2, (unsigned long)SPI1->SR);
    board_log(text);
}

static void slow_delay(uint32_t loops)
{
    for (volatile uint32_t i = 0u; i < loops; ++i) __NOP();
}

/* Bit-bang one register read in SPI mode 3 with a ~20 ms clock period, so that
 * every level stays long enough to be measured with a multimeter. */
static uint8_t bitbang_read(uint8_t reg)
{
    char trace[10];
    char text[80];
    uint8_t value = 0u;
    uint8_t bit;
    uint8_t idle;
    uint8_t mosi = (uint8_t)(reg | 0x80u);

    /* PA4=CS out, PA5=SCK out, PA6=MISO in, PA7=MOSI out. PA6 must stay an
     * input: MODER field n is at bits 2n, so driving the wrong one would both
     * hide the sensor and hang the dummy-byte read at a fixed level. */
    GPIOA->BSRR = (1uL << 4) | (1uL << 5) | (1uL << 7); /* idle CS=1 SCK=1 MOSI=1 */
    GPIOA->OTYPER &= ~((1uL << 4) | (1uL << 5) | (1uL << 7));
    GPIOA->MODER = (GPIOA->MODER & ~((3uL << 8) | (3uL << 10) | (3uL << 12) | (3uL << 14)))
        | (1uL << 8) | (1uL << 10) | (1uL << 14);

    idle = (uint8_t)((GPIOA->IDR >> 6) & 1u);
    GPIOA->BRR = 1uL << 4;
    for (int i = 7; i >= 0; --i) {
        GPIOA->BRR = 1uL << 5;
        if ((mosi >> i) & 1u) GPIOA->BSRR = 1uL << 7; else GPIOA->BRR = 1uL << 7;
        slow_delay(300000u);
        GPIOA->BSRR = 1uL << 5;
        slow_delay(300000u);
        board_watchdog_feed();
    }
    for (int i = 7; i >= 0; --i) {
        GPIOA->BRR = 1uL << 5;
        slow_delay(300000u);
        GPIOA->BSRR = 1uL << 5;
        slow_delay(300000u);
        bit = (uint8_t)((GPIOA->IDR >> 6) & 1u);
        value = (uint8_t)((value << 1) | bit);
        trace[7 - i] = bit ? '1' : '0';
        board_watchdog_feed();
    }
    GPIOA->BSRR = 1uL << 4;
    trace[8] = '\0';

    /* Back to the real pin roles: CS is plain GPIO output, PA5/6/7 are AF0. */
    GPIOA->MODER = (GPIOA->MODER & ~((3uL << 8) | (3uL << 10) | (3uL << 12) | (3uL << 14)))
        | (1uL << 8) | (2uL << 10) | (2uL << 12) | (2uL << 14);
    GPIOA->BSRR = 1uL << 4;

    (void)snprintf(text, sizeof(text), "BB reg=0x%02X idle=%u bits=%s value=0x%02X\r\n",
                   (unsigned)reg, (unsigned)idle, trace, (unsigned)value);
    board_log(text);
    return value;
}

static void spi_stress(void)
{
    char text[96];
    uint8_t value = 0u;
    uint32_t reads = 0u;
    uint32_t errors = 0u;
    uint32_t last = board_millis();

    while ((uint32_t)(board_millis() - last) < 5000u) {
        if (board_spi_read(0x0Fu, &value, 1u) != 0) ++errors;
        ++reads;
        board_watchdog_feed();
    }
    (void)snprintf(text, sizeof(text), "SPI stress reads=%lu errors=%lu last=0x%02X\r\n",
                   (unsigned long)reads, (unsigned long)errors, (unsigned)value);
    board_log(text);
}

/* Read one pin twice, once with the internal pull-up and once with the internal
 * pull-down. A net with no driver follows the pull (returns 0b10); a net that
 * something really drives ignores it (0b00 = driven low, 0b11 = driven high).
 * This separates "the chip is talking" from "the pad is just floating" without
 * needing a probe on a 0.5 mm LGA pad. */
static uint8_t probe_pin(unsigned pin)
{
    uint32_t moder = GPIOA->MODER;
    uint32_t pupdr = GPIOA->PUPDR;
    uint32_t shift = pin * 2u;
    uint8_t up;
    uint8_t down;

    GPIOA->MODER = moder & ~(3uL << shift);
    GPIOA->PUPDR = (pupdr & ~(3uL << shift)) | (1uL << shift);
    slow_delay(200000u);
    up = (uint8_t)((GPIOA->IDR >> pin) & 1u);
    GPIOA->PUPDR = (pupdr & ~(3uL << shift)) | (2uL << shift);
    slow_delay(200000u);
    down = (uint8_t)((GPIOA->IDR >> pin) & 1u);
    GPIOA->PUPDR = pupdr;
    GPIOA->MODER = moder;
    return (uint8_t)((up << 1) | down);
}

static void probe_pins(void)
{
    char text[200];
    uint8_t int1 = probe_pin(0u);   /* PA0 = U2 pin 4  IMU_INT1 */
    uint8_t int2 = probe_pin(8u);   /* PA8 = U2 pin 9  IMU_INT2 */
    uint8_t miso = probe_pin(6u);   /* PA6 = U2 pin 1  SDO/SA0 */

    (void)snprintf(text, sizeof(text),
        "PROBE INT1(PA0)=%u%u INT2(PA8)=%u%u MISO(PA6)=%u%u  10=floating 00=driven low 11=driven high\r\n",
        (unsigned)((int1 >> 1) & 1u), (unsigned)(int1 & 1u),
        (unsigned)((int2 >> 1) & 1u), (unsigned)(int2 & 1u),
        (unsigned)((miso >> 1) & 1u), (unsigned)(miso & 1u));
    board_log(text);
}

/* Level seen with no internal pull at all, so an external pull shows through. */
static uint8_t level_nopull(unsigned pin)
{
    uint32_t moder = GPIOA->MODER;
    uint32_t pupdr = GPIOA->PUPDR;
    uint32_t shift = pin * 2u;
    uint8_t level;

    GPIOA->MODER = moder & ~(3uL << shift);
    GPIOA->PUPDR = pupdr & ~(3uL << shift);
    slow_delay(50000u);
    level = (uint8_t)((GPIOA->IDR >> pin) & 1u);
    GPIOA->PUPDR = pupdr;
    GPIOA->MODER = moder;
    return level;
}

/* Loopback through the sensor itself: PIN_CTRL.sdo_pu_en turns on a pull-up on
 * the SDO/SA0 pad. If that write reaches the die, MISO stops floating. Proves
 * CS, SCK, MOSI and the MISO connection all at once. */
static void sdo_pullup_test(void)
{
    char text[200];
    uint8_t ctrl = 0u;
    uint8_t value = 0x40u;
    int rd;
    uint8_t none_before = level_nopull(6u);
    uint8_t pd_before = (uint8_t)(probe_pin(6u) & 1u);
    uint8_t none_after;
    uint8_t pd_after;

    rd = board_spi_read(0x02u, &ctrl, 1u);
    (void)board_spi_write(0x02u, &value, 1u);
    slow_delay(200000u);
    none_after = level_nopull(6u);
    pd_after = (uint8_t)(probe_pin(6u) & 1u);
    value = 0x00u;
    (void)board_spi_write(0x02u, &value, 1u);

    (void)snprintf(text, sizeof(text),
        "SDO-PU read=%d ctrl=0x%02X none=%u>%u pulldown=%u>%u (any change = the write reached the chip)\r\n",
        rd, (unsigned)ctrl, (unsigned)none_before, (unsigned)none_after,
        (unsigned)pd_before, (unsigned)pd_after);
    board_log(text);
}

/* Observe the chip through INT1 instead of MISO, so a doubtful SDO pad cannot
 * hide the answer. IF_CFG bit4 (h_lactive) flips the inactive level of the
 * interrupt pins from LOW to HIGH, and bit3 (pp_od) makes them open drain.
 * INT1 already measures "driven low", so both writes are visible on PA0. */
static void int_output_test(void)
{
    char text[240];
    uint8_t ifcfg = 0u;
    uint8_t value;
    uint8_t base = probe_pin(0u);
    uint8_t hl;
    uint8_t od;
    int rd = board_spi_read(0x03u, &ifcfg, 1u);

    value = 0x10u;                                   /* IF_CFG.h_lactive = 1 */
    (void)board_spi_write(0x03u, &value, 1u);
    slow_delay(200000u);
    hl = probe_pin(0u);

    value = 0x08u;                                   /* IF_CFG.pp_od = 1 */
    (void)board_spi_write(0x03u, &value, 1u);
    slow_delay(200000u);
    od = probe_pin(0u);

    value = 0x00u;
    (void)board_spi_write(0x03u, &value, 1u);

    (void)snprintf(text, sizeof(text),
        "INT-TEST read=%d ifcfg=0x%02X base=%u%u hl=1>%u%u od=1>%u%u  (base 00; hl should be 11, od should be 10)\r\n",
        rd, (unsigned)ifcfg,
        (unsigned)((base >> 1) & 1u), (unsigned)(base & 1u),
        (unsigned)((hl >> 1) & 1u), (unsigned)(hl & 1u),
        (unsigned)((od >> 1) & 1u), (unsigned)(od & 1u));
    board_log(text);
}

static void print_status(void)
{
    imu_snapshot_t s;
    char text[260];
    imu_get_snapshot(&s);
    (void)snprintf(text, sizeof(text),
        "t=%lu ready=%u id=0x%02X err=%u n=%lu gyro=%d,%d,%d q16=%04X,%04X,%04X spierr=%lu fifo=%lu uart=%lu ck=%lu idr=%04lX\r\n",
        (unsigned long)board_millis(), (unsigned)s.ready, (unsigned)s.who_am_i, (unsigned)s.error,
        (unsigned long)s.sample_count, (int)s.gyro[0], (int)s.gyro[1], (int)s.gyro[2],
        (unsigned)s.quat_fp16[0], (unsigned)s.quat_fp16[1], (unsigned)s.quat_fp16[2],
        (unsigned long)s.spi_errors, (unsigned long)s.fifo_overflows,
        (unsigned long)board_diagnostics.uart_errors, (unsigned long)protocol.checksum_errors,
        (unsigned long)GPIOA->IDR);
    board_log(text);
}

int main(void)
{
    uint32_t last_log = 0u;
    uint8_t periodic_log = 1u;
    uint8_t pa2_gpio = 0u;
    uint8_t pa2_level = 0u;
    uint32_t pa2_stamp = 0u;
    board_init();
    proto_init(&protocol, control_table_read, control_table_write, send_packet, &protocol);
    imu_init(board_millis());
    board_log("\r\n" BOARD_FIRMWARE_STRING " | STM32G031F8 | FT-SCS ID=200 " BOARD_BUS_BAUD_STR " 8N1\r\n");
    board_log("LOG=115200 8N1; ?:help s:status l:logs r:restart d:pins i:spi b:bitbang n:probe x:sdo-pu y:int-out w:spi-stress\r\n");
    print_pins();
    for (;;) {
        uint8_t byte;
        uint32_t received_us;
        if (board_bus_take_fault()) proto_reset_receiver(&protocol);
        while (board_bus_pop(&byte, &received_us)) {
            proto_feed(&protocol, byte, received_us);
        }
        proto_poll(&protocol, board_micros());
        /* Do not begin sensor/log work while an instruction is being received
         * or a synchronized reply is queued. Protocol traffic has priority. */
        if (protocol.rx_length == 0u && protocol.pending == 0u) {
            imu_poll(board_millis());
            int command = board_log_getchar();
            if (command == 'r' || command == 'R') { imu_request_reinit(); board_log("IMU restart requested\r\n"); }
            else if (command == 'l' || command == 'L') { periodic_log ^= 1u; board_log(periodic_log ? "logs on\r\n" : "logs off\r\n"); }
            else if (command == 'd' || command == 'D') print_pins();
            else if (command == 't' || command == 'T') {
                /* Drive the bus from the IMU side: first a broadcast ping (so the
                 * servo answers), then a 0x55 pattern (so a sniffer sees bytes). */
                static const uint8_t ping[6] = { 0xFF, 0xFF, 0xFE, 0x02, 0x01, 0xFE };
                uint8_t filler[16];
                char text[64];
                int rc;
                for (uint32_t i = 0; i < sizeof(filler); ++i) filler[i] = 0x55u;
                rc = board_bus_send(ping, sizeof(ping));
                (void)snprintf(text, sizeof(text), "TX ping rc=%d\r\n", rc);
                board_log(text);
                rc = board_bus_send(filler, sizeof(filler));
                (void)snprintf(text, sizeof(text), "TX 0x55 rc=%d\r\n", rc);
                board_log(text);
            }
            else if (command == 'p' || command == 'P') {
                pa2_gpio ^= 1u;
                if (pa2_gpio) {
                    /* PA2 as a plain push-pull output: proves whether the pad can drive at all. */
                    GPIOA->MODER = (GPIOA->MODER & ~(3UL << 4)) | (1UL << 4);
                    GPIOA->OTYPER &= ~(1UL << 2);
                    GPIOA->OSPEEDR = (GPIOA->OSPEEDR & ~(3UL << 4)) | (3UL << 4);
                    pa2_level = 0u; pa2_stamp = board_millis();
                    GPIOA->BRR = 1UL << 2;
                    board_log("PA2 -> GPIO output, toggling every 500 ms\r\n");
                } else {
                    GPIOA->AFR[0] = (GPIOA->AFR[0] & ~(15UL << 8)) | (1UL << 8);
                    GPIOA->MODER = (GPIOA->MODER & ~(3UL << 4)) | (2UL << 4);
                    board_log("PA2 -> AF1 (USART2 TX)\r\n");
                }
                print_pins();
            }
            else if (command == 'i' || command == 'I') print_spi();
            else if (command == 'b' || command == 'B') {
                (void)bitbang_read(0x0Fu);
                (void)bitbang_read(0x0Fu);
            }
            else if (command == 'n' || command == 'N') probe_pins();
            else if (command == 'x' || command == 'X') sdo_pullup_test();
            else if (command == 'y' || command == 'Y') int_output_test();
            else if (command == 'w' || command == 'W') spi_stress();
            else if (command == '?' || command == 'h') board_log("s=status, l=logs, r=restart IMU, d=pins, i=spi, b=bitbang whoami, n=probe INT1/INT2/MISO, x=SDO pull-up loopback, y=INT1 output test, w=spi stress, p=PA2 gpio, t=TX probe\r\n");
            if (pa2_gpio && (uint32_t)(board_millis() - pa2_stamp) >= 500u) {
                char text[64];
                pa2_stamp = board_millis();
                pa2_level ^= 1u;
                if (pa2_level) GPIOA->BSRR = 1UL << 2; else GPIOA->BRR = 1UL << 2;
                (void)snprintf(text, sizeof(text), "PA2=%u IDR=%04lX\r\n",
                               (unsigned)pa2_level, (unsigned long)GPIOA->IDR);
                board_log(text);
            }
            if (command == 's' || command == 'S' ||
                (periodic_log && (uint32_t)(board_millis() - last_log) >= 1000u)) {
                last_log = board_millis(); print_status();
            }
        }
        board_watchdog_feed();
    }
}
