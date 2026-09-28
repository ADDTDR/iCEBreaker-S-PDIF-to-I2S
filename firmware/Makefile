RISCV_PREFIX ?= riscv64-elf-
INVALIDATE_APIO ?= 1
CC := $(RISCV_PREFIX)gcc
OBJCOPY := $(RISCV_PREFIX)objcopy

CFLAGS := -march=rv32e -mabi=ilp32e -Os -ffreestanding -nostdlib -nostartfiles
CFLAGS += -fno-pic -fno-builtin -msmall-data-limit=0
LDFLAGS := -Wl,-T,linker.ld -Wl,--build-id=none -Wl,--gc-sections

.PHONY: all clean

all: firmware.hex

firmware.elf: main.c linker.ld
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ main.c

firmware.hex: firmware.elf
	$(OBJCOPY) -O verilog --verilog-data-width=4 $< $@
	tr -d '\r' < $@ > $@.tmp && mv $@.tmp $@
	@if [ "$(INVALIDATE_APIO)" != "0" ]; then rm -f ../_build/default/hardware.json ../_build/default/hardware.asc; fi
	@if [ "$(INVALIDATE_APIO)" != "0" ]; then rm -f ../_build/default/hardware.bin ../_build/default/hardware.pnr; fi

clean:
	rm -f firmware.elf firmware.hex