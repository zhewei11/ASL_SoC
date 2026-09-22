    .section .text.init
    .globl _start
    .option norvc

_start:
    li      x1, 0x00020000
    sw      x0, 0(x1)
    sw      x0, 4(x1)
    sw      x0, 8(x1)
    sw      x0, 12(x1)
    la      x5, trap_handler
    csrw    mtvec, x5

    # Enable machine external and machine timer interrupts globally.
    li      x6, 0x00000880
    csrw    mie, x6
    li      x6, 0x00000008
    csrs    mstatus, x6

    # Generate a deterministic external interrupt through the local LIC.
    li      x7, 0x10031000
    li      x8, 1
    sw      x8, 0x40(x7)
1:
    j       1b

    .org 0x100
trap_handler:
    csrr    x10, mcause
    li      x11, 0x8000000b
    beq     x10, x11, external_handler
    li      x11, 0x80000007
    beq     x10, x11, timer_handler
    li      x12, 0xBAD00000
    sw      x12, 12(x1)
2:
    j       2b

external_handler:
    sw      x10, 0(x1)
    lw      x12, 0x1c(x7)
    sw      x12, 4(x1)
    sw      x12, 0x1c(x7)
    sw      x0, 0x0c(x7)

    # Program mtimecmp sufficiently ahead of the current mtime.
    li      x13, 0x10034000
    li      x14, -1
    sw      x14, 4(x13)
    lw      x15, 8(x13)
    addi    x15, x15, 200
    sw      x15, 0(x13)
    sw      x0, 4(x13)
    mret

timer_handler:
    sw      x10, 8(x1)
    li      x14, -1
    sw      x14, 4(x13)
    li      x12, 0x54494d52
    sw      x12, 12(x1)
    mret
