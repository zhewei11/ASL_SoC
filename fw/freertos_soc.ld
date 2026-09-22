OUTPUT_ARCH( "riscv" )
ENTRY( _start )

/*
 * The SoC TCMs are Harvard memories: instructions are fetched from ITCM,
 * while normal loads/stores can reach DTCM only.  Keep all compiler-generated
 * constants and jump tables in DTCM so C code never issues a data read to
 * ITCM.
 */
MEMORY
{
    ROM  (rx)  : ORIGIN = 0x00000000, LENGTH = 0x2000
    IMEM (rx)  : ORIGIN = 0x00010000, LENGTH = 0x10000
    DMEM (rwx) : ORIGIN = 0x00020000, LENGTH = 0xFF00
}

SECTIONS
{
    .init ORIGIN( ROM ) : ALIGN( 4 )
    {
        KEEP( *(.init) )
        KEEP( *(.init.*) )
    } > ROM

    .text ORIGIN( IMEM ) : ALIGN( 256 )
    {
        __text_start = .;
        *(.text.freertos_risc_v_trap_handler)
        *(.text*)
        . = ALIGN( 16 );
        __text_end = .;
    } > IMEM

    .data ORIGIN( DMEM ) : ALIGN( 16 )
    {
        __data_start = .;
        __global_pointer$ = . + 0x800;
        *(.rodata*)
        *(.srodata*)
        *(.data*)
        *(.sdata*)
        . = ALIGN( 16 );
        __data_end = .;
    } > DMEM

    .bss (NOLOAD) : ALIGN( 16 )
    {
        __bss_start = .;
        *(.bss*)
        *(.sbss*)
        *(COMMON)
        . = ALIGN( 16 );
        __bss_end = .;
    } > DMEM

    __stack_top = ORIGIN( DMEM ) + LENGTH( DMEM );
    __stack_bottom = __stack_top - 0x1000;
    __freertos_test_signature = 0x0002FF00;
    PROVIDE( end = __bss_end );
    PROVIDE( _end = __bss_end );

    ASSERT( __text_end <= ORIGIN( IMEM ) + LENGTH( IMEM ),
            "FreeRTOS image exceeds ITCM" )
    ASSERT( __bss_end <= __stack_bottom,
            "FreeRTOS data/heap overlaps the boot stack" )

    /DISCARD/ :
    {
        *(.comment)
        *(.eh_frame*)
        *(.riscv.attributes)
    }
}
