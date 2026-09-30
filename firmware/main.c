#include <stdint.h>

#define DEVICE_ID (*(volatile uint32_t *)0x10000000u)
#define RX_STATUS (*(volatile uint32_t *)0x10000004u)
#define RX_DATA (*(volatile uint32_t *)0x10000008u)
#define SCRATCH (*(volatile uint32_t *)0x1000000cu)
#define SPECTRUM_DATA (*(volatile uint32_t *)0x10000010u)
#define TX_STATUS (*(volatile uint32_t *)0x10001004u)
#define TX_DATA (*(volatile uint32_t *)0x10001008u)

#define RX_NOT_EMPTY 0x00000001u
#define TX_NOT_FULL 0x00000001u

static volatile uint32_t last_received_sample;

void _start(void) __attribute__((noreturn, section(".text.start")));

void _start(void)
{
    if (DEVICE_ID != 0x49434542u) {
        SCRATCH = 0xbad00001u;
        for (;;) {}
    }

    SCRATCH = 0x12345678u;
    if (SCRATCH != 0x12345678u) {
        SCRATCH = 0xbad00002u;
        for (;;) {}
    }

    SCRATCH = 0x00000000u;

    for (;;) {
        if ((RX_STATUS & RX_NOT_EMPTY) && (TX_STATUS & TX_NOT_FULL)) {
            last_received_sample = RX_DATA;
            SPECTRUM_DATA = last_received_sample;
            TX_DATA = last_received_sample;
        }
    }
}