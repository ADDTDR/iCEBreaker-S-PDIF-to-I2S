# iCEBreaker S/PDIF to I2S

This project receives logic-level S/PDIF on an iCEBreaker v1.0e and sends
16-bit stereo I2S to a PCM5102 DAC. It targets the Apple TV optical output
through an external optical S/PDIF receiver module.

## Clocking

The iCEBreaker 12 MHz oscillator feeds the UP5K PLL, which generates the
96 MHz clock used by all FPGA logic. The S/PDIF receiver measures incoming
biphase-mark transitions against this 96 MHz clock.

The I2S transmitter uses a 32-bit phase accumulator with a nominal increment
of `0x20c49ba6`:

- FPGA system clock: 96 MHz
- I2S BCLK: 6.144 MHz nominal
- I2S LRCLK/sample rate: 96 kHz nominal
- I2S format: 16-bit stereo data in 32-bit channel slots
- MCLK: held low because the PCM5102 does not require it

The output clock is recovered digitally around the nominal 96 kHz rate. A
16-frame stereo FIFO compares decoded S/PDIF arrivals with I2S consumption.
Playback starts at the eight-frame midpoint. If the FIFO rises above midpoint,
the controller increases the NCO phase increment; if it falls below midpoint,
the controller decreases it. This makes the average I2S rate follow the source
while the FIFO absorbs short-term phase and edge-measurement variation.

The controller pull range is approximately +/-1900 ppm around 96 kHz. It is
intended to correct oscillator tolerance and long-term drift from the working
Apple TV source, not convert between unrelated sample rates. BCLK still has
the one-system-clock quantization jitter inherent in an FPGA NCO.

## Spectrum Display

An HCMS-29xx four-character dot-matrix display shows a five-band stereo
spectrum. The left channel uses the first two characters and the right channel
uses the last two. Each band is two columns wide, seven dots high, and grows
upward from the bottom row.

This is not a literal FFT. It
uses a compact, FPGA-friendly filter bank implemented by `audio_spectrum_bands`:

- Each channel stores five cascaded 24-bit one-pole low-pass stages. One shared,
	pipelined datapath updates them sequentially during the idle clocks between
	I2S sample requests.
- The difference between adjacent low-pass stages forms a progressively lower
	frequency band; the final stage supplies the lowest-frequency band.
- The absolute value of each band drives a 16-bit envelope. It rises
	immediately with signal level and decays gradually between peaks.
- A logarithmic-style threshold map converts each envelope to one of eight
	levels (zero through seven), which becomes the visible bar height.

The display analyzes the samples currently presented to the I2S transmitter.
It therefore follows recovered S/PDIF audio when locked and shows silence when
no valid input is available. The bar values cross from the 96 MHz analyzer into
the HCMS frame registers in the same clock domain.

The bands are useful as a low-cost visual spectrum indicator, not as
calibrated FFT bins or a precision audio analyzer.

Sequential processing avoids parallel arithmetic datapaths. At 96 kHz it
finishes all five bands in 20 of the roughly 1,000 available 96 MHz clocks per
audio sample.

## Wishbone Peripheral Bus

The first CPU integration stage provides a 32-bit, single-master Wishbone
Classic peripheral bus. Four 4 KB slots are reserved:

| Address range | Planned peripheral |
| --- | --- |
| `0x10000000` - `0x10000fff` | S/PDIF receive FIFO |
| `0x10001000` - `0x10001fff` | I2S transmit FIFO |
| `0x10002000` - `0x10002fff` | Spectrum analyzer |
| `0x10003000` - `0x10003fff` | HCMS display |

During bus bring-up, slot zero contains an ID register at offset `0x00` and a
byte-writable scratch register at offset `0x04`. Disabled or out-of-range
accesses complete with both `ACK` and `ERR`, preventing a software bus hang.

## RISC-V CPU

A minimum-area PicoRV32 configuration runs RV32E firmware at 12 MHz from a
4 KB unified program/data block RAM. Counters, interrupts, multiplication,
division, compressed instructions, and the upper 16 registers are disabled.
The vendored `picorv32.v` is the source distributed with the APIO OSS CAD
Suite.

The initial freestanding C firmware reads the Wishbone device ID, writes and
reads back the scratch register, then writes `0xb007c0de` as its boot-success
signature. Rebuild the checked-in BRAM image with:

```sh
make -C firmware
```

This requires `riscv64-elf-gcc` and `riscv64-elf-objcopy`; on macOS they are
provided by the Homebrew `riscv64-elf-gcc` formula.

## Connections

### PMOD 1A - PCM5102

| PMOD pin | FPGA pin | Signal | PCM5102 |
| --- | ---: | --- | --- |
| 1 | 4 | MCLK, held low | SCK/MCLK if exposed |
| 2 | 2 | BCLK | BCK |
| 3 | 47 | SDATA | DIN |
| 4 | 45 | LRCLK | LCK/LRCK |
| 5 | - | Ground | Ground |
| 6 | - | 3.3 V | Supply, if appropriate for the module |

### PMOD 1B - S/PDIF

| PMOD pin | FPGA pin | Signal |
| --- | ---: | --- |
| 1 | 43 | Logic-level S/PDIF input |
| 2 | 38 | Decode status/debug output |
| 5 | - | Ground |
| 6 | - | 3.3 V |

### HCMS-29xx Display

| FPGA pin | Signal | HCMS-29xx |
| ---: | --- | --- |
| 27 | HCMS_NCS_O | /CE or /CS |
| 25 | HCMS_DATA_O | Data in |
| 21 | HCMS_REGSEL_O | Register select |
| 19 | HCMS_CLOCK_O | Clock |
| 26 | HCMS_RESET_O | Reset |

Do not connect raw coaxial or optical S/PDIF directly to the FPGA pin. Use a
receiver module that outputs a 3.3 V-compatible logic signal.

## Status LEDs

The onboard LEDs are active-low.

| Green | Red | Meaning |
| --- | --- | --- |
| On | Off | CPU firmware booted; no audio error is active |
| On | On | CPU booted; input is active but valid audio is not decoding |
| Off | On | CPU trapped, or input is active without valid decoded audio |
| Off | Off | CPU has not completed boot |

PMOD 1B pin 2 is high while the receiver is locked or shortly after a valid
stereo frame.

## Build and Upload

Install APIO with the `icebreaker` board support and build the firmware, then
run:

```sh
make -C firmware
apio test
apio build
apio upload
```
