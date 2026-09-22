`include "asl_soc_config.svh"

module address_attributes #(
     parameter logic [31:0] BOOT_ROM_BASE       = `ASL_SOC_BOOT_ROM_BASE
    ,parameter logic [31:0] BOOT_ROM_BYTES      = `ASL_SOC_BOOT_ROM_BYTES
    ,parameter logic [31:0] ITCM_BASE           = `ASL_SOC_ITCM_BASE
    ,parameter logic [31:0] ITCM_BYTES          = `ASL_SOC_ITCM_BYTES
    ,parameter logic [31:0] DTCM_BASE           = `ASL_SOC_DTCM_BASE
    ,parameter logic [31:0] DTCM_BYTES          = `ASL_SOC_DTCM_BYTES
    ,parameter logic [31:0] MMIO_BASE          = `ASL_SOC_MMIO_BASE
    ,parameter logic [31:0] MMIO_BYTES         = `ASL_SOC_MMIO_BYTES
    ,parameter logic [31:0] DMA_UNCACHED_BASE  = `ASL_SOC_DMA_UNCACHED_BASE
    ,parameter logic [31:0] DMA_UNCACHED_BYTES = `ASL_SOC_DMA_UNCACHED_BYTES
    ,parameter logic [31:0] DRAM_BASE          = `ASL_SOC_DRAM_BASE
    ,parameter logic [31:0] DRAM_BYTES         = `ASL_SOC_DRAM_BYTES
) (
     input  logic [31:0] address
    ,output logic        is_local
    ,output logic        is_mmio
    ,output logic        is_dram
    ,output logic        is_uncached
    ,output logic        is_cached_dram
);

    function automatic logic in_region(
         input logic [31:0] addr
        ,input logic [31:0] base
        ,input logic [31:0] bytes
    );
        logic [32:0] addr_ext;
        logic [32:0] limit_ext;
        begin
            addr_ext  = {1'b0, addr};
            limit_ext = {1'b0, base} + {1'b0, bytes};
            in_region = (addr_ext >= {1'b0, base}) && (addr_ext < limit_ext);
        end
    endfunction

    always_comb begin
        is_local       = in_region(address, BOOT_ROM_BASE, BOOT_ROM_BYTES) ||
                         in_region(address, ITCM_BASE, ITCM_BYTES) ||
                         in_region(address, DTCM_BASE, DTCM_BYTES);
        is_mmio        = in_region(address, MMIO_BASE, MMIO_BYTES);
        is_dram        = in_region(address, DRAM_BASE, DRAM_BYTES);
        is_uncached    = is_local || is_mmio ||
                         in_region(address, DMA_UNCACHED_BASE, DMA_UNCACHED_BYTES);
        is_cached_dram = is_dram && !is_uncached;
    end

endmodule
