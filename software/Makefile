ROOT := ..
BUILD_DIR := build
HOST_TEST := $(BUILD_DIR)/asl_motion_test
PROTOCOL_SIM := $(BUILD_DIR)/asl_letter_protocol
COMMAND_VECTOR := $(BUILD_DIR)/asl_letter_command.mem
LETTER ?= A

PROTOCOL_RTL := \
	$(ROOT)/rtl/protocol/core/uart_fractional_tick.sv \
	$(ROOT)/rtl/protocol/core/uart_tx.sv \
	$(ROOT)/rtl/protocol/core/uart_rx.sv \
	$(ROOT)/rtl/protocol/core/rs485_uart_phy.sv \
	$(ROOT)/rtl/protocol/core/protocol2_pingpong_sram.sv \
	$(ROOT)/rtl/protocol/core/protocol2_tx.sv \
	$(ROOT)/rtl/protocol/core/protocol2_rx.sv \
	$(ROOT)/rtl/protocol/core/protocol2_core.sv \
	$(ROOT)/rtl/protocol/core/protocol2_hx5_rt_sequencer.sv \
	$(ROOT)/rtl/protocol/core/protocol2_rt_engine.sv \
	$(ROOT)/rtl/protocol/core/protocol2_mmio_wrapper.sv

.PHONY: test host-test protocol-test clean

test: protocol-test

$(BUILD_DIR):
	mkdir -p $@

$(HOST_TEST): src/asl_motion.c generated/asl_actions_generated.c \
		tests/asl_motion_test.c include/asl_motion.h \
		generated/asl_actions_generated.h \
		$(ROOT)/fw/include/hx5_d20_protocol.h | $(BUILD_DIR)
	cc -std=c11 -Wall -Wextra -Werror \
		-Iinclude -Igenerated -I$(ROOT)/fw/include \
		src/asl_motion.c generated/asl_actions_generated.c \
		tests/asl_motion_test.c -o $@

host-test: $(HOST_TEST) | $(BUILD_DIR)
	$(HOST_TEST) $(LETTER) $(COMMAND_VECTOR)

$(PROTOCOL_SIM): $(PROTOCOL_RTL) \
		tests/asl_letter_protocol_tb.sv
	iverilog -g2012 -Wall -Wno-timescale -I$(ROOT)/rtl/include \
		-s asl_letter_protocol_tb -o $@ $(PROTOCOL_RTL) \
		tests/asl_letter_protocol_tb.sv

protocol-test: host-test $(PROTOCOL_SIM)
	vvp $(PROTOCOL_SIM)

clean:
	rm -f $(HOST_TEST) $(PROTOCOL_SIM) $(COMMAND_VECTOR)
