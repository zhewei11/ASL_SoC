OUTPUT_ARCH(riscv)
ENTRY(_start)

MEMORY
{
    BOOT_ROM (rx) : ORIGIN = 0x00000000, LENGTH = 8K
}

SECTIONS
{
    .text : ALIGN(4)
    {
        KEEP(*(.text.init))
        *(.text*)
    } > BOOT_ROM

    /DISCARD/ :
    {
        *(.comment*)
        *(.riscv.attributes*)
    }
}

