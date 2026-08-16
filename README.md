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

Do not connect raw coaxial or optical S/PDIF directly to the FPGA pin. Use a
receiver module that outputs a 3.3 V-compatible logic signal.

## Status LEDs

The onboard LEDs are active-low.

| Green | Red | Meaning |
| --- | --- | --- |
| On | Off | Recent valid S/PDIF samples are being sent to the DAC |
| Off | On | Input transitions are present, but valid audio is not decoding |
| Off | Off | No S/PDIF carrier/activity detected; fallback tone is selected |

PMOD 1B pin 2 is high while the receiver is locked or shortly after a valid
stereo frame.

## Build and Upload

Install APIO with the `icebreaker` board support, then run:

```sh
apio test
apio build
apio upload
```

The generated bitstream is `_build/default/hardware.bin`.

## Current Limitations

- Receiver thresholds and clock recovery are tuned around 96 kHz S/PDIF input.
- Recovery tracks small source/local oscillator differences; it is not an
	asynchronous sample-rate converter for 44.1 or 48 kHz input.
- The 16-frame FIFO adds about 83 microseconds of startup buffering at 96 kHz.
- Loss of valid decoded frames selects the ROM fallback tone.
