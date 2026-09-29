// Register File Module
module integer_register_file (
     input              clk
    ,input              rst
    // Read Ports
    ,input      [4:0]   rs1
    ,input      [4:0]   rs2
    ,input      [4:0]   rd_read
    ,output     [31:0]  read_data1
    ,output     [31:0]  read_data2
    ,output     [31:0]  read_data3
    // Write Port
    ,input      [4:0]   rd_write
    ,input      [31:0]  write_data
    ,input              write_enable
    // Halted-hart abstract debug port. Debug writes have priority because the
    // normal pipeline is empty before debug_halted is asserted.
    ,input      [4:0]   debug_addr
    ,input      [31:0]  debug_write_data
    ,input              debug_write_enable
    ,output     [31:0]  debug_read_data
);


    reg [31:0] registers [31:0];

    assign read_data1 = (rs1 == 5'd0) ? 32'h0 : registers[rs1];
    assign read_data2 = (rs2 == 5'd0) ? 32'h0 : registers[rs2];
    assign read_data3 = (rd_read == 5'd0)  ? 32'h0 : registers[rd_read];
    assign debug_read_data = (debug_addr == 5'd0) ? 32'h0 :
                             registers[debug_addr];


    integer i;
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            for (i = 0; i < 32; i = i + 1)
                registers[i] <= 32'h0;
        end
        else if (debug_write_enable && debug_addr != 5'd0) begin
            registers[debug_addr] <= debug_write_data;
        end
        else if (write_enable && rd_write != 5'd0) begin
            registers[rd_write] <= write_data;
        end
    end

endmodule
