`include "rtos_core_config.svh"

module protocol2_pingpong_sram (
     input  logic        clk
    ,input  logic        rst
    ,input  logic        flush
    // Port A: TX packetizer or RX parser
    ,input  logic        port_a_request
    ,output logic        port_a_ready
    ,input  logic        port_a_write_enable
    ,input  logic [10:0] port_a_byte_address
    ,input  logic [7:0]  port_a_write_data
    ,output logic        port_a_read_valid
    ,output logic [31:0] port_a_read_data
    // Port B: RX result/parameter drain
    ,input  logic        port_b_request
    ,output logic        port_b_ready
    ,input  logic [8:0]  port_b_word_address
    ,output logic        port_b_read_valid
    ,output logic [31:0] port_b_read_data
);

    // 512 x 32 bits = 2048 bytes.
    // byte_address[10] selects the 1024-byte ping/pong bank.

`ifdef RTOS_CORE_PROTOCOL2_USE_SRAM_MACRO

    logic        macro_select_a;
    logic        macro_select_b;
    logic        macro_enable;
    logic        macro_write_enable;
    logic [8:0]  macro_word_address;
    logic [31:0] macro_bweb;
    logic [31:0] macro_read_data;

    // The available ASIC macro is single-port. Port A has priority because
    // it carries the real-time RX write stream. Port B holds its request
    // until ready, so parameter draining continues on the next free cycle.
    assign macro_select_a = port_a_request;
    assign macro_select_b = !port_a_request && port_b_request;
    assign port_a_ready   = 1'b1;
    assign port_b_ready   = !port_a_request;

    assign macro_enable =
        macro_select_a || macro_select_b;
    assign macro_write_enable =
        macro_select_a ?
            port_a_write_enable :
            1'b0;
    assign macro_word_address =
        macro_select_a ?
            port_a_byte_address[10:2] :
            port_b_word_address;
    assign macro_bweb =
        (port_a_byte_address[1:0] == 2'd0) ? 32'hFFFF_FF00 :
        (port_a_byte_address[1:0] == 2'd1) ? 32'hFFFF_00FF :
        (port_a_byte_address[1:0] == 2'd2) ? 32'hFF00_FFFF :
                                             32'h00FF_FFFF;

    assign port_a_read_data = macro_read_data;
    assign port_b_read_data = macro_read_data;

    TS1N16ADFPCLLLVTA512X45M4SWSHOD u_packet_sram (
         .SLP     (1'b0)
        ,.DSLP    (1'b0)
        ,.SD      (1'b0)
        ,.PUDELAY ()
        ,.CLK     (clk)
        ,.CEB     (~macro_enable)
        ,.WEB     (~macro_write_enable)
        ,.A       ({5'h00, macro_word_address})
        ,.D       ({4{port_a_write_data}})
        ,.BWEB      (macro_write_enable ?
                     macro_bweb : 32'hFFFF_FFFF)
        ,.RTSEL   (2'b01)
        ,.WTSEL   (2'b01)
        ,.Q       (macro_read_data)
    );

    always_ff @(posedge clk or posedge rst) begin
        if (rst || flush) begin
            port_a_read_valid <= 1'b0;
            port_b_read_valid <= 1'b0;
        end else begin
            port_a_read_valid <=
                macro_select_a && !port_a_write_enable;
            port_b_read_valid <=
                macro_select_b;
        end
    end

`else

    logic [31:0] memory [0:511];

    assign port_a_ready = 1'b1;
    assign port_b_ready = 1'b1;

    always_ff @(posedge clk or posedge rst) begin
        if (rst || flush) begin
            port_a_read_valid <= 1'b0;
            port_b_read_valid <= 1'b0;
        end else begin
            port_a_read_valid <=
                port_a_request && !port_a_write_enable;
            port_b_read_valid <=
                port_b_request;
        end
    end

    always_ff @(posedge clk) begin
        if (port_a_request) begin
            if (port_a_write_enable) begin
                case (port_a_byte_address[1:0])
                    2'd0:
                        memory[port_a_byte_address[10:2]][7:0]
                            <= port_a_write_data;
                    2'd1:
                        memory[port_a_byte_address[10:2]][15:8]
                            <= port_a_write_data;
                    2'd2:
                        memory[port_a_byte_address[10:2]][23:16]
                            <= port_a_write_data;
                    default:
                        memory[port_a_byte_address[10:2]][31:24]
                            <= port_a_write_data;
                endcase
            end else begin
                port_a_read_data <=
                    memory[port_a_byte_address[10:2]];
            end
        end

        if (port_b_request) begin
            port_b_read_data <=
                memory[port_b_word_address];
        end
    end

`endif

endmodule
