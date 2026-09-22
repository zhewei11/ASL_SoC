`include "asl_soc_config.svh"

module soc_mmio_subsystem #(
     parameter logic [31:0] MMIO_BASE = `ASL_SOC_MMIO_BASE
    ,parameter logic [31:0] MMIO_BYTES = `ASL_SOC_MMIO_BYTES
    ,parameter logic [15:0] DEFAULT_POSE_MAX_STEP =
        16'(`ASL_SOC_DEFAULT_MAX_STEP)
    ,parameter logic [7:0] DEFAULT_HAND_ID = 8'd110
) (
     input  logic        clk
    ,input  logic        rst
    // MMIO interface
    ,input  logic        mmio_valid
    ,output logic        mmio_ready
    ,input  logic        mmio_write
    ,input  logic [31:0] mmio_addr
    ,input  logic [31:0] mmio_wdata
    ,input  logic [3:0]  mmio_wstrb
    ,output logic [31:0] mmio_rdata
    ,output logic        mmio_error
    // Protocol interface
    ,output logic        protocol_valid
    ,input  logic        protocol_ready
    ,output logic        protocol_write
    ,output logic [31:0] protocol_addr
    ,output logic [31:0] protocol_wdata
    ,output logic [3:0]  protocol_wstrb
    ,input  logic [31:0] protocol_rdata
    // Interrupt interface
    ,output logic        interrupt_valid
    ,input  logic        interrupt_ready
    ,output logic        interrupt_write
    ,output logic [31:0] interrupt_addr
    ,output logic [31:0] interrupt_wdata
    ,output logic [3:0]  interrupt_wstrb
    ,input  logic [31:0] interrupt_rdata
    // Timer interface
    ,output logic        timer_valid
    ,input  logic        timer_ready
    ,output logic        timer_write
    ,output logic [31:0] timer_addr
    ,output logic [31:0] timer_wdata
    ,output logic [3:0]  timer_wstrb
    ,input  logic [31:0] timer_rdata
    // UART interface
    ,output logic        uart_valid
    ,input  logic        uart_ready
    ,output logic        uart_write
    ,output logic [31:0] uart_addr
    ,output logic [31:0] uart_wdata
    ,output logic [3:0]  uart_wstrb
    ,input  logic [31:0] uart_rdata
    // CNN interface
    ,output logic        cnn_manual_start
    ,output logic        cnn_auto_start_enable
    ,output logic        cnn_clear_irq
    ,output logic [31:0] cnn_input_address
    ,output logic [31:0] cnn_input_bytes
    ,output logic        cnn_force_class_valid
    ,output logic [7:0]  cnn_force_class_id
    ,output logic [7:0]  cnn_force_confidence
    ,input  logic        cnn_busy
    ,input  logic        cnn_done
    ,input  logic        cnn_error
    ,input  logic        cnn_irq
    ,input  logic [7:0]  cnn_class_id
    ,input  logic [7:0]  cnn_confidence
    ,input  logic [31:0] cnn_result_sequence
    ,input  logic [31:0] cnn_dma_checksum
    ,input  logic [31:0] cnn_dma_bytes_read
    // Ethernet interface
    ,input  logic        ethernet_frame_done
    ,input  logic        ethernet_frame_error
    ,input  logic [31:0] ethernet_frame_bytes
    ,input  logic [31:0] ethernet_frame_checksum
    ,input  logic [31:0] ethernet_frame_sequence
    ,input  logic        ethernet_frame_buffer_held
    // Pose interface
    ,output logic        pose_manual_target_valid
    ,output logic [7:0]  pose_manual_class_id
    ,output logic [15:0] pose_max_step
    ,output logic [7:0]  pose_hand_id
    ,input  logic        pose_frame_busy
    ,input  logic [7:0]  pose_active_class_id
    ,input  logic [31:0] pose_command_sequence
    ,input  logic        pose_protocol_present
    ,input  logic        pose_protocol_busy
    ,input  logic        pose_protocol_error
    ,input  logic        pose_protocol_bank
    ,input  logic [31:0] pose_protocol_sequence
    // Safety interface
    ,output logic        software_torque_request
    ,output logic        software_watchdog_enable
    ,output logic        software_watchdog_kick
    ,output logic        software_safety_clear
    ,input  logic        torque_enable_allow
    ,input  logic        rs485_de_inhibit
    ,input  logic        watchdog_fault
    ,input  logic        safety_fault_latched
);

    localparam logic [3:0] PAGE_PROTOCOL = 4'h0;
    localparam logic [3:0] PAGE_INTERRUPT = 4'h1;
    localparam logic [3:0] PAGE_CNN      = 4'h2;
    localparam logic [3:0] PAGE_ETH      = 4'h3;
    localparam logic [3:0] PAGE_TIMER    = 4'h4;
    localparam logic [3:0] PAGE_POSE     = 4'h5;
    localparam logic [3:0] PAGE_SAFETY   = 4'h6;
    localparam logic [3:0] PAGE_UART     = 4'h7;

    logic        address_in_window;
    logic [3:0]  page;
    logic [11:0] page_offset;
    logic        protocol_select;
    logic        interrupt_select;
    logic        timer_select;
    logic        uart_select;
    logic        local_handshake;
    logic [31:0] cnn_class_config;

    function automatic logic in_region(
         input logic [31:0] address
        ,input logic [31:0] base
        ,input logic [31:0] bytes
    );
        logic [32:0] address_ext;
        logic [32:0] limit_ext;
        begin
            address_ext = {1'b0, address};
            limit_ext = {1'b0, base} + {1'b0, bytes};
            in_region = address_ext >= {1'b0, base} && address_ext < limit_ext;
        end
    endfunction

    function automatic logic [31:0] merge_wstrb(
         input logic [31:0] old_value
        ,input logic [31:0] new_value
        ,input logic [3:0] strobe
    );
        integer lane;
        begin
            merge_wstrb = old_value;
            for (lane = 0; lane < 4; lane = lane + 1)
                if (strobe[lane])
                    merge_wstrb[lane*8 +: 8] = new_value[lane*8 +: 8];
        end
    endfunction

    assign address_in_window = in_region(mmio_addr, MMIO_BASE, MMIO_BYTES);
    assign page = mmio_addr[15:12];
    assign page_offset = mmio_addr[11:0];
    assign protocol_select = address_in_window && page == PAGE_PROTOCOL;
    assign interrupt_select = address_in_window && page == PAGE_INTERRUPT;
    assign timer_select = address_in_window && page == PAGE_TIMER;
    assign uart_select = address_in_window && page == PAGE_UART;
    assign protocol_valid = mmio_valid && protocol_select;
    assign protocol_write = mmio_write;
    assign protocol_addr = mmio_addr;
    assign protocol_wdata = mmio_wdata;
    assign protocol_wstrb = mmio_wstrb;
    assign interrupt_valid = mmio_valid && interrupt_select;
    assign interrupt_write = mmio_write;
    assign interrupt_addr = mmio_addr;
    assign interrupt_wdata = mmio_wdata;
    assign interrupt_wstrb = mmio_wstrb;
    assign timer_valid = mmio_valid && timer_select;
    assign timer_write = mmio_write;
    assign timer_addr = mmio_addr;
    assign timer_wdata = mmio_wdata;
    assign timer_wstrb = mmio_wstrb;
    assign uart_valid = mmio_valid && uart_select;
    assign uart_write = mmio_write;
    assign uart_addr = mmio_addr;
    assign uart_wdata = mmio_wdata;
    assign uart_wstrb = mmio_wstrb;
    assign mmio_ready = protocol_select ? protocol_ready :
                        interrupt_select ? interrupt_ready :
                        timer_select ? timer_ready :
                        uart_select ? uart_ready : mmio_valid;
    assign local_handshake = mmio_valid && mmio_ready &&
                             !protocol_select && !interrupt_select &&
                             !timer_select && !uart_select;

    always_comb begin
        mmio_rdata = 32'd0;
        mmio_error = mmio_valid && (!address_in_window ||
                     !((page == PAGE_PROTOCOL) || (page == PAGE_INTERRUPT) ||
                       (page == PAGE_CNN) ||
                       (page == PAGE_ETH) || (page == PAGE_POSE) ||
                       (page == PAGE_TIMER) || (page == PAGE_SAFETY) ||
                       (page == PAGE_UART)));
        if (protocol_select) begin
            mmio_rdata = protocol_rdata;
        end else if (interrupt_select) begin
            mmio_rdata = interrupt_rdata;
        end else if (timer_select) begin
            mmio_rdata = timer_rdata;
        end else if (uart_select) begin
            mmio_rdata = uart_rdata;
        end else if (address_in_window) begin
            case (page)
                PAGE_CNN: case (page_offset)
                    12'h000: mmio_rdata = {30'd0, cnn_auto_start_enable, 1'b0};
                    12'h004: mmio_rdata =
                        {27'd0, cnn_irq, cnn_error, cnn_done, cnn_busy, 1'b0};
                    12'h008: mmio_rdata = cnn_input_address;
                    12'h00C: mmio_rdata = cnn_input_bytes;
                    12'h010: mmio_rdata = ethernet_frame_checksum;
                    12'h014: mmio_rdata = cnn_class_config;
                    12'h018: mmio_rdata =
                        {16'd0, cnn_confidence, cnn_class_id};
                    12'h01C: mmio_rdata = cnn_result_sequence;
                    12'h020: mmio_rdata = cnn_dma_checksum;
                    12'h024: mmio_rdata = cnn_dma_bytes_read;
                    default: mmio_rdata = 32'd0;
                endcase
                PAGE_ETH: case (page_offset)
                    12'h000: mmio_rdata =
                        {29'd0, ethernet_frame_buffer_held,
                         ethernet_frame_error, ethernet_frame_done};
                    12'h004: mmio_rdata = `ASL_SOC_ETH_FRAME_BUFFER_BASE;
                    12'h008: mmio_rdata = `ASL_SOC_ETH_MAX_FRAME_BYTES;
                    12'h00C: mmio_rdata = ethernet_frame_bytes;
                    12'h010: mmio_rdata = ethernet_frame_checksum;
                    12'h014: mmio_rdata = ethernet_frame_sequence;
                    default: mmio_rdata = 32'd0;
                endcase
                PAGE_POSE: case (page_offset)
                    12'h004: mmio_rdata =
                        {15'd0, pose_frame_busy, 8'd0, pose_active_class_id};
                    12'h008: mmio_rdata = {24'd0, pose_manual_class_id};
                    12'h00C: mmio_rdata = {16'd0, pose_max_step};
                    12'h010: mmio_rdata = pose_command_sequence;
                    12'h014: mmio_rdata = {
                        28'd0, pose_protocol_bank, pose_protocol_error,
                        pose_protocol_busy, pose_protocol_present
                    };
                    12'h018: mmio_rdata = pose_protocol_sequence;
                    12'h01C: mmio_rdata = {24'd0, pose_hand_id};
                    default: mmio_rdata = 32'd0;
                endcase
                PAGE_SAFETY: case (page_offset)
                    12'h000: mmio_rdata = {
                        26'd0, software_watchdog_enable,
                        software_torque_request, safety_fault_latched,
                        watchdog_fault, rs485_de_inhibit, torque_enable_allow
                    };
                    12'h004: mmio_rdata = {
                        30'd0, software_watchdog_enable,
                        software_torque_request
                    };
                    default: mmio_rdata = 32'd0;
                endcase
                default: mmio_rdata = 32'd0;
            endcase
        end
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            cnn_manual_start          <= 1'b0;
            cnn_auto_start_enable     <= 1'b1;
            cnn_clear_irq             <= 1'b0;
            cnn_input_address         <= `ASL_SOC_ETH_FRAME_BUFFER_BASE;
            cnn_input_bytes           <= `ASL_SOC_ETH_MAX_FRAME_BYTES;
            cnn_force_class_valid     <= 1'b0;
            cnn_force_class_id        <= 8'd0;
            cnn_force_confidence      <= 8'd128;
            cnn_class_config          <= 32'h0000_8000;
            pose_manual_target_valid  <= 1'b0;
            pose_manual_class_id      <= 8'd0;
            pose_max_step             <= DEFAULT_POSE_MAX_STEP;
            pose_hand_id              <= DEFAULT_HAND_ID;
            software_torque_request   <= 1'b1;
            software_watchdog_enable  <= 1'b0;
            software_watchdog_kick    <= 1'b0;
            software_safety_clear     <= 1'b0;
        end else begin
            cnn_manual_start         <= 1'b0;
            cnn_clear_irq            <= 1'b0;
            pose_manual_target_valid <= 1'b0;
            software_watchdog_kick   <= 1'b0;
            software_safety_clear    <= 1'b0;

            if (local_handshake && mmio_write && |mmio_wstrb) begin
                case (page)
                    PAGE_CNN: case (page_offset)
                        12'h000: if (mmio_wstrb[0]) begin
                            cnn_manual_start      <= mmio_wdata[0];
                            cnn_auto_start_enable <= mmio_wdata[1];
                            cnn_clear_irq         <= mmio_wdata[2];
                        end
                        12'h008: cnn_input_address <= merge_wstrb(
                            cnn_input_address, mmio_wdata, mmio_wstrb
                        );
                        12'h00C: cnn_input_bytes <= merge_wstrb(
                            cnn_input_bytes, mmio_wdata, mmio_wstrb
                        );
                        12'h014: begin
                            cnn_class_config <= merge_wstrb(
                                cnn_class_config, mmio_wdata, mmio_wstrb
                            );
                            if (mmio_wstrb[0])
                                cnn_force_class_id <= mmio_wdata[7:0];
                            if (mmio_wstrb[1])
                                cnn_force_confidence <= mmio_wdata[15:8];
                            if (mmio_wstrb[3])
                                cnn_force_class_valid <= mmio_wdata[31];
                        end
                        default: begin end
                    endcase

                    PAGE_POSE: case (page_offset)
                        12'h000: if (mmio_wstrb[0])
                            pose_manual_target_valid <= mmio_wdata[0];
                        12'h008: if (mmio_wstrb[0])
                            pose_manual_class_id <= mmio_wdata[7:0];
                        12'h00C: begin
                            if (mmio_wstrb[0])
                                pose_max_step[7:0] <= mmio_wdata[7:0];
                            if (mmio_wstrb[1])
                                pose_max_step[15:8] <= mmio_wdata[15:8];
                        end
                        12'h01C: if (mmio_wstrb[0] &&
                                      (mmio_wdata[7:0] <= 8'd252))
                            pose_hand_id <= mmio_wdata[7:0];
                        default: begin end
                    endcase

                    PAGE_SAFETY: begin
                        if (page_offset == 12'h004 && mmio_wstrb[0]) begin
                            software_torque_request  <= mmio_wdata[0];
                            software_watchdog_enable <= mmio_wdata[1];
                            software_watchdog_kick   <= mmio_wdata[2];
                            software_safety_clear    <= mmio_wdata[3];
                        end
                    end

                    default: begin end
                endcase
            end
        end
    end

endmodule
