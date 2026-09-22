`include "rtos_core_config.svh"

module uncached_mmio_router #(
     parameter logic [31:0] MMIO_BASE = `RTOS_CORE_LOCAL_MMIO_BASE
    ,parameter logic [31:0] MMIO_MASK = `RTOS_CORE_LOCAL_MMIO_MASK
) (
     input  logic        core_req
    ,input  logic        core_write
    ,input  logic [31:0] core_word_addr
    ,input  logic [31:0] core_wdata
    ,input  logic [3:0]  core_wstrb
    ,output logic        core_valid
    ,output logic [31:0] core_rdata

    ,output logic        cache_req
    ,input  logic        cache_valid
    ,input  logic [31:0] cache_rdata

    ,output logic        mmio_valid
    ,input  logic        mmio_ready
    ,output logic        mmio_write
    ,output logic [31:0] mmio_addr
    ,output logic [31:0] mmio_wdata
    ,output logic [3:0]  mmio_wstrb
    ,input  logic [31:0] mmio_rdata
);

    logic address_is_mmio;

    assign mmio_addr = {core_word_addr[29:0], 2'b00};
    assign address_is_mmio =
        ((mmio_addr & MMIO_MASK) == (MMIO_BASE & MMIO_MASK));

    assign cache_req = core_req && !address_is_mmio;

    assign mmio_valid = core_req && address_is_mmio;
    assign mmio_write = core_write;
    assign mmio_wdata = core_wdata;
    assign mmio_wstrb = core_wstrb;

    assign core_valid = address_is_mmio ?
        (mmio_valid && mmio_ready) : cache_valid;
    assign core_rdata = address_is_mmio ?
        mmio_rdata : cache_rdata;

endmodule
