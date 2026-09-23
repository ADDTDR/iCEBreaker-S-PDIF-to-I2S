#include <stdint.h>

#define DEVICE_ID (*(volatile uint32_t *)0x10000000u)
#define SCRATCH (*(volatile uint32_t *)0x10000004u)

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

    SCRATCH = 0xb007c0deu;
    for (;;) {}
}