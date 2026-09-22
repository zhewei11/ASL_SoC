`include "asl_soc_config.svh"

module soc_core_top #(
     parameter int unsigned CPU_HZ                  = `ASL_SOC_CPU_HZ
    ,parameter int unsigned RT_FRAME_HZ             = `ASL_SOC_RT_FRAME_HZ
    ,parameter int unsigned MOTOR_COUNT             = `ASL_SOC_MOTOR_COUNT
    ,parameter int unsigned POSE_COUNT              = `ASL_SOC_POSE_COUNT
    ,parameter int unsigned ETH_MAX_FRAME_BYTES     = `ASL_SOC_ETH_MAX_FRAME_BYTES
    ,parameter int unsigned CNN_MAX_INPUT_BYTES     =
        `ASL_SOC_CNN_INPUT_WIDTH * `ASL_SOC_CNN_INPUT_HEIGHT *
        `ASL_SOC_CNN_INPUT_CHANNELS
    ,parameter int unsigned CNN_STUB_LATENCY_CYCLES = `ASL_SOC_CNN_STUB_LATENCY_CYCLES
    ,parameter int unsigned DMA_MAX_BURST_BEATS     = `ASL_SOC_DMA_MAX_BURST_BEATS
    ,parameter int unsigned WATCHDOG_TIMEOUT_CYCLES = CPU_HZ
    ,parameter int unsigned HOST_UART_BAUD = `ASL_SOC_UART_BAUD
    ,parameter int unsigned RT_FRAME_CYCLES_OVERRIDE = 0
    ,parameter bit ENABLE_CPU = 1'b1
    ,parameter bit ENABLE_CPU_FPU = 1'b1
    // CPU/RTOS is the sole Protocol command-bank producer in the revised
    // architecture. Set to 0 only for the autonomous hardware Pose Adapter
    // compatibility path or its directed verification.
    ,parameter bit CPU_OWNS_PROTOCOL_COMMANDS = 1'b1
    ,parameter bit USE_HX5_RT_SEQUENCER = 1'b1
    ,parameter BOOT_ROM_INIT_FILE = ""
    ,parameter ITCM_INIT_FILE = ""
    ,parameter DTCM_INIT_FILE = ""
    ,parameter logic [15:0] POSE_MAX_STEP           =
        16'(`ASL_SOC_DEFAULT_MAX_STEP)
    ,parameter logic [15:0] POSE_GOAL_CURRENT       = 16'd0
    ,parameter logic [31:0] POSE_GOAL_VELOCITY      = 32'd0
    ,parameter logic [31:0] POSE_PROFILE_ACCELERATION = 32'd0
    ,parameter logic [31:0] POSE_PROFILE_VELOCITY   = 32'd0
) (
     input  logic        clk
    ,input  logic        rst

    // External verification/debug MMIO requester. It owns MMIO only when
    // ENABLE_CPU=0; normal SoC builds use the internal RV32IMF CPU.
    ,input  logic        mmio_valid
    ,output logic        mmio_ready
    ,input  logic        mmio_write
    ,input  logic [31:0] mmio_addr
    ,input  logic [31:0] mmio_wdata
    ,input  logic [3:0]  mmio_wstrb
    ,output logic [31:0] mmio_rdata
    ,output logic        mmio_error

    // MAC-facing L2 payload stream. Preamble/SFD/FCS and PHY adaptation live
    // in the deferred board wrapper.
    ,input  logic        eth_rx_valid
    ,input  logic [31:0] eth_rx_data
    ,input  logic [3:0]  eth_rx_keep
    ,input  logic        eth_rx_last
    ,output logic        eth_rx_ready
    ,output logic        eth_tx_valid
    ,output logic [31:0] eth_tx_data
    ,output logic [3:0]  eth_tx_keep
    ,output logic        eth_tx_last
    ,input  logic        eth_tx_ready

    // Direct hardware safety boundary.
    ,input  logic        emergency_stop_n
    ,input  logic        external_fault
    ,input  logic        torque_enable_request
    ,input  logic        watchdog_enable
    ,input  logic        watchdog_kick
    ,input  logic        safety_clear_fault
    ,output logic        torque_enable_allow
    ,output logic        rs485_de_inhibit
    ,output logic        watchdog_fault
    ,output logic        safety_fault_latched

    // Verification override for the CNN stub result. Normal firmware starts
    // the accelerator and reads its result through MMIO.
    ,input  logic        cnn_test_class_valid
    ,input  logic [7:0]  cnn_test_class_id
    ,input  logic [7:0]  cnn_test_confidence
    ,input  logic        cnn_clear_irq
    ,output logic        cnn_busy
    ,output logic        cnn_done
    ,output logic        cnn_error
    ,output logic [7:0]  cnn_class_id
    ,output logic [7:0]  cnn_confidence
    ,output logic        cnn_irq

    // Pose Player observation/compatibility stream. In the default CPU-owned
    // Protocol mode this remains an external ready/valid interface; in the
    // compatibility mode the internal hardware adapter consumes it.
    ,output logic        protocol_command_valid
    ,input  logic        protocol_command_ready
    ,output logic [$clog2(MOTOR_COUNT)-1:0] protocol_motor_index
    ,output logic [15:0] protocol_command_position
    ,output logic        protocol_command_last
    ,output logic        protocol_command_commit
    ,output logic [31:0] protocol_command_sequence
    ,output logic        pose_frame_busy
    ,output logic [7:0]  pose_active_class_id

    // External AXI4 memory master shared by CPU I/D and the two-channel burst
    // DMA. DMA channel 0 writes Ethernet frames; channel 1 reads CNN inputs.
    ,output logic [3:0]  m_axi_awid
    ,output logic [31:0] m_axi_awaddr
    ,output logic [7:0]  m_axi_awlen
    ,output logic [2:0]  m_axi_awsize
    ,output logic [1:0]  m_axi_awburst
    ,output logic        m_axi_awvalid
    ,input  logic        m_axi_awready
    ,output logic [31:0] m_axi_wdata
    ,output logic [3:0]  m_axi_wstrb
    ,output logic        m_axi_wlast
    ,output logic        m_axi_wvalid
    ,input  logic        m_axi_wready
    ,input  logic [3:0]  m_axi_bid
    ,input  logic [1:0]  m_axi_bresp
    ,input  logic        m_axi_bvalid
    ,output logic        m_axi_bready
    ,output logic [3:0]  m_axi_arid
    ,output logic [31:0] m_axi_araddr
    ,output logic [7:0]  m_axi_arlen
    ,output logic [2:0]  m_axi_arsize
    ,output logic [1:0]  m_axi_arburst
    ,output logic        m_axi_arvalid
    ,input  logic        m_axi_arready
    ,input  logic [3:0]  m_axi_rid
    ,input  logic [31:0] m_axi_rdata
    ,input  logic [1:0]  m_axi_rresp
    ,input  logic        m_axi_rlast
    ,input  logic        m_axi_rvalid
    ,output logic        m_axi_rready

    ,output logic        ethernet_frame_irq
    ,output logic [31:0] ethernet_frame_bytes
    ,output logic [31:0] ethernet_frame_checksum

    ,input  logic        host_uart_rx
    ,output logic        host_uart_tx
    ,output logic        host_uart_irq

    ,input  logic        rs485_rx
    ,output logic        rs485_tx
    ,output logic        rs485_de
    ,output logic        protocol_irq
);

    localparam int unsigned RT_FRAME_CYCLES =
        (RT_FRAME_CYCLES_OVERRIDE != 0) ? RT_FRAME_CYCLES_OVERRIDE :
        ((RT_FRAME_HZ == 0) ? 1 : CPU_HZ / RT_FRAME_HZ);
    localparam logic [15:0] NEUTRAL_POSITION =
        16'(`ASL_SOC_NEUTRAL_POSITION);

    logic [15:0] protocol_goal_current;
    logic [31:0] protocol_goal_velocity;
    logic [31:0] protocol_profile_acceleration;
    logic [31:0] protocol_profile_velocity;

    // Frame and accelerator status.
    logic        frame_done;
    logic        frame_error;
    logic [31:0] frame_sequence;
    logic [31:0] cnn_result_sequence;
    logic [31:0] cnn_dma_checksum;
    logic [31:0] cnn_dma_bytes_read;
    logic        rt_frame_tick_pulse;

    // Protocol MMIO endpoint.
    logic        protocol_mmio_valid;
    logic        protocol_mmio_ready;
    logic        protocol_mmio_write;
    logic [31:0] protocol_mmio_addr;
    logic [31:0] protocol_mmio_wdata;
    logic [3:0]  protocol_mmio_wstrb;
    logic [31:0] protocol_mmio_rdata;

    // Shared Protocol bus and pose-command adapter.
    logic        protocol_bus_valid;
    logic        protocol_bus_ready;
    logic        protocol_bus_write;
    logic [31:0] protocol_bus_addr;
    logic [31:0] protocol_bus_wdata;
    logic [31:0] protocol_bus_rdata;
    logic [3:0]  protocol_bus_wstrb;
    logic        pose_protocol_mmio_valid;
    logic        pose_protocol_mmio_ready;
    logic        pose_protocol_mmio_write;
    logic [31:0] pose_protocol_mmio_addr;
    logic [31:0] pose_protocol_mmio_wdata;
    logic [3:0]  pose_protocol_mmio_wstrb;
    logic        pose_protocol_busy;
    logic        pose_protocol_error;
    logic        pose_protocol_bank;
    logic [31:0] pose_protocol_sequence;
    logic        pose_adapter_ready;

    // UART and external RS-485 signals.
    logic        uart_mmio_valid;
    logic        uart_mmio_ready;
    logic        uart_mmio_write;
    logic [31:0] uart_mmio_addr;
    logic [31:0] uart_mmio_wdata;
    logic [31:0] uart_mmio_rdata;
    logic [3:0]  uart_mmio_wstrb;
    logic        protocol_rs485_tx;
    logic        protocol_rs485_de;

    // Software-configurable CNN controls.
    logic        mmio_cnn_manual_start;
    logic        mmio_cnn_auto_start_enable;
    logic        mmio_cnn_clear_irq;
    logic [31:0] mmio_cnn_input_address;
    logic [31:0] mmio_cnn_input_bytes;
    logic        mmio_cnn_force_class_valid;
    logic [7:0]  mmio_cnn_force_class_id;
    logic [7:0]  mmio_cnn_force_confidence;

    // Pose and safety controls.
    logic        mmio_pose_target_valid;
    logic [7:0]  mmio_pose_class_id;
    logic [15:0] mmio_pose_max_step;
    logic [7:0]  mmio_pose_hand_id;
    logic        software_torque_request;
    logic        software_watchdog_enable;
    logic        software_watchdog_kick;
    logic        software_safety_clear;

    // Inputs selected between autonomous and software-controlled operation.
    logic        cnn_start_selected;
    logic [31:0] cnn_input_address_selected;
    logic [31:0] cnn_input_bytes_selected;
    logic        cnn_dma_start;
    logic [31:0] cnn_dma_input_address;
    logic [31:0] cnn_dma_input_bytes;
    logic        cnn_dma_busy;
    logic        cnn_dma_done;
    logic        cnn_dma_error;
    logic        cnn_dma_stream_valid;
    logic [31:0] cnn_dma_stream_data;
    logic [3:0]  cnn_dma_stream_keep;
    logic        cnn_dma_stream_last;
    logic        pose_target_valid_selected;
    logic [7:0]  pose_target_class_selected;

    // Four-slot AXI fabric: CPU I/D use slots 0/1 and DMA uses slot 2.
    logic [3:0][3:0]  fabric_awid;
    logic [3:0][31:0] fabric_awaddr;
    logic [3:0][7:0]  fabric_awlen;
    logic [3:0][2:0]  fabric_awsize;
    logic [3:0][1:0]  fabric_awburst;
    logic [3:0]       fabric_awvalid;
    logic [3:0]       fabric_awready;

    // Write data channel.
    logic [3:0][31:0] fabric_wdata;
    logic [3:0][3:0]  fabric_wstrb;
    logic [3:0]       fabric_wlast;
    logic [3:0]       fabric_wvalid;
    logic [3:0]       fabric_wready;

    // Write response channel.
    logic [3:0][3:0] fabric_bid;
    logic [3:0][1:0] fabric_bresp;
    logic [3:0]      fabric_bvalid;
    logic [3:0]      fabric_bready;

    // Read address channel.
    logic [3:0][3:0]  fabric_arid;
    logic [3:0][31:0] fabric_araddr;
    logic [3:0][7:0]  fabric_arlen;
    logic [3:0][2:0]  fabric_arsize;
    logic [3:0][1:0]  fabric_arburst;
    logic [3:0]       fabric_arvalid;
    logic [3:0]       fabric_arready;

    // Read data channel.
    logic [3:0][3:0]  fabric_rid;
    logic [3:0][31:0] fabric_rdata;
    logic [3:0][1:0]  fabric_rresp;
    logic [3:0]       fabric_rlast;
    logic [3:0]       fabric_rvalid;
    logic [3:0]       fabric_rready;

    // Multi-channel DMA write master (Ethernet S2MM channel).
    logic [3:0]  eth_axi_awid;
    logic [31:0] eth_axi_awaddr;
    logic [7:0]  eth_axi_awlen;
    logic [2:0]  eth_axi_awsize;
    logic [1:0]  eth_axi_awburst;
    logic        eth_axi_awvalid;
    logic        eth_axi_awready;
    logic [31:0] eth_axi_wdata;
    logic [3:0]  eth_axi_wstrb;
    logic        eth_axi_wlast;
    logic        eth_axi_wvalid;
    logic        eth_axi_wready;
    logic [3:0]  eth_axi_bid;
    logic [1:0]  eth_axi_bresp;
    logic        eth_axi_bvalid;
    logic        eth_axi_bready;

    // Multi-channel DMA read master (CNN MM2S channel).
    logic [3:0]  cnn_axi_arid;
    logic [31:0] cnn_axi_araddr;
    logic [7:0]  cnn_axi_arlen;
    logic [2:0]  cnn_axi_arsize;
    logic [1:0]  cnn_axi_arburst;
    logic        cnn_axi_arvalid;
    logic        cnn_axi_arready;
    logic [3:0]  cnn_axi_rid;
    logic [31:0] cnn_axi_rdata;
    logic [1:0]  cnn_axi_rresp;
    logic        cnn_axi_rlast;
    logic        cnn_axi_rvalid;
    logic        cnn_axi_rready;

    // Fabric arbitration state.
    logic [1:0] fabric_write_owner;
    logic [1:0] fabric_read_owner;

    // CPU MMIO bus.
    logic        cpu_mmio_valid;
    logic        cpu_mmio_ready;
    logic        cpu_mmio_write;
    logic [31:0] cpu_mmio_addr;
    logic [31:0] cpu_mmio_wdata;
    logic [31:0] cpu_mmio_rdata;
    logic [3:0]  cpu_mmio_wstrb;

    // MMIO bus selected between the CPU and verification requester.
    logic        bus_mmio_valid;
    logic        bus_mmio_ready;
    logic        bus_mmio_write;
    logic [31:0] bus_mmio_addr;
    logic [31:0] bus_mmio_wdata;
    logic [31:0] bus_mmio_rdata;
    logic [3:0]  bus_mmio_wstrb;
    logic        bus_mmio_error;

    // CPU instruction AXI read address channel.
    logic [3:0]  cpu_i_arid;
    logic [31:0] cpu_i_araddr;
    logic [7:0]  cpu_i_arlen;
    logic [2:0]  cpu_i_arsize;
    logic [1:0]  cpu_i_arburst;
    logic        cpu_i_arvalid;
    logic        cpu_i_arready;

    // CPU instruction AXI read data channel.
    logic [3:0]  cpu_i_rid;
    logic [31:0] cpu_i_rdata;
    logic [1:0]  cpu_i_rresp;
    logic        cpu_i_rlast;
    logic        cpu_i_rvalid;
    logic        cpu_i_rready;

    // CPU data AXI write address channel.
    logic [3:0]  cpu_d_awid;
    logic [31:0] cpu_d_awaddr;
    logic [7:0]  cpu_d_awlen;
    logic [2:0]  cpu_d_awsize;
    logic [1:0]  cpu_d_awburst;
    logic        cpu_d_awvalid;
    logic        cpu_d_awready;

    // CPU data AXI write data channel.
    logic [31:0] cpu_d_wdata;
    logic [3:0]  cpu_d_wstrb;
    logic        cpu_d_wlast;
    logic        cpu_d_wvalid;
    logic        cpu_d_wready;

    // CPU data AXI write response channel.
    logic [3:0] cpu_d_bid;
    logic [1:0] cpu_d_bresp;
    logic       cpu_d_bvalid;
    logic       cpu_d_bready;

    // CPU data AXI read address channel.
    logic [3:0]  cpu_d_arid;
    logic [31:0] cpu_d_araddr;
    logic [7:0]  cpu_d_arlen;
    logic [2:0]  cpu_d_arsize;
    logic [1:0]  cpu_d_arburst;
    logic        cpu_d_arvalid;
    logic        cpu_d_arready;

    // CPU data AXI read data channel.
    logic [3:0]  cpu_d_rid;
    logic [31:0] cpu_d_rdata;
    logic [1:0]  cpu_d_rresp;
    logic        cpu_d_rlast;
    logic        cpu_d_rvalid;
    logic        cpu_d_rready;

    // Local interrupt-controller MMIO endpoint.
    logic        interrupt_mmio_valid;
    logic        interrupt_mmio_ready;
    logic        interrupt_mmio_write;
    logic [31:0] interrupt_mmio_addr;
    logic [31:0] interrupt_mmio_wdata;
    logic [3:0]  interrupt_mmio_wstrb;
    logic [31:0] interrupt_mmio_rdata;

    // Machine-timer MMIO endpoint and local interrupt state.
    logic        timer_mmio_valid;
    logic        timer_mmio_ready;
    logic        timer_mmio_write;
    logic [31:0] timer_mmio_addr;
    logic [31:0] timer_mmio_wdata;
    logic [3:0]  timer_mmio_wstrb;
    logic [31:0] timer_mmio_rdata;
    logic [7:0]  local_irq_sources;
    logic        local_external_irq;
    logic        machine_timer_irq;
    logic [3:0]  local_active_irq;
    logic [63:0] machine_time;
    logic        ethernet_frame_buffer_held;

    // initial begin
    //     if (CPU_HZ == 0 || RT_FRAME_HZ == 0)
    //         $error("CPU_HZ and RT_FRAME_HZ must be non-zero");
    //     else if (CPU_HZ % RT_FRAME_HZ != 0)
    //         $error("CPU_HZ must be an integer multiple of RT_FRAME_HZ");
    //     if (MOTOR_COUNT < 2)
    //         $error("MOTOR_COUNT must be at least two");
    //     if (POSE_COUNT < 3)
    //         $error("POSE_COUNT must include Neutral, A and B");
    // end

    assign eth_tx_valid = 1'b0;
    assign eth_tx_data  = 32'd0;
    assign eth_tx_keep  = 4'd0;
    assign eth_tx_last  = 1'b0;

    assign rs485_tx = protocol_rs485_tx;
    assign rs485_de = protocol_rs485_de && !rs485_de_inhibit;

    assign bus_mmio_valid = ENABLE_CPU ? cpu_mmio_valid : mmio_valid;
    assign bus_mmio_write = ENABLE_CPU ? cpu_mmio_write : mmio_write;
    assign bus_mmio_addr  = ENABLE_CPU ? cpu_mmio_addr  : mmio_addr;
    assign bus_mmio_wdata = ENABLE_CPU ? cpu_mmio_wdata : mmio_wdata;
    assign bus_mmio_wstrb = ENABLE_CPU ? cpu_mmio_wstrb : mmio_wstrb;
    assign cpu_mmio_ready = ENABLE_CPU && bus_mmio_ready;
    assign cpu_mmio_rdata = bus_mmio_rdata;
    assign mmio_ready = !ENABLE_CPU && bus_mmio_ready;
    assign mmio_rdata = bus_mmio_rdata;
    assign mmio_error = !ENABLE_CPU && bus_mmio_error;

    assign local_irq_sources = {
        frame_error,
        pose_protocol_error,
        safety_fault_latched,
        watchdog_fault,
        host_uart_irq,
        protocol_irq,
        cnn_irq,
        ethernet_frame_irq
    };

    local_interrupt_controller #(
         .NUM_SOURCES  (8)
        ,.RESET_ENABLE (8'hff)
        ,.RESET_EDGE   (8'h81)
    ) u_local_interrupt_controller (
         .clk                (clk)
        ,.rst                (rst)
        ,.irq_sources        (local_irq_sources)
        ,.mmio_valid         (interrupt_mmio_valid)
        ,.mmio_ready         (interrupt_mmio_ready)
        ,.mmio_write         (interrupt_mmio_write)
        ,.mmio_addr          (interrupt_mmio_addr)
        ,.mmio_wdata         (interrupt_mmio_wdata)
        ,.mmio_wstrb         (interrupt_mmio_wstrb)
        ,.mmio_rdata         (interrupt_mmio_rdata)
        ,.external_interrupt (local_external_irq)
        ,.active_source      (local_active_irq)
    );

    machine_timer #(.BASE_ADDRESS(`ASL_SOC_TIMER_MMIO_BASE)) u_machine_timer (
         .clk             (clk)
        ,.rst             (rst)
        ,.mmio_valid      (timer_mmio_valid)
        ,.mmio_ready      (timer_mmio_ready)
        ,.mmio_write      (timer_mmio_write)
        ,.mmio_addr       (timer_mmio_addr)
        ,.mmio_wdata      (timer_mmio_wdata)
        ,.mmio_wstrb      (timer_mmio_wstrb)
        ,.mmio_rdata      (timer_mmio_rdata)
        ,.timer_interrupt (machine_timer_irq)
        ,.mtime_value     (machine_time)
    );

    always_comb begin
        fabric_awid = '0;
        fabric_awaddr = '0;
        fabric_awlen = '0;
        fabric_awsize = '0;
        fabric_awburst = '0;
        fabric_awvalid = '0;
        fabric_wdata = '0;
        fabric_wstrb = '0;
        fabric_wlast = '0;
        fabric_wvalid = '0;
        fabric_bready = '0;
        fabric_arid = '0;
        fabric_araddr = '0;
        fabric_arlen = '0;
        fabric_arsize = '0;
        fabric_arburst = '0;
        fabric_arvalid = '0;
        fabric_rready = '0;

        fabric_awid[2] = eth_axi_awid;
        fabric_awaddr[2] = eth_axi_awaddr;
        fabric_awlen[2] = eth_axi_awlen;
        fabric_awsize[2] = eth_axi_awsize;
        fabric_awburst[2] = eth_axi_awburst;
        fabric_awvalid[2] = eth_axi_awvalid;
        fabric_wdata[2] = eth_axi_wdata;
        fabric_wstrb[2] = eth_axi_wstrb;
        fabric_wlast[2] = eth_axi_wlast;
        fabric_wvalid[2] = eth_axi_wvalid;
        fabric_bready[2] = eth_axi_bready;

        fabric_arid[0] = cpu_i_arid;
        fabric_araddr[0] = cpu_i_araddr;
        fabric_arlen[0] = cpu_i_arlen;
        fabric_arsize[0] = cpu_i_arsize;
        fabric_arburst[0] = cpu_i_arburst;
        fabric_arvalid[0] = cpu_i_arvalid;
        fabric_rready[0] = cpu_i_rready;

        fabric_awid[1] = cpu_d_awid;
        fabric_awaddr[1] = cpu_d_awaddr;
        fabric_awlen[1] = cpu_d_awlen;
        fabric_awsize[1] = cpu_d_awsize;
        fabric_awburst[1] = cpu_d_awburst;
        fabric_awvalid[1] = cpu_d_awvalid;
        fabric_wdata[1] = cpu_d_wdata;
        fabric_wstrb[1] = cpu_d_wstrb;
        fabric_wlast[1] = cpu_d_wlast;
        fabric_wvalid[1] = cpu_d_wvalid;
        fabric_bready[1] = cpu_d_bready;
        fabric_arid[1] = cpu_d_arid;
        fabric_araddr[1] = cpu_d_araddr;
        fabric_arlen[1] = cpu_d_arlen;
        fabric_arsize[1] = cpu_d_arsize;
        fabric_arburst[1] = cpu_d_arburst;
        fabric_arvalid[1] = cpu_d_arvalid;
        fabric_rready[1] = cpu_d_rready;

        fabric_arid[2] = cnn_axi_arid;
        fabric_araddr[2] = cnn_axi_araddr;
        fabric_arlen[2] = cnn_axi_arlen;
        fabric_arsize[2] = cnn_axi_arsize;
        fabric_arburst[2] = cnn_axi_arburst;
        fabric_arvalid[2] = cnn_axi_arvalid;
        fabric_rready[2] = cnn_axi_rready;
    end

    assign eth_axi_awready = fabric_awready[2];
    assign eth_axi_wready = fabric_wready[2];
    assign eth_axi_bid = fabric_bid[2];
    assign eth_axi_bresp = fabric_bresp[2];
    assign eth_axi_bvalid = fabric_bvalid[2];
    assign cpu_i_arready = fabric_arready[0];
    assign cpu_i_rid = fabric_rid[0];
    assign cpu_i_rdata = fabric_rdata[0];
    assign cpu_i_rresp = fabric_rresp[0];
    assign cpu_i_rlast = fabric_rlast[0];
    assign cpu_i_rvalid = fabric_rvalid[0];
    assign cpu_d_awready = fabric_awready[1];
    assign cpu_d_wready = fabric_wready[1];
    assign cpu_d_bid = fabric_bid[1];
    assign cpu_d_bresp = fabric_bresp[1];
    assign cpu_d_bvalid = fabric_bvalid[1];
    assign cpu_d_arready = fabric_arready[1];
    assign cpu_d_rid = fabric_rid[1];
    assign cpu_d_rdata = fabric_rdata[1];
    assign cpu_d_rresp = fabric_rresp[1];
    assign cpu_d_rlast = fabric_rlast[1];
    assign cpu_d_rvalid = fabric_rvalid[1];
    assign cnn_axi_arready = fabric_arready[2];
    assign cnn_axi_rid = fabric_rid[2];
    assign cnn_axi_rdata = fabric_rdata[2];
    assign cnn_axi_rresp = fabric_rresp[2];
    assign cnn_axi_rlast = fabric_rlast[2];
    assign cnn_axi_rvalid = fabric_rvalid[2];

    soc_cpu_cluster #(
         .BOOT_ROM_INIT_FILE (BOOT_ROM_INIT_FILE)
        ,.ITCM_INIT_FILE     (ITCM_INIT_FILE)
        ,.DTCM_INIT_FILE     (DTCM_INIT_FILE)
        ,.ENABLE_FPU         (ENABLE_CPU_FPU)
    ) u_soc_cpu_cluster (
         .clk           (clk)
        ,.rst           (rst || !ENABLE_CPU)
        ,.dma_irq       (local_external_irq)
        ,.protocol_irq  (1'b0)
        ,.watchdog_irq  (1'b0)
        ,.platform_irqs (4'd0)
        ,.timer_irq     (machine_timer_irq)
        ,.mtime_value   (machine_time)
        ,.mmio_valid    (cpu_mmio_valid)
        ,.mmio_ready    (cpu_mmio_ready)
        ,.mmio_write    (cpu_mmio_write)
        ,.mmio_addr     (cpu_mmio_addr)
        ,.mmio_wdata    (cpu_mmio_wdata)
        ,.mmio_wstrb    (cpu_mmio_wstrb)
        ,.mmio_rdata    (cpu_mmio_rdata)
        ,.i_axi_arid    (cpu_i_arid)
        ,.i_axi_araddr  (cpu_i_araddr)
        ,.i_axi_arlen   (cpu_i_arlen)
        ,.i_axi_arsize  (cpu_i_arsize)
        ,.i_axi_arburst (cpu_i_arburst)
        ,.i_axi_arvalid (cpu_i_arvalid)
        ,.i_axi_arready (cpu_i_arready)
        ,.i_axi_rid     (cpu_i_rid)
        ,.i_axi_rdata   (cpu_i_rdata)
        ,.i_axi_rresp   (cpu_i_rresp)
        ,.i_axi_rlast   (cpu_i_rlast)
        ,.i_axi_rvalid  (cpu_i_rvalid)
        ,.i_axi_rready  (cpu_i_rready)
        ,.d_axi_awid    (cpu_d_awid)
        ,.d_axi_awaddr  (cpu_d_awaddr)
        ,.d_axi_awlen   (cpu_d_awlen)
        ,.d_axi_awsize  (cpu_d_awsize)
        ,.d_axi_awburst (cpu_d_awburst)
        ,.d_axi_awvalid (cpu_d_awvalid)
        ,.d_axi_awready (cpu_d_awready)
        ,.d_axi_wdata   (cpu_d_wdata)
        ,.d_axi_wstrb   (cpu_d_wstrb)
        ,.d_axi_wlast   (cpu_d_wlast)
        ,.d_axi_wvalid  (cpu_d_wvalid)
        ,.d_axi_wready  (cpu_d_wready)
        ,.d_axi_bid     (cpu_d_bid)
        ,.d_axi_bresp   (cpu_d_bresp)
        ,.d_axi_bvalid  (cpu_d_bvalid)
        ,.d_axi_bready  (cpu_d_bready)
        ,.d_axi_arid    (cpu_d_arid)
        ,.d_axi_araddr  (cpu_d_araddr)
        ,.d_axi_arlen   (cpu_d_arlen)
        ,.d_axi_arsize  (cpu_d_arsize)
        ,.d_axi_arburst (cpu_d_arburst)
        ,.d_axi_arvalid (cpu_d_arvalid)
        ,.d_axi_arready (cpu_d_arready)
        ,.d_axi_rid     (cpu_d_rid)
        ,.d_axi_rdata   (cpu_d_rdata)
        ,.d_axi_rresp   (cpu_d_rresp)
        ,.d_axi_rlast   (cpu_d_rlast)
        ,.d_axi_rvalid  (cpu_d_rvalid)
        ,.d_axi_rready  (cpu_d_rready)
    );

    axi4_4x1_arbiter u_external_axi_arbiter (
         .clk               (clk)
        ,.rst               (rst)
        ,.s_axi_awid        (fabric_awid)
        ,.s_axi_awaddr      (fabric_awaddr)
        ,.s_axi_awlen       (fabric_awlen)
        ,.s_axi_awsize      (fabric_awsize)
        ,.s_axi_awburst     (fabric_awburst)
        ,.s_axi_awvalid     (fabric_awvalid)
        ,.s_axi_awready     (fabric_awready)
        ,.s_axi_wdata       (fabric_wdata)
        ,.s_axi_wstrb       (fabric_wstrb)
        ,.s_axi_wlast       (fabric_wlast)
        ,.s_axi_wvalid      (fabric_wvalid)
        ,.s_axi_wready      (fabric_wready)
        ,.s_axi_bid         (fabric_bid)
        ,.s_axi_bresp       (fabric_bresp)
        ,.s_axi_bvalid      (fabric_bvalid)
        ,.s_axi_bready      (fabric_bready)
        ,.s_axi_arid        (fabric_arid)
        ,.s_axi_araddr      (fabric_araddr)
        ,.s_axi_arlen       (fabric_arlen)
        ,.s_axi_arsize      (fabric_arsize)
        ,.s_axi_arburst     (fabric_arburst)
        ,.s_axi_arvalid     (fabric_arvalid)
        ,.s_axi_arready     (fabric_arready)
        ,.s_axi_rid         (fabric_rid)
        ,.s_axi_rdata       (fabric_rdata)
        ,.s_axi_rresp       (fabric_rresp)
        ,.s_axi_rlast       (fabric_rlast)
        ,.s_axi_rvalid      (fabric_rvalid)
        ,.s_axi_rready      (fabric_rready)
        ,.m_axi_awid        (m_axi_awid)
        ,.m_axi_awaddr      (m_axi_awaddr)
        ,.m_axi_awlen       (m_axi_awlen)
        ,.m_axi_awsize      (m_axi_awsize)
        ,.m_axi_awburst     (m_axi_awburst)
        ,.m_axi_awvalid     (m_axi_awvalid)
        ,.m_axi_awready     (m_axi_awready)
        ,.m_axi_wdata       (m_axi_wdata)
        ,.m_axi_wstrb       (m_axi_wstrb)
        ,.m_axi_wlast       (m_axi_wlast)
        ,.m_axi_wvalid      (m_axi_wvalid)
        ,.m_axi_wready      (m_axi_wready)
        ,.m_axi_bid         (m_axi_bid)
        ,.m_axi_bresp       (m_axi_bresp)
        ,.m_axi_bvalid      (m_axi_bvalid)
        ,.m_axi_bready      (m_axi_bready)
        ,.m_axi_arid        (m_axi_arid)
        ,.m_axi_araddr      (m_axi_araddr)
        ,.m_axi_arlen       (m_axi_arlen)
        ,.m_axi_arsize      (m_axi_arsize)
        ,.m_axi_arburst     (m_axi_arburst)
        ,.m_axi_arvalid     (m_axi_arvalid)
        ,.m_axi_arready     (m_axi_arready)
        ,.m_axi_rid         (m_axi_rid)
        ,.m_axi_rdata       (m_axi_rdata)
        ,.m_axi_rresp       (m_axi_rresp)
        ,.m_axi_rlast       (m_axi_rlast)
        ,.m_axi_rvalid      (m_axi_rvalid)
        ,.m_axi_rready      (m_axi_rready)
        ,.write_owner_debug (fabric_write_owner)
        ,.read_owner_debug  (fabric_read_owner)
    );

    soc_mmio_subsystem #(
         .DEFAULT_POSE_MAX_STEP (POSE_MAX_STEP)
    ) u_soc_mmio_subsystem (
         .clk                        (clk)
        ,.rst                        (rst)
        ,.mmio_valid                 (bus_mmio_valid)
        ,.mmio_ready                 (bus_mmio_ready)
        ,.mmio_write                 (bus_mmio_write)
        ,.mmio_addr                  (bus_mmio_addr)
        ,.mmio_wdata                 (bus_mmio_wdata)
        ,.mmio_wstrb                 (bus_mmio_wstrb)
        ,.mmio_rdata                 (bus_mmio_rdata)
        ,.mmio_error                 (bus_mmio_error)
        ,.protocol_valid             (protocol_mmio_valid)
        ,.protocol_ready             (protocol_mmio_ready)
        ,.protocol_write             (protocol_mmio_write)
        ,.protocol_addr              (protocol_mmio_addr)
        ,.protocol_wdata             (protocol_mmio_wdata)
        ,.protocol_wstrb             (protocol_mmio_wstrb)
        ,.protocol_rdata             (protocol_mmio_rdata)
        ,.interrupt_valid            (interrupt_mmio_valid)
        ,.interrupt_ready            (interrupt_mmio_ready)
        ,.interrupt_write            (interrupt_mmio_write)
        ,.interrupt_addr             (interrupt_mmio_addr)
        ,.interrupt_wdata            (interrupt_mmio_wdata)
        ,.interrupt_wstrb            (interrupt_mmio_wstrb)
        ,.interrupt_rdata            (interrupt_mmio_rdata)
        ,.timer_valid                (timer_mmio_valid)
        ,.timer_ready                (timer_mmio_ready)
        ,.timer_write                (timer_mmio_write)
        ,.timer_addr                 (timer_mmio_addr)
        ,.timer_wdata                (timer_mmio_wdata)
        ,.timer_wstrb                (timer_mmio_wstrb)
        ,.timer_rdata                (timer_mmio_rdata)
        ,.uart_valid                 (uart_mmio_valid)
        ,.uart_ready                 (uart_mmio_ready)
        ,.uart_write                 (uart_mmio_write)
        ,.uart_addr                  (uart_mmio_addr)
        ,.uart_wdata                 (uart_mmio_wdata)
        ,.uart_wstrb                 (uart_mmio_wstrb)
        ,.uart_rdata                 (uart_mmio_rdata)
        ,.cnn_manual_start           (mmio_cnn_manual_start)
        ,.cnn_auto_start_enable      (mmio_cnn_auto_start_enable)
        ,.cnn_clear_irq              (mmio_cnn_clear_irq)
        ,.cnn_input_address          (mmio_cnn_input_address)
        ,.cnn_input_bytes            (mmio_cnn_input_bytes)
        ,.cnn_force_class_valid      (mmio_cnn_force_class_valid)
        ,.cnn_force_class_id         (mmio_cnn_force_class_id)
        ,.cnn_force_confidence       (mmio_cnn_force_confidence)
        ,.cnn_busy                   (cnn_busy)
        ,.cnn_done                   (cnn_done)
        ,.cnn_error                  (cnn_error)
        ,.cnn_irq                    (cnn_irq)
        ,.cnn_class_id               (cnn_class_id)
        ,.cnn_confidence             (cnn_confidence)
        ,.cnn_result_sequence        (cnn_result_sequence)
        ,.cnn_dma_checksum           (cnn_dma_checksum)
        ,.cnn_dma_bytes_read         (cnn_dma_bytes_read)
        ,.ethernet_frame_done        (frame_done)
        ,.ethernet_frame_error       (frame_error)
        ,.ethernet_frame_bytes       (ethernet_frame_bytes)
        ,.ethernet_frame_checksum    (ethernet_frame_checksum)
        ,.ethernet_frame_sequence    (frame_sequence)
        ,.ethernet_frame_buffer_held (ethernet_frame_buffer_held)
        ,.pose_manual_target_valid   (mmio_pose_target_valid)
        ,.pose_manual_class_id       (mmio_pose_class_id)
        ,.pose_max_step              (mmio_pose_max_step)
        ,.pose_hand_id               (mmio_pose_hand_id)
        ,.pose_frame_busy            (pose_frame_busy)
        ,.pose_active_class_id       (pose_active_class_id)
        ,.pose_command_sequence      (protocol_command_sequence)
        ,.pose_protocol_present      (!CPU_OWNS_PROTOCOL_COMMANDS)
        ,.pose_protocol_busy         (pose_protocol_busy)
        ,.pose_protocol_error        (pose_protocol_error)
        ,.pose_protocol_bank         (pose_protocol_bank)
        ,.pose_protocol_sequence     (pose_protocol_sequence)
        ,.software_torque_request    (software_torque_request)
        ,.software_watchdog_enable   (software_watchdog_enable)
        ,.software_watchdog_kick     (software_watchdog_kick)
        ,.software_safety_clear      (software_safety_clear)
        ,.torque_enable_allow        (torque_enable_allow)
        ,.rs485_de_inhibit           (rs485_de_inhibit)
        ,.watchdog_fault             (watchdog_fault)
        ,.safety_fault_latched       (safety_fault_latched)
    );

    // Pose command-bank updates have priority only during their short MMIO
    // burst. A CPU request remains asserted and completes after the adapter
    // releases the Protocol port.
    assign protocol_bus_valid = pose_protocol_mmio_valid ||
                                protocol_mmio_valid;
    assign protocol_bus_write = pose_protocol_mmio_valid ?
                                pose_protocol_mmio_write :
                                protocol_mmio_write;
    assign protocol_bus_addr = pose_protocol_mmio_valid ?
                               pose_protocol_mmio_addr :
                               protocol_mmio_addr;
    assign protocol_bus_wdata = pose_protocol_mmio_valid ?
                                pose_protocol_mmio_wdata :
                                protocol_mmio_wdata;
    assign protocol_bus_wstrb = pose_protocol_mmio_valid ?
                                pose_protocol_mmio_wstrb :
                                protocol_mmio_wstrb;
    assign pose_protocol_mmio_ready = pose_protocol_mmio_valid &&
                                      protocol_bus_ready;
    assign protocol_mmio_ready = !pose_protocol_mmio_valid &&
                                 protocol_bus_ready;
    assign protocol_mmio_rdata = protocol_bus_rdata;

    protocol2_mmio_wrapper #(
         .CLOCK_HZ                (CPU_HZ)
        ,.BAUD_RATE               (`ASL_SOC_PROTOCOL_BAUD)
        ,.USE_EXTERNAL_FRAME_TICK (1'b1)
        ,.USE_HX5_RT_SEQUENCER    (USE_HX5_RT_SEQUENCER)
    ) u_protocol2_mmio_wrapper (
         .clk            (clk)
        ,.rst            (rst)
        ,.frame_tick     (rt_frame_tick_pulse)
        ,.external_abort (safety_fault_latched)
        ,.mmio_valid     (protocol_bus_valid)
        ,.mmio_ready     (protocol_bus_ready)
        ,.mmio_write     (protocol_bus_write)
        ,.mmio_addr      (protocol_bus_addr)
        ,.mmio_wdata     (protocol_bus_wdata)
        ,.mmio_wstrb     (protocol_bus_wstrb)
        ,.mmio_rdata     (protocol_bus_rdata)
        ,.irq            (protocol_irq)
        ,.rs485_tx       (protocol_rs485_tx)
        ,.rs485_rx       (rs485_rx)
        ,.rs485_de       (protocol_rs485_de)
    );

    host_uart_mmio #(
         .CLOCK_HZ  (CPU_HZ)
        ,.BAUD_RATE (HOST_UART_BAUD)
    ) u_host_uart_mmio (
         .clk        (clk)
        ,.rst        (rst)
        ,.mmio_valid (uart_mmio_valid)
        ,.mmio_ready (uart_mmio_ready)
        ,.mmio_write (uart_mmio_write)
        ,.mmio_addr  (uart_mmio_addr)
        ,.mmio_wdata (uart_mmio_wdata)
        ,.mmio_wstrb (uart_mmio_wstrb)
        ,.mmio_rdata (uart_mmio_rdata)
        ,.uart_rx    (host_uart_rx)
        ,.uart_tx    (host_uart_tx)
        ,.irq        (host_uart_irq)
    );

    safety_supervisor #(
         .WATCHDOG_TIMEOUT_CYCLES (WATCHDOG_TIMEOUT_CYCLES)
    ) u_safety_supervisor (
         .clk                  (clk)
        ,.rst                  (rst)
        ,.emergency_stop_n     (emergency_stop_n)
        ,.external_fault       (external_fault)
        ,.torque_enable_request(torque_enable_request &&
                               software_torque_request)
        ,.watchdog_enable      (watchdog_enable ||
                               software_watchdog_enable)
        ,.watchdog_kick        (watchdog_kick || software_watchdog_kick)
        ,.clear_fault          (safety_clear_fault || software_safety_clear)
        ,.torque_enable_allow  (torque_enable_allow)
        ,.rs485_de_inhibit     (rs485_de_inhibit)
        ,.watchdog_fault       (watchdog_fault)
        ,.safety_fault_latched (safety_fault_latched)
    );

    axi_multichannel_burst_dma #(
         .FRAME_BUFFER_BASE (`ASL_SOC_ETH_FRAME_BUFFER_BASE)
        ,.MAX_FRAME_BYTES   (ETH_MAX_FRAME_BYTES)
        ,.MAX_INPUT_BYTES   (CNN_MAX_INPUT_BYTES)
        ,.MAX_BURST_BEATS   (DMA_MAX_BURST_BEATS)
    ) u_axi_multichannel_burst_dma (
         .clk                    (clk)
        ,.rst                    (rst)
        ,.s2mm_valid             (eth_rx_valid)
        ,.s2mm_data              (eth_rx_data)
        ,.s2mm_keep              (eth_rx_keep)
        ,.s2mm_last              (eth_rx_last)
        ,.s2mm_ready             (eth_rx_ready)
        ,.s2mm_frame_done        (frame_done)
        ,.s2mm_frame_error       (frame_error)
        ,.s2mm_frame_bytes       (ethernet_frame_bytes)
        ,.s2mm_frame_checksum    (ethernet_frame_checksum)
        ,.s2mm_frame_sequence    (frame_sequence)
        ,.s2mm_hold_after_frame  (mmio_cnn_auto_start_enable)
        ,.s2mm_frame_release     (cnn_done || cnn_error)
        ,.s2mm_frame_buffer_held (ethernet_frame_buffer_held)
        ,.mm2s_start             (cnn_dma_start)
        ,.mm2s_address           (cnn_dma_input_address)
        ,.mm2s_bytes             (cnn_dma_input_bytes)
        ,.mm2s_busy              (cnn_dma_busy)
        ,.mm2s_done              (cnn_dma_done)
        ,.mm2s_error             (cnn_dma_error)
        ,.mm2s_checksum          (cnn_dma_checksum)
        ,.mm2s_bytes_read        (cnn_dma_bytes_read)
        ,.mm2s_valid             (cnn_dma_stream_valid)
        ,.mm2s_ready             (1'b1)
        ,.mm2s_data              (cnn_dma_stream_data)
        ,.mm2s_keep              (cnn_dma_stream_keep)
        ,.mm2s_last              (cnn_dma_stream_last)
        ,.m_axi_awid             (eth_axi_awid)
        ,.m_axi_awaddr           (eth_axi_awaddr)
        ,.m_axi_awlen            (eth_axi_awlen)
        ,.m_axi_awsize           (eth_axi_awsize)
        ,.m_axi_awburst          (eth_axi_awburst)
        ,.m_axi_awvalid          (eth_axi_awvalid)
        ,.m_axi_awready          (eth_axi_awready)
        ,.m_axi_wdata            (eth_axi_wdata)
        ,.m_axi_wstrb            (eth_axi_wstrb)
        ,.m_axi_wlast            (eth_axi_wlast)
        ,.m_axi_wvalid           (eth_axi_wvalid)
        ,.m_axi_wready           (eth_axi_wready)
        ,.m_axi_bid              (eth_axi_bid)
        ,.m_axi_bresp            (eth_axi_bresp)
        ,.m_axi_bvalid           (eth_axi_bvalid)
        ,.m_axi_bready           (eth_axi_bready)
        ,.m_axi_arid             (cnn_axi_arid)
        ,.m_axi_araddr           (cnn_axi_araddr)
        ,.m_axi_arlen            (cnn_axi_arlen)
        ,.m_axi_arsize           (cnn_axi_arsize)
        ,.m_axi_arburst          (cnn_axi_arburst)
        ,.m_axi_arvalid          (cnn_axi_arvalid)
        ,.m_axi_arready          (cnn_axi_arready)
        ,.m_axi_rid              (cnn_axi_rid)
        ,.m_axi_rdata            (cnn_axi_rdata)
        ,.m_axi_rresp            (cnn_axi_rresp)
        ,.m_axi_rlast            (cnn_axi_rlast)
        ,.m_axi_rvalid           (cnn_axi_rvalid)
        ,.m_axi_rready           (cnn_axi_rready)
    );

    assign ethernet_frame_irq = frame_done;

    assign cnn_start_selected = mmio_cnn_manual_start ||
        (frame_done && !frame_error && mmio_cnn_auto_start_enable);
    assign cnn_input_address_selected = mmio_cnn_manual_start ?
        mmio_cnn_input_address : `ASL_SOC_ETH_FRAME_BUFFER_BASE;
    assign cnn_input_bytes_selected = mmio_cnn_manual_start ?
        mmio_cnn_input_bytes : ethernet_frame_bytes;

    cnn_accelerator_stub #(
         .POSE_COUNT     (POSE_COUNT)
        ,.LATENCY_CYCLES (CNN_STUB_LATENCY_CYCLES)
    ) u_cnn_accelerator_stub (
         .clk               (clk)
        ,.rst               (rst)
        ,.start             (cnn_start_selected)
        ,.input_address     (cnn_input_address_selected)
        ,.input_bytes       (cnn_input_bytes_selected)
        ,.test_class_valid   (cnn_test_class_valid ||
                             mmio_cnn_force_class_valid)
        ,.test_class_id      (cnn_test_class_valid ? cnn_test_class_id :
                             mmio_cnn_force_class_id)
        ,.test_confidence    (cnn_test_class_valid ? cnn_test_confidence :
                             mmio_cnn_force_confidence)
        ,.clear_irq         (cnn_clear_irq || mmio_cnn_clear_irq)
        ,.busy              (cnn_busy)
        ,.done              (cnn_done)
        ,.error             (cnn_error)
        ,.class_id          (cnn_class_id)
        ,.confidence        (cnn_confidence)
        ,.result_sequence   (cnn_result_sequence)
        ,.irq               (cnn_irq)
        ,.dma_start         (cnn_dma_start)
        ,.dma_input_address (cnn_dma_input_address)
        ,.dma_input_bytes   (cnn_dma_input_bytes)
        ,.dma_done          (cnn_dma_done)
        ,.dma_error         (cnn_dma_error)
        ,.dma_checksum      (cnn_dma_checksum)
    );

    rt_frame_tick #(
         .FRAME_CYCLES (RT_FRAME_CYCLES)
    ) u_rt_frame_tick (
         .clk  (clk)
        ,.rst  (rst)
        ,.tick (rt_frame_tick_pulse)
    );

    assign pose_target_valid_selected = mmio_pose_target_valid || cnn_done;
    assign pose_target_class_selected = mmio_pose_target_valid ?
        mmio_pose_class_id : cnn_class_id;

    generate
        if (CPU_OWNS_PROTOCOL_COMMANDS) begin : g_cpu_protocol_commands
            // The RTOS writes Command A/B through Protocol MMIO. Keep the
            // Pose stream observable at the top-level, but do not synthesize
            // a second MMIO producer that could race the CPU.
            assign pose_adapter_ready = protocol_command_ready;
            assign pose_protocol_mmio_valid = 1'b0;
            assign pose_protocol_mmio_write = 1'b0;
            assign pose_protocol_mmio_addr = 32'd0;
            assign pose_protocol_mmio_wdata = 32'd0;
            assign pose_protocol_mmio_wstrb = 4'd0;
            assign pose_protocol_busy = 1'b0;
            assign pose_protocol_error = 1'b0;
            assign pose_protocol_bank = 1'b0;
            assign pose_protocol_sequence = 32'd0;
        end else begin : g_hardware_protocol_commands
            pose_protocol_command_adapter #(
                 .MOTOR_COUNT   (MOTOR_COUNT)
                ,.PROTOCOL_BASE (`ASL_SOC_PROTOCOL2_MMIO_BASE)
            ) u_pose_protocol_command_adapter (
                 .clk                       (clk)
                ,.rst                       (rst)
                ,.pose_valid                (protocol_command_valid)
                ,.pose_ready                (pose_adapter_ready)
                ,.pose_motor_index          (protocol_motor_index)
                ,.pose_goal_current         (protocol_goal_current)
                ,.pose_goal_velocity        (protocol_goal_velocity)
                ,.pose_profile_acceleration (protocol_profile_acceleration)
                ,.pose_profile_velocity     (protocol_profile_velocity)
                ,.pose_position             (protocol_command_position)
                ,.pose_last                 (protocol_command_last)
                ,.pose_commit               (protocol_command_commit)
                ,.pose_sequence             (protocol_command_sequence)
                ,.hand_id                   (mmio_pose_hand_id)
                ,.mmio_valid                (pose_protocol_mmio_valid)
                ,.mmio_ready                (pose_protocol_mmio_ready)
                ,.mmio_write                (pose_protocol_mmio_write)
                ,.mmio_addr                 (pose_protocol_mmio_addr)
                ,.mmio_wdata                (pose_protocol_mmio_wdata)
                ,.mmio_wstrb                (pose_protocol_mmio_wstrb)
                ,.mmio_rdata                (protocol_bus_rdata)
                ,.busy                      (pose_protocol_busy)
                ,.error                     (pose_protocol_error)
                ,.committed_bank            (pose_protocol_bank)
                ,.committed_sequence        (pose_protocol_sequence)
            );
        end
    endgenerate

    pose_player #(
         .MOTOR_COUNT                  (MOTOR_COUNT)
        ,.POSE_COUNT                   (POSE_COUNT)
        ,.NEUTRAL_POSITION             (NEUTRAL_POSITION)
        ,.DEFAULT_MAX_STEP             (POSE_MAX_STEP)
        ,.DEFAULT_GOAL_CURRENT         (POSE_GOAL_CURRENT)
        ,.DEFAULT_GOAL_VELOCITY        (POSE_GOAL_VELOCITY)
        ,.DEFAULT_PROFILE_ACCELERATION (POSE_PROFILE_ACCELERATION)
        ,.DEFAULT_PROFILE_VELOCITY     (POSE_PROFILE_VELOCITY)
    ) u_pose_player (
         .clk                          (clk)
        ,.rst                          (rst)
        ,.frame_tick                   (rt_frame_tick_pulse)
        ,.safety_allow                 (torque_enable_allow)
        ,.target_valid                 (pose_target_valid_selected)
        ,.target_class_id              (pose_target_class_selected)
        ,.max_step                     (mmio_pose_max_step)
        ,.command_valid                (protocol_command_valid)
        ,.command_ready                (pose_adapter_ready)
        ,.command_motor_index          (protocol_motor_index)
        ,.command_goal_current         (protocol_goal_current)
        ,.command_goal_velocity        (protocol_goal_velocity)
        ,.command_profile_acceleration (protocol_profile_acceleration)
        ,.command_profile_velocity     (protocol_profile_velocity)
        ,.command_position             (protocol_command_position)
        ,.command_last                 (protocol_command_last)
        ,.command_commit               (protocol_command_commit)
        ,.command_sequence             (protocol_command_sequence)
        ,.frame_busy                   (pose_frame_busy)
        ,.active_class_id              (pose_active_class_id)
    );

endmodule
