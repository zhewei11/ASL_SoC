    .section .text.init
    .globl _start
    .option norvc

_start:
    li      x1, 0x00020000
    li      x2, 0x21000000
    li      x3, 0x11223344
    li      x4, 0x55667788
    li      x5, 0x13579bdf
    li      x6, 0x2468ace0
    sw      x3, 0(x2)
    sw      x4, 4(x2)
    sw      x5, 8(x2)
    sw      x6, 12(x2)

    # The first load refills one complete four-word D-cache line.
    lw      x10, 0(x2)
    lw      x11, 4(x2)
    lw      x12, 8(x2)
    lw      x13, 12(x2)
    sw      x10, 0(x1)
    sw      x11, 4(x1)
    sw      x12, 8(x1)
    sw      x13, 12(x1)

    # Re-read the line; these accesses must hit without another AXI refill.
    lw      x14, 0(x2)
    lw      x15, 12(x2)
    xor     x14, x14, x15
    sw      x14, 16(x1)
    li      x16, 0x43414348
    sw      x16, 20(x1)
1:
    j       1b
