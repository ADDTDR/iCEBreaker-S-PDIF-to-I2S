#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
BUILD_DIR="$ROOT/_build/default"
FIRMWARE_DIR="$ROOT/firmware"
BASE_HEX="$BUILD_DIR/firmware-base.hex"
BASE_HASH="$BUILD_DIR/firmware-base.asc.sha256"
ASC="$BUILD_DIR/hardware.asc"
PATCHED_ASC="$BUILD_DIR/hardware-firmware.asc"
BIN="$BUILD_DIR/hardware.bin"
TOOLS="$HOME/.apio/packages/oss-cad-suite/bin"

find_tool() {
    if command -v "$1" >/dev/null 2>&1; then
        command -v "$1"
    elif [ -x "$TOOLS/$1" ]; then
        printf '%s\n' "$TOOLS/$1"
    else
        printf 'Missing required tool: %s\n' "$1" >&2
        exit 1
    fi
}

OBJCOPY=$(find_tool riscv64-elf-objcopy)
ICEBRAM=$(find_tool icebram)
ICEPACK=$(find_tool icepack)

cd "$ROOT"
mkdir -p "$BUILD_DIR"
make -C firmware -B INVALIDATE_APIO=0 firmware.hex

"$OBJCOPY" -O binary "$FIRMWARE_DIR/firmware.elf" "$BUILD_DIR/firmware.bin"
firmware_size=$(wc -c < "$BUILD_DIR/firmware.bin" | tr -d ' ')
if [ "$firmware_size" -gt 4096 ]; then
    printf 'Firmware is %s bytes; maximum is 4096 bytes.\n' "$firmware_size" >&2
    exit 1
fi

xxd -e -g4 -c4 "$BUILD_DIR/firmware.bin" | awk '{print $2}' > "$BUILD_DIR/firmware-code.hex"
"$ICEBRAM" -g -s 1 32 1024 > "$BUILD_DIR/firmware-padding.hex"
awk 'NR == FNR { code[NR] = $1; words = NR; next }
     FNR <= words { print code[FNR]; next }
     { print $1 }' \
    "$BUILD_DIR/firmware-code.hex" "$BUILD_DIR/firmware-padding.hex" \
    > "$FIRMWARE_DIR/firmware.hex"

base_valid=0
if [ -f "$ASC" ] && [ -f "$BASE_HEX" ] && [ -f "$BASE_HASH" ]; then
    current_hash=$(shasum -a 256 "$ASC" | awk '{print $1}')
    recorded_hash=$(cat "$BASE_HASH")
    if [ "$current_hash" = "$recorded_hash" ]; then
        base_valid=1
    fi
fi

if [ "$base_valid" -eq 0 ]; then
    printf 'Building one-time FPGA base image...\n'
    rm -f "$BUILD_DIR/hardware.json" "$ASC" "$BIN" "$BUILD_DIR/hardware.pnr"
    apio build
    cp "$FIRMWARE_DIR/firmware.hex" "$BASE_HEX"
    shasum -a 256 "$ASC" | awk '{print $1}' > "$BASE_HASH"
else
    printf 'Patching firmware BRAM without FPGA synthesis...\n'
    "$ICEBRAM" "$BASE_HEX" "$FIRMWARE_DIR/firmware.hex" < "$ASC" > "$PATCHED_ASC"
    "$ICEPACK" "$PATCHED_ASC" "$BIN"
fi

apio upload