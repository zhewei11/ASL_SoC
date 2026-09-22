module LD_filter (
     input  [3:0]  use_mem_type
    ,input  [31:0] mem_read_data
    ,input  [1:0]  addr_offset
    ,output reg [31:0] load_result
);

    localparam MEM_LW   = 4'b0100;
    localparam MEM_LH   = 4'b0101;
    localparam MEM_LB   = 4'b0110;
    localparam MEM_LBU  = 4'b0111;
    localparam MEM_LHU  = 4'b1100;

    always @(*) begin
        load_result = 32'h0;
        case (use_mem_type)
            MEM_LW: begin
                load_result = mem_read_data;
            end

            MEM_LH: begin
                case (addr_offset[1])
                    1'b0: load_result = {{16{mem_read_data[15]}}, mem_read_data[15:0]};
                    1'b1: load_result = {{16{mem_read_data[31]}}, mem_read_data[31:16]};

                endcase
            end

            MEM_LHU: begin
                case (addr_offset[1])
                    1'b0: load_result = {16'h0, mem_read_data[15:0]};
                    1'b1: load_result = {16'h0, mem_read_data[31:16]};

                endcase
            end

            MEM_LB: begin
                case (addr_offset)
                    2'b00: load_result = {{24{mem_read_data[7]}}, mem_read_data[7:0]};
                    2'b01: load_result = {{24{mem_read_data[15]}}, mem_read_data[15:8]};
                    2'b10: load_result = {{24{mem_read_data[23]}}, mem_read_data[23:16]};
                    2'b11: load_result = {{24{mem_read_data[31]}}, mem_read_data[31:24]};
                endcase
            end

            MEM_LBU: begin
                case (addr_offset)
                    2'b00: load_result = {24'h0, mem_read_data[7:0]};
                    2'b01: load_result = {24'h0, mem_read_data[15:8]};
                    2'b10: load_result = {24'h0, mem_read_data[23:16]};
                    2'b11: load_result = {24'h0, mem_read_data[31:24]};
                endcase
            end

            default: load_result = mem_read_data;
        endcase
    end

endmodule
