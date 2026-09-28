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

The display analyzer receives samples through the RISC-V firmware path. The CPU
polls the S/PDIF receive FIFO, reads each packed stereo frame, and writes it to
the spectrum mailbox. A synchronized update toggle transfers that sample back
to the 96 MHz analyzer domain. I2S playback remains on its direct hardware path.

The bands are useful as a low-cost visual spectrum indicator, not as
calibrated FFT bins or a precision audio analyzer.

Sequential processing avoids parallel arithmetic datapaths. At 96 kHz it
finishes all five bands in 20 of the roughly 1,000 available 96 MHz clocks per
audio sample.

## Wishbone Peripheral Bus

The CPU integration provides a 32-bit, single-master Wishbone Classic
peripheral bus. Four 4 KB slots are reserved:

| Address range | Planned peripheral |
| --- | --- |
| `0x10000000` - `0x10000fff` | S/PDIF receive FIFO |
| `0x10001000` - `0x10001fff` | I2S transmit FIFO |
| `0x10002000` - `0x10002fff` | Reserved |
| `0x10003000` - `0x10003fff` | HCMS display |

The implemented receive peripheral registers are:

| Address | Access | Function |
| --- | --- | --- |
| `0x10000000` | Read | Device ID, `0x49434542` (`ICEB`) |
| `0x10000004` | Read | Bit 0: RX not empty; bit 1: RX overflow |
| `0x10000008` | Read | Pop packed `{left[15:0], right[15:0]}` sample |
| `0x1000000c` | Read/write | Boot-test scratch register |
| `0x10000010` | Read/write | Spectrum sample mailbox |

Disabled or out-of-range Wishbone slots complete with both `ACK` and `ERR`,
preventing a software bus hang.

## RISC-V CPU

A minimum-area PicoRV32 configuration runs RV32E firmware at 12 MHz from a
4 KB unified program/data block RAM. Counters, interrupts, multiplication,
division, compressed instructions, and the upper 16 registers are disabled.
The vendored `picorv32.v` is the source distributed with the APIO OSS CAD
Suite.

The freestanding C firmware first checks that the Wishbone device ID is
`0x49434542` and verifies scratch-register read/write operation with the pattern
`0x12345678`. It writes `0xbad00001` on an ID failure or `0xbad00002` on a
scratch failure, then stops. On success it clears the scratch register, so the
firmware briefly writes the `0xb007c0de` boot signature and then clears it, so
the green boot indicator remains off during normal operation.

The main polling loop tests bit 0 of `RX_STATUS` (`RX_NOT_EMPTY`). When a stereo
frame is available, reading `RX_DATA` removes it from the receive FIFO and the
firmware writes that packed frame to `SPECTRUM_DATA`. This makes the spectrum
analyzer and display depend on the CPU transport path, while I2S playback stays
in hardware.

Rebuild the checked-in BRAM image with:

```sh
make -C firmware
```

This requires `riscv64-elf-gcc` and `riscv64-elf-objcopy`; on macOS they are
provided by the Homebrew `riscv64-elf-gcc` formula.

Generating `firmware.hex` removes cached APIO synthesis outputs so the next
`apio build` always embeds the updated firmware instead of reusing an older
bitstream.

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

Install APIO with the `icebreaker` board support. For a normal FPGA build, run:

```sh
make -C firmware
apio test
apio build
apio upload
```

For C-only changes, compile, patch the firmware block RAM in the existing
placed design, and upload it with:

```sh
./deploy_firmware.sh
```

The first invocation creates a base FPGA image with a full APIO build.
Subsequent invocations skip synthesis and place-and-route. Run a normal build
after changing Verilog, constraints, or APIO configuration; the next firmware
deployment will perform one full build to establish a new base.
