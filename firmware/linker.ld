ENTRY(_start)

MEMORY
{
    ram (rwx) : ORIGIN = 0x00000000, LENGTH = 4K
}

SECTIONS
{
    .text : {
        KEEP(*(.text.start))
        *(.text*)
        *(.rodata*)
    } > ram

    .data : {
        *(.data*)
        *(.sdata*)
    } > ram

    .bss (NOLOAD) : {
        *(.bss*)
        *(.sbss*)
        *(COMMON)
    } > ram

    /DISCARD/ : {
        *(.comment*)
        *(.riscv.attributes*)
    }

    ASSERT(. <= ORIGIN(ram) + LENGTH(ram), "firmware exceeds 4 KB RAM")
}