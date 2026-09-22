    .section .text.init
    .globl _start
    .option norvc

_start:
    # DTCM signature base.
    li      x1, 0x00020000
    li      x2, 0x12345678
    sw      x2, 0(x1)

    # Route synchronous exceptions to a handler kept in Boot ROM.
    la      x5, trap_handler
    csrw    mtvec, x5

    # Prove that 0x1003_xxxx bypasses D-cache and reaches external MMIO.
    li      x3, 0x10030000
    lw      x4, 0x30(x3)
    sw      x4, 4(x1)

    # RV32IMF must report I+M+F, with MXL=RV32.
    csrr    x8, misa
    sw      x8, 16(x1)

    # Read a second, non-Protocol page to verify the new SoC page decoder.
    li      x3, 0x10032000
    lw      x10, 4(x3)
    sw      x10, 24(x1)

    # Report one boot marker through the Host UART MMIO page.
    li      x3, 0x10037000
    li      x10, 'A'
    sw      x10, 8(x3)

    # Exercise the integrated F register file, arithmetic/conversion datapath,
    # DTCM FLW/FSW path and floating-point CSRs using exact binary operands.
    li      x11, 0x3fc00000          # 1.5f
    fmv.w.x f0, x11
    li      x12, 0x40100000          # 2.25f
    fmv.w.x f1, x12

    fadd.s  f2, f0, f1              # 3.75f = 0x40700000
    fmv.x.w x13, f2
    sw      x13, 8(x1)

    fmul.s  f3, f0, f1              # 3.375f = 0x40580000
    fmv.x.w x13, f3
    sw      x13, 12(x1)

    fdiv.s  f4, f1, f0              # 1.5f = 0x3fc00000
    fmv.x.w x13, f4
    sw      x13, 28(x1)

    fcvt.w.s x14, f2, rne           # round 3.75f to 4 and set NX
    sw      x14, 32(x1)

    fsw     f2, 40(x1)
    flw     f5, 40(x1)
    fmv.x.w x15, f5
    sw      x15, 40(x1)

    csrr    x16, fcsr
    sw      x16, 36(x1)
    csrr    x17, mstatus
    sw      x17, 52(x1)

    li      x9, 0x46505521           # "FPU!" completion signature
    sw      x9, 20(x1)
1:
    j       1b

    .org 0x100
trap_handler:
    csrr    x6, mcause
    sw      x6, 44(x1)
    csrr    x7, mtval
    sw      x7, 48(x1)
    li      x9, 0xBAD
    sw      x9, 20(x1)
2:
    j       2b
