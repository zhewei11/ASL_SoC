    .section .text.init
    .globl _start
    .option norvc

_start:
    # Protocol 2.0 RT: one real no-response TX transaction every 100,000
    # cycles. This uses the normal MMIO/indirect-memory programming path.
    li      x3, 0x10030000
    li      x4, 100000
    sw      x4, 0x48(x3)       # frame period
    li      x4, 70000
    sw      x4, 0x4c(x3)       # communication deadline
    li      x4, 90000
    sw      x4, 0x50(x3)       # command commit deadline
    sw      x0, 0x90(x3)       # RT owner

    li      x4, 0x80000000     # command A, autoincrement
    sw      x4, 0xb8(x3)
    li      x4, 0x44332211
    sw      x4, 0xbc(x3)
    li      x4, 0x00000055
    sw      x4, 0xbc(x3)

    li      x4, 0x80004000     # descriptor region, autoincrement
    sw      x4, 0xb8(x3)
    li      x4, 0x00000103     # valid, abort-on-error, device ID 1
    sw      x4, 0xbc(x3)
    sw      x0, 0xbc(x3)       # command byte offset
    li      x4, 5
    sw      x4, 0xbc(x3)       # body length
    sw      x0, 0xbc(x3)       # no response expected
    sw      x0, 0xbc(x3)       # expected device mask
    sw      x0, 0xbc(x3)       # response timeout
    sw      x0, 0xbc(x3)       # inter-byte timeout
    sw      x0, 0xbc(x3)       # feedback map offset
    li      x4, 1
    sw      x4, 0xbc(x3)       # execute every frame
    li      x4, -1
    sw      x4, 0xbc(x3)       # end descriptor chain

    li      x4, 1
    sw      x4, 0xc4(x3)       # one descriptor
    sw      x4, 0xc8(x3)       # command sequence 1
    li      x4, 0x80000000
    sw      x4, 0xc0(x3)       # commit command A
    li      x4, 1
    sw      x4, 0x40(x3)       # enable RT scheduler

    # CNN input lives in a separate uncached region from the Ethernet frame
    # buffer. Repeated starts keep AXI read slot 3 continuously occupied.
    li      x5, 0x10032000
    li      x6, 0x20008000
    sw      x6, 0x08(x5)
    li      x6, 25600
    sw      x6, 0x0c(x5)
    li      x6, 1
    sw      x6, 0x00(x5)

    # Signal to the testbench that all engines have been configured.
    li      x7, 0x00020000
    li      x8, 0x53545253
    sw      x8, 0(x7)

    # Saturate the CPU data AXI path with uncached DRAM reads. Poll CNN only
    # once per 256 reads and immediately restart it after each completion.
    li      x20, 0x20010000
    li      x21, 0x20020000
    li      x22, 256

stress_loop:
    lw      x23, 0(x20)
    addi    x20, x20, 4
    bltu    x20, x21, stress_no_wrap
    li      x20, 0x20010000

stress_no_wrap:
    addi    x22, x22, -1
    bnez    x22, stress_loop
    li      x22, 256
    lw      x24, 0x04(x5)
    andi    x25, x24, 0x18     # latched IRQ or error
    beqz    x25, stress_loop
    li      x26, 4
    sw      x26, 0x00(x5)      # clear IRQ/error
    li      x26, 1
    sw      x26, 0x00(x5)      # restart DMA + stub
    j       stress_loop
