`ifdef ASL_SOC_SVA
module axi_master_assertions (
    input logic clk, input logic rst,
    input logic [3:0] awid, input logic [31:0] awaddr,
    input logic [7:0] awlen, input logic [2:0] awsize,
    input logic [1:0] awburst, input logic awvalid, input logic awready,
    input logic [31:0] wdata, input logic [3:0] wstrb,
    input logic wlast, input logic wvalid, input logic wready,
    input logic [3:0] arid, input logic [31:0] araddr,
    input logic [7:0] arlen, input logic [2:0] arsize,
    input logic [1:0] arburst, input logic arvalid, input logic arready
);
    property p_aw_stable_while_stalled;
        @(posedge clk) disable iff (rst)
            $past(awvalid && !awready) && awvalid && !awready |->
                $stable({awid, awaddr, awlen, awsize, awburst});
    endproperty
    property p_w_stable_while_stalled;
        @(posedge clk) disable iff (rst)
            $past(wvalid && !wready) && wvalid && !wready |->
                $stable({wdata, wstrb, wlast});
    endproperty
    property p_ar_stable_while_stalled;
        @(posedge clk) disable iff (rst)
            $past(arvalid && !arready) && arvalid && !arready |->
                $stable({arid, araddr, arlen, arsize, arburst});
    endproperty
    property p_word_accesses_only;
        @(posedge clk) disable iff (rst)
            (awvalid | arvalid) |->
            ((!awvalid || awsize == 3'd2) && (!arvalid || arsize == 3'd2));
    endproperty
    assert property (p_aw_stable_while_stalled);
    assert property (p_w_stable_while_stalled);
    assert property (p_ar_stable_while_stalled);
    assert property (p_word_accesses_only);
endmodule
`endif
