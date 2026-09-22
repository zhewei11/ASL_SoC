`timescale 1ns/1ps
module ethernet_rx_dma_tb;
    logic clk = 0, rst = 1;
    always #5 clk = ~clk;
    logic eth_rx_valid, eth_rx_last, eth_rx_ready;
    logic [31:0] eth_rx_data;
    logic [3:0] eth_rx_keep;
    logic frame_done, frame_error;
    logic [31:0] frame_bytes, frame_checksum, frame_sequence;
    logic hold_after_frame, frame_release, frame_buffer_held;
    logic [3:0] awid, bid;
    logic [31:0] awaddr, wdata;
    logic [7:0] awlen;
    logic [2:0] awsize;
    logic [1:0] awburst, bresp;
    logic awvalid, awready = 1, wlast, wvalid, wready = 1;
    logic [3:0] wstrb;
    logic bvalid, bready;
    logic [1:0] response_code;
    logic wrong_response_id;
    integer checks, aw_count, write_beat_count;
    integer expected_write_beats, burst_write_beats;
    logic [31:0] max_awaddr;
    logic [7:0] max_awlen;
    logic bad_wlast;

    ethernet_rx_dma_shell #(
        .FRAME_BUFFER_BASE(32'h2000_0000), .MAX_FRAME_BYTES(8),
        .MAX_BURST_BEATS(2), .AXI_ID(4'h6)
    ) dut (
        .clk(clk), .rst(rst), .eth_rx_valid(eth_rx_valid),
        .eth_rx_data(eth_rx_data), .eth_rx_keep(eth_rx_keep),
        .eth_rx_last(eth_rx_last), .eth_rx_ready(eth_rx_ready),
        .frame_done(frame_done), .frame_error(frame_error),
        .frame_bytes(frame_bytes), .frame_checksum(frame_checksum),
        .frame_sequence(frame_sequence), .hold_after_frame(hold_after_frame),
        .frame_release(frame_release), .frame_buffer_held(frame_buffer_held),
        .m_axi_awid(awid),
        .m_axi_awaddr(awaddr), .m_axi_awlen(awlen),
        .m_axi_awsize(awsize), .m_axi_awburst(awburst),
        .m_axi_awvalid(awvalid), .m_axi_awready(awready),
        .m_axi_wdata(wdata), .m_axi_wstrb(wstrb), .m_axi_wlast(wlast),
        .m_axi_wvalid(wvalid), .m_axi_wready(wready), .m_axi_bid(bid),
        .m_axi_bresp(bresp), .m_axi_bvalid(bvalid), .m_axi_bready(bready)
    );

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            bvalid <= 0; bid <= 0; bresp <= 0;
            aw_count <= 0; max_awaddr <= 0; max_awlen <= 0;
            write_beat_count <= 0; expected_write_beats <= 0;
            burst_write_beats <= 0; bad_wlast <= 0;
        end else begin
            if (awvalid && awready) begin
                aw_count <= aw_count + 1;
                expected_write_beats <= awlen + 1;
                burst_write_beats <= 0;
                if (awaddr > max_awaddr) max_awaddr <= awaddr;
                if (awlen > max_awlen) max_awlen <= awlen;
            end
            if (wvalid && wready) begin
                write_beat_count <= write_beat_count + 1;
                burst_write_beats <= burst_write_beats + 1;
                if (wlast != (burst_write_beats + 1 == expected_write_beats))
                    bad_wlast <= 1'b1;
                if (wlast) begin
                    bvalid <= 1;
                    bid <= wrong_response_id ? 4'h7 : 4'h6;
                    bresp <= response_code;
                end
            end else if (bvalid && bready) begin
                bvalid <= 0;
            end
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

    task automatic reset_dut;
        begin
            rst = 1; eth_rx_valid = 0; eth_rx_last = 0;
            response_code = 0; wrong_response_id = 0;
            hold_after_frame = 0; frame_release = 0;
            repeat (3) @(posedge clk);
            @(negedge clk); rst = 0;
        end
    endtask

    task automatic send_word(input logic [31:0] data,
                              input logic [3:0] keep, input logic last);
        begin
            @(negedge clk);
            eth_rx_valid = 1; eth_rx_data = data;
            eth_rx_keep = keep; eth_rx_last = last;
            while (!eth_rx_ready) @(negedge clk);
            @(negedge clk);
            eth_rx_valid = 0; eth_rx_last = 0;
        end
    endtask

    task automatic wait_done;
        integer timeout;
        begin
            timeout = 0;
            while (!frame_done && timeout < 30) begin
                @(posedge clk); timeout++;
            end
            check(timeout < 30, "frame terminates without hanging");
        end
    endtask

    initial begin
        checks = 0; eth_rx_data = 0; eth_rx_keep = 0;
        reset_dut();
        send_word(32'h4433_2211, 4'hf, 0);
        send_word(32'h0000_6655, 4'h3, 1);
        wait_done();
        check(!frame_error && frame_bytes == 6,
              "valid partial final word completes with exact byte count");
        check(frame_checksum == 32'h4433_4444,
              "checksum masks unused final byte lanes");
        check(aw_count == 1 && max_awaddr == 32'h2000_0000 &&
              max_awlen == 1 && write_beat_count == 2 && !bad_wlast,
              "valid frame is written as one two-beat AXI burst");

        reset_dut(); hold_after_frame = 1;
        send_word(32'hfeed_cafe, 4'hf, 1);
        wait_done();
        check(frame_buffer_held && !eth_rx_ready,
              "completed auto-CNN frame holds its buffer against overwrite");
        @(negedge clk); frame_release = 1;
        @(posedge clk); @(negedge clk); frame_release = 0;
        check(!frame_buffer_held && eth_rx_ready,
              "CNN release returns buffer ownership to Ethernet DMA");

        reset_dut();
        send_word(32'h1111_1111, 4'hf, 0);
        send_word(32'h2222_2222, 4'hf, 0);
        send_word(32'h3333_3333, 4'hf, 1);
        wait_done();
        check(frame_error, "oversize frame is rejected");
        check(aw_count == 1 && max_awaddr == 32'h2000_0000 &&
              write_beat_count == 2,
              "oversize frame writes only its in-range burst");

        reset_dut();
        send_word(32'hdead_beef, 4'h0, 1);
        wait_done();
        check(frame_error && aw_count == 0,
              "zero-byte beat is rejected without any AXI write");

        reset_dut(); response_code = 2'b10;
        send_word(32'h1234_5678, 4'hf, 1);
        wait_done();
        check(frame_error, "AXI write response error propagates to frame status");

        reset_dut(); wrong_response_id = 1;
        send_word(32'h1234_5678, 4'hf, 1);
        wait_done();
        check(frame_error, "unexpected AXI response ID is rejected");

        $display("Ethernet RX DMA regression: %0d checks passed", checks);
        $finish;
    end
endmodule
