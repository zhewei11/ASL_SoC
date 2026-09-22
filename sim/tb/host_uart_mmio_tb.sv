`timescale 1ns/1ps

module host_uart_mmio_tb;
    localparam int BIT_CYCLES = 10;
    logic clk = 0;
    logic rst = 1;
    always #5 clk = ~clk;

    logic mmio_valid = 0, mmio_ready, mmio_write = 0;
    logic [31:0] mmio_addr = 0, mmio_wdata = 0, mmio_rdata;
    logic [3:0] mmio_wstrb = 0;
    logic uart_rx = 1, uart_tx, irq;
    logic [7:0] captured_tx;
    logic captured_stop;
    int checks;
    int bit_index;

    host_uart_mmio #(.CLOCK_HZ(100), .BAUD_RATE(10)) dut (.*);

    task automatic check(input logic condition, input string message);
        if (!condition) begin
            $error("FAIL: %s", message);
            $fatal(1);
        end
        checks++;
        $display("PASS: %s", message);
    endtask

    task automatic write_reg(input logic [7:0] offset,
                             input logic [31:0] data);
        @(negedge clk);
        mmio_valid = 1;
        mmio_write = 1;
        mmio_addr = {24'd0, offset};
        mmio_wdata = data;
        mmio_wstrb = 4'hF;
        while (!mmio_ready) @(negedge clk);
        @(posedge clk);
        @(negedge clk);
        mmio_valid = 0;
        mmio_write = 0;
        mmio_wstrb = 0;
    endtask

    task automatic read_reg(input logic [7:0] offset,
                            output logic [31:0] data);
        @(negedge clk);
        mmio_valid = 1;
        mmio_write = 0;
        mmio_addr = {24'd0, offset};
        while (!mmio_ready) @(negedge clk);
        #1 data = mmio_rdata;
        @(posedge clk);
        @(negedge clk);
        mmio_valid = 0;
    endtask

    task automatic capture_tx_byte;
        @(negedge uart_tx);
        repeat (BIT_CYCLES/2) @(posedge clk);
        check(!uart_tx, "UART TX start bit is low");
        for (bit_index = 0; bit_index < 8; bit_index++) begin
            repeat (BIT_CYCLES) @(posedge clk);
            captured_tx[bit_index] = uart_tx;
        end
        repeat (BIT_CYCLES) @(posedge clk);
        captured_stop = uart_tx;
    endtask

    task automatic drive_rx_byte(input logic [7:0] data,
                                 input logic stop_bit);
        @(negedge clk);
        uart_rx = 0;
        repeat (BIT_CYCLES) @(posedge clk);
        for (bit_index = 0; bit_index < 8; bit_index++) begin
            @(negedge clk);
            uart_rx = data[bit_index];
            repeat (BIT_CYCLES) @(posedge clk);
        end
        @(negedge clk);
        uart_rx = stop_bit;
        repeat (BIT_CYCLES) @(posedge clk);
        @(negedge clk);
        uart_rx = 1;
        repeat (3) @(posedge clk);
    endtask

    logic [31:0] value;
    initial begin
        repeat (5) @(posedge clk);
        rst <= 0;

        read_reg(8'h00, value);
        check(value == 32'h5541_5254, "UART ID register");
        read_reg(8'h10, value);
        check(value == BIT_CYCLES, "UART rounded baud divisor");
        read_reg(8'h04, value);
        check(value[0] && !value[1], "UART reset state is TX ready");

        write_reg(8'h14, 32'h1);
        fork
            write_reg(8'h08, 32'hA5);
            capture_tx_byte();
        join
        check(captured_tx == 8'hA5 && captured_stop,
              "UART TX serializes LSB-first data and stop bit");
        wait (irq);
        read_reg(8'h18, value);
        check(value[0], "UART TX-done IRQ status");
        write_reg(8'h18, 32'h1);
        check(!irq, "UART TX-done IRQ clears by W1C");

        write_reg(8'h14, 32'h6);
        drive_rx_byte(8'h3C, 1'b1);
        check(irq, "UART RX-valid raises enabled IRQ");
        read_reg(8'h04, value);
        check(value[2] && !value[3], "UART receives frame without error");
        read_reg(8'h0C, value);
        check(value[7:0] == 8'h3C, "UART RX data is software-readable");
        read_reg(8'h04, value);
        check(!value[2], "UART RX read consumes pending byte");

        drive_rx_byte(8'h11, 1'b1);
        drive_rx_byte(8'h22, 1'b1);
        read_reg(8'h04, value);
        check(value[4] && value[2], "UART RX overrun is latched");
        read_reg(8'h0C, value);
        check(value[7:0] == 8'h11, "UART overrun preserves oldest byte");
        write_reg(8'h18, 32'h4);
        read_reg(8'h04, value);
        check(!value[4], "UART error W1C clears overrun latch");

        drive_rx_byte(8'h55, 1'b0);
        read_reg(8'h04, value);
        check(value[3] && value[5], "UART framing error is latched and raises IRQ");
        write_reg(8'h18, 32'h4);
        read_reg(8'h04, value);
        check(!value[3], "UART error W1C clears framing latch");

        $display("Host UART MMIO regression: %0d checks passed", checks);
        $finish;
    end

    initial begin
        #100_000;
        $fatal(1, "UART regression timeout");
    end
endmodule
