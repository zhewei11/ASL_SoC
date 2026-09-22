`timescale 1ns/1ps

module cnn_input_dma_tb;

    logic clk = 1'b0;
    logic rst = 1'b1;
    always #5 clk = ~clk;

    logic        start = 1'b0;
    logic [31:0] input_address = 32'd0;
    logic [31:0] input_bytes = 32'd0;
    logic        busy;
    logic        done;
    logic        error;
    logic [31:0] checksum;
    logic [31:0] bytes_read;
    logic        data_valid;
    logic        data_ready = 1'b1;
    logic [31:0] data;
    logic [3:0]  data_keep;
    logic        data_last;

    logic [3:0]  m_axi_arid;
    logic [31:0] m_axi_araddr;
    logic [7:0]  m_axi_arlen;
    logic [2:0]  m_axi_arsize;
    logic [1:0]  m_axi_arburst;
    logic        m_axi_arvalid;
    logic        m_axi_arready = 1'b1;
    logic [3:0]  m_axi_rid = 4'd0;
    logic [31:0] m_axi_rdata = 32'd0;
    logic [1:0]  m_axi_rresp = 2'd0;
    logic        m_axi_rlast = 1'b0;
    logic        m_axi_rvalid = 1'b0;
    logic        m_axi_rready;

    integer checks = 0;
    integer ar_handshakes = 0;
    integer stream_beats = 0;
    logic [3:0] final_stream_keep = 4'd0;
    integer timeout;

    cnn_input_dma #(
         .MAX_INPUT_BYTES (32)
        ,.MAX_BURST_BEATS (4)
        ,.AXI_ID          (4'd3)
    ) dut (.*);

    always @(posedge clk) begin
        if (!rst && m_axi_arvalid && m_axi_arready)
            ar_handshakes <= ar_handshakes + 1;
        if (!rst && data_valid && data_ready) begin
            stream_beats <= stream_beats + 1;
            if (data_last)
                final_stream_keep <= data_keep;
        end
    end

    task automatic check(input logic condition, input string message);
        if (!condition) begin
            $error("FAIL: %s", message);
            $fatal(1);
        end
        checks++;
        $display("PASS: %s", message);
    endtask

    task automatic launch(
         input logic [31:0] address
        ,input logic [31:0] bytes
    );
        begin
            @(negedge clk);
            input_address = address;
            input_bytes = bytes;
            start = 1'b1;
            @(negedge clk);
            start = 1'b0;
        end
    endtask

    task automatic wait_for_done;
        begin
            timeout = 0;
            while (!done && timeout < 100) begin
                @(negedge clk);
                timeout++;
            end
            if (timeout >= 100)
                $fatal(1, "DMA completion timeout");
        end
    endtask

    task automatic begin_burst(
         input logic [31:0] expected_address
        ,input logic [7:0]  expected_length
    );
        begin
            while (!(m_axi_arvalid && m_axi_arready))
                @(negedge clk);
            check(m_axi_araddr == expected_address &&
                  m_axi_arid == 4'd3 &&
                  m_axi_arlen == expected_length &&
                  m_axi_arsize == 3'd2 &&
                  m_axi_arburst == 2'b01,
                  "DMA issues the expected AXI INCR burst");
            @(negedge clk);
        end
    endtask

    task automatic send_read_beat(
         input logic [31:0] data
        ,input logic [3:0]  response_id
        ,input logic [1:0]  response
        ,input logic        response_last
    );
        begin
            m_axi_rid = response_id;
            m_axi_rdata = data;
            m_axi_rresp = response;
            m_axi_rlast = response_last;
            m_axi_rvalid = 1'b1;
            while (!m_axi_rready)
                @(negedge clk);
            @(negedge clk);
            m_axi_rvalid = 1'b0;
            m_axi_rlast = 1'b0;
            m_axi_rresp = 2'b00;
        end
    endtask

    initial begin
        repeat (4) @(posedge clk);
        rst = 1'b0;

        launch(32'h2000_0000, 0);
        wait_for_done();
        check(error && !busy, "zero-byte DMA request is rejected");
        check(ar_handshakes == 0, "invalid request does not reach AXI");

        launch(32'h2000_0002, 4);
        wait_for_done();
        check(error && ar_handshakes == 0,
              "unaligned DMA address is rejected before AXI");

        launch(32'h2000_0000, 33);
        wait_for_done();
        check(error && ar_handshakes == 0,
              "DMA length above configured maximum is rejected");

        fork
            begin
                launch(32'h2000_0040, 10);
                wait_for_done();
            end
            begin
                begin_burst(32'h2000_0040, 8'd2);
                send_read_beat(32'h4433_2211, 4'd3, 2'b00, 1'b0);
                send_read_beat(32'h8877_6655, 4'd3, 2'b00, 1'b0);
                send_read_beat(32'hccbb_aa99, 4'd3, 2'b00, 1'b1);
            end
        join
        check(!error && !busy, "partial final word completes cleanly");
        check(bytes_read == 10, "DMA reports the exact byte count");
        check(checksum ==
              (32'h4433_2211 ^ 32'h8877_6655 ^ 32'h0000_aa99),
              "final partial word is masked before checksum accumulation");
        check(stream_beats == 3 && final_stream_keep == 4'b0011,
              "MM2S stream marks the final partial beat correctly");

        ar_handshakes = 0;
        fork
            begin
                launch(32'h2000_0080, 24);
                wait_for_done();
            end
            begin
                begin_burst(32'h2000_0080, 8'd3);
                send_read_beat(32'h0000_0001, 4'd3, 2'b00, 1'b0);
                send_read_beat(32'h0000_0002, 4'd3, 2'b00, 1'b0);
                send_read_beat(32'h0000_0004, 4'd3, 2'b00, 1'b0);
                send_read_beat(32'h0000_0008, 4'd3, 2'b00, 1'b1);
                begin_burst(32'h2000_0090, 8'd1);
                send_read_beat(32'h0000_0010, 4'd3, 2'b00, 1'b0);
                send_read_beat(32'h0000_0020, 4'd3, 2'b00, 1'b1);
            end
        join
        check(!error && bytes_read == 24 && ar_handshakes == 2,
              "long transfer is split into bounded bursts");
        check(checksum == 32'h0000_003f,
              "checksum spans every beat in multiple bursts");

        fork
            begin
                launch(32'h2000_00c0, 8);
                wait_for_done();
            end
            begin
                begin_burst(32'h2000_00c0, 8'd1);
                send_read_beat(32'h1234_5678, 4'd3, 2'b10, 1'b0);
            end
        join
        check(error && bytes_read == 0,
              "AXI read response error is propagated");

        fork
            begin
                launch(32'h2000_00d0, 8);
                wait_for_done();
            end
            begin
                begin_burst(32'h2000_00d0, 8'd1);
                send_read_beat(32'h1234_5678, 4'd2, 2'b00, 1'b0);
            end
        join
        check(error, "unexpected AXI response ID is rejected");

        fork
            begin
                launch(32'h2000_0ffc, 8);
                wait_for_done();
            end
            begin
                begin_burst(32'h2000_0ffc, 8'd0);
                send_read_beat(32'haaaa_5555, 4'd3, 2'b00, 1'b1);
                begin_burst(32'h2000_1000, 8'd0);
                send_read_beat(32'h5555_aaaa, 4'd3, 2'b00, 1'b1);
            end
        join
        check(!error && bytes_read == 8,
              "DMA splits bursts at the AXI 4 KiB boundary");

        $display("CNN burst DMA regression: %0d checks passed", checks);
        $finish;
    end

    initial begin
        #20_000;
        $fatal(1, "CNN input DMA global timeout");
    end

endmodule
