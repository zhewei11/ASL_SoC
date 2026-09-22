BUILD_DIR := build
SIMV := $(BUILD_DIR)/soc_core_smoke
INFRA_SIMV := $(BUILD_DIR)/axi_infrastructure
CPU_SIMV := $(BUILD_DIR)/rv32im_boot
RV32F_UNIT_SIMV := $(BUILD_DIR)/rv32f_unit
RV32F_CORE_SIMV := $(BUILD_DIR)/rv32f_core
RV32F_TRAP_SIMV := $(BUILD_DIR)/rv32f_trap
PMP_CSR_SIMV := $(BUILD_DIR)/pmp_csr
PMP_CORE_SIMV := $(BUILD_DIR)/core_pmp_user
RV32F_RANDOM_DIR := $(BUILD_DIR)/rv32f_random
SOC_CPU_SIMV := $(BUILD_DIR)/soc_cpu_boot
FREERTOS_SIMV := $(BUILD_DIR)/soc_freertos_boot
CPU_IRQ_SIMV := $(BUILD_DIR)/soc_cpu_interrupt_timer
CACHED_DRAM_SIMV := $(BUILD_DIR)/soc_cpu_cached_dram
UART_SIMV := $(BUILD_DIR)/host_uart_mmio
STRESS_SIMV := $(BUILD_DIR)/soc_dram_stress
CNN_DMA_SIMV := $(BUILD_DIR)/cnn_input_dma
ETH_DMA_SIMV := $(BUILD_DIR)/ethernet_rx_dma
IRQ_TIMER_SIMV := $(BUILD_DIR)/interrupt_timer
PROTOCOL_MMIO_SIMV := $(BUILD_DIR)/protocol2_mmio
PROTOCOL_SCHED_SIMV := $(BUILD_DIR)/protocol2_scheduler
PROTOCOL_SAFETY_SIMV := $(BUILD_DIR)/protocol2_safety
PROTOCOL_EXT_TICK_SIMV := $(BUILD_DIR)/protocol2_external_tick
PROTOCOL_HX5_SEQ_SIMV := $(BUILD_DIR)/protocol2_hx5_sequencer
POSE_PROTOCOL_SIMV := $(BUILD_DIR)/pose_protocol_adapter
PROTOCOL_RTL := rtl/protocol/core/uart_fractional_tick.sv \
	rtl/protocol/core/uart_tx.sv rtl/protocol/core/uart_rx.sv \
	rtl/protocol/core/rs485_uart_phy.sv \
	rtl/protocol/core/protocol2_pingpong_sram.sv \
	rtl/protocol/core/protocol2_tx.sv rtl/protocol/core/protocol2_rx.sv \
	rtl/protocol/core/protocol2_core.sv \
	rtl/protocol/core/protocol2_hx5_rt_sequencer.sv \
	rtl/protocol/core/protocol2_rt_engine.sv \
	rtl/protocol/core/protocol2_mmio_wrapper.sv
SOC_RTL := $(filter-out +%,$(shell sed '/^[[:space:]]*$$/d' rtl/rtl_smoke.f))
CPU_ELF := $(BUILD_DIR)/rv32im_boot.elf
CPU_BIN := $(BUILD_DIR)/rv32im_boot.bin
CPU_MEM := $(BUILD_DIR)/rv32im_boot.mem
STRESS_ELF := $(BUILD_DIR)/dram_stress.elf
STRESS_BIN := $(BUILD_DIR)/dram_stress.bin
STRESS_MEM := $(BUILD_DIR)/dram_stress.mem
CPU_IRQ_ELF := $(BUILD_DIR)/interrupt_timer.elf
CPU_IRQ_BIN := $(BUILD_DIR)/interrupt_timer.bin
CPU_IRQ_MEM := $(BUILD_DIR)/interrupt_timer.mem
CACHED_DRAM_ELF := $(BUILD_DIR)/cached_dram.elf
CACHED_DRAM_BIN := $(BUILD_DIR)/cached_dram.bin
CACHED_DRAM_MEM := $(BUILD_DIR)/cached_dram.mem
RISCV_TOOL_DIR := ../rtos_core/freertos_demo/.tools/xpack-riscv-none-elf-gcc-13.4.0-1/bin
RISCV_GCC := $(RISCV_TOOL_DIR)/riscv-none-elf-gcc
RISCV_OBJCOPY := $(RISCV_TOOL_DIR)/riscv-none-elf-objcopy
RISCV_MARCH := rv32imf_zicsr
RISCV_ABI := ilp32f
FREERTOS_DEMO_DIR := ../rtos_core/freertos_demo
FREERTOS_ROM_MEM := $(BUILD_DIR)/freertos_rom.mem
FREERTOS_ITCM_MEM := $(BUILD_DIR)/freertos_itcm.mem
FREERTOS_DTCM_MEM := $(BUILD_DIR)/freertos_dtcm.mem

.PHONY: all config headers cpu-source-check protocol-source-check test \
	rv32f-random freertos-firmware freertos-test \
	protocol-test protocol-long protocol-real-10k protocol-sva soc-sva \
	cached-sva verify-all format format-check lint clean

all: test

format:
	python3 scripts/format_rtl_style.py

format-check:
	python3 scripts/format_rtl_style.py --check

config:
	python3 scripts/generate_config.py

headers: config
	cc -std=c11 -Wall -Wextra -Werror -Ifw/include \
		-fsyntax-only sim/software_headers_compile.c
	python3 -m unittest discover -s scripts -p 'test_*.py'

cpu-source-check:
	python3 scripts/check_local_cpu_sources.py

protocol-source-check:
	python3 scripts/check_local_protocol_sources.py

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

$(SIMV): config $(SOC_RTL) sim/models/axi_dram_model.sv \
		sim/tb/soc_core_smoke_tb.sv | $(BUILD_DIR)
	iverilog -g2012 -Wall -Wno-timescale -s soc_core_smoke_tb -o $(SIMV) \
		-f rtl/rtl_smoke.f sim/models/axi_dram_model.sv \
		sim/tb/soc_core_smoke_tb.sv

$(INFRA_SIMV): rtl/memory/axi_bram_slave.sv \
		rtl/interconnect/axi4_4x1_arbiter.sv \
		sim/tb/axi_infrastructure_tb.sv | $(BUILD_DIR)
	iverilog -g2012 -Wall -Wno-timescale -s axi_infrastructure_tb \
		-o $(INFRA_SIMV) rtl/memory/axi_bram_slave.sv \
		rtl/interconnect/axi4_4x1_arbiter.sv \
		sim/tb/axi_infrastructure_tb.sv

$(CPU_ELF): fw/boot_smoke.S fw/boot_smoke.ld | $(BUILD_DIR)
	$(RISCV_GCC) -march=$(RISCV_MARCH) -mabi=$(RISCV_ABI) -nostdlib \
		-Wl,--build-id=none -T fw/boot_smoke.ld -o $@ fw/boot_smoke.S

$(CPU_BIN): $(CPU_ELF)
	$(RISCV_OBJCOPY) -O binary $< $@

$(CPU_MEM): $(CPU_BIN) scripts/bin_to_mem.py
	python3 scripts/bin_to_mem.py --bytes 8192 $< $@

$(STRESS_ELF): fw/dram_stress.S fw/boot_smoke.ld | $(BUILD_DIR)
	$(RISCV_GCC) -march=$(RISCV_MARCH) -mabi=$(RISCV_ABI) -nostdlib \
		-Wl,--build-id=none -T fw/boot_smoke.ld -o $@ fw/dram_stress.S

$(STRESS_BIN): $(STRESS_ELF)
	$(RISCV_OBJCOPY) -O binary $< $@

$(STRESS_MEM): $(STRESS_BIN) scripts/bin_to_mem.py
	python3 scripts/bin_to_mem.py --bytes 8192 $< $@

$(CPU_IRQ_ELF): fw/interrupt_timer.S fw/boot_smoke.ld | $(BUILD_DIR)
	$(RISCV_GCC) -march=$(RISCV_MARCH) -mabi=$(RISCV_ABI) -nostdlib \
		-Wl,--build-id=none -T fw/boot_smoke.ld -o $@ fw/interrupt_timer.S

$(CPU_IRQ_BIN): $(CPU_IRQ_ELF)
	$(RISCV_OBJCOPY) -O binary $< $@

$(CPU_IRQ_MEM): $(CPU_IRQ_BIN) scripts/bin_to_mem.py
	python3 scripts/bin_to_mem.py --bytes 8192 $< $@

$(CACHED_DRAM_ELF): fw/cached_dram.S fw/boot_smoke.ld | $(BUILD_DIR)
	$(RISCV_GCC) -march=$(RISCV_MARCH) -mabi=$(RISCV_ABI) -nostdlib \
		-Wl,--build-id=none -T fw/boot_smoke.ld -o $@ fw/cached_dram.S

$(CACHED_DRAM_BIN): $(CACHED_DRAM_ELF)
	$(RISCV_OBJCOPY) -O binary $< $@

$(CACHED_DRAM_MEM): $(CACHED_DRAM_BIN) scripts/bin_to_mem.py
	python3 scripts/bin_to_mem.py --bytes 8192 $< $@

$(CPU_SIMV): $(CPU_MEM) rtl/cpu_rv32im.f sim/tb/rv32im_boot_tb.sv
	iverilog -g2012 -Wall -Wno-timescale -s rv32im_boot_tb \
		-o $(CPU_SIMV) -f rtl/cpu_rv32im.f sim/tb/rv32im_boot_tb.sv

$(RV32F_UNIT_SIMV): rtl/cpu/core/ex/rv32f_unit.sv \
		sim/tb/rv32f_unit_tb.sv | $(BUILD_DIR)
	iverilog -g2012 -Wall -Wno-timescale -s rv32f_unit_tb \
		-o $@ rtl/cpu/core/ex/rv32f_unit.sv sim/tb/rv32f_unit_tb.sv

$(RV32F_CORE_SIMV): rtl/cpu_rv32im.f sim/tb/rv32f_core_tb.sv | $(BUILD_DIR)
	iverilog -g2012 -Wall -Wno-timescale -s core_rv32f_tb \
		-o $@ -f rtl/cpu_rv32im.f sim/tb/rv32f_core_tb.sv

$(RV32F_TRAP_SIMV): rtl/cpu_rv32im.f sim/tb/rv32f_trap_tb.sv | $(BUILD_DIR)
	iverilog -g2012 -Wall -Wno-timescale -s core_rv32f_trap_tb \
		-o $@ -f rtl/cpu_rv32im.f sim/tb/rv32f_trap_tb.sv

$(PMP_CSR_SIMV): rtl/cpu/core/ex/csr_registers.v \
		sim/tb/pmp_csr_tb.sv | $(BUILD_DIR)
	iverilog -g2012 -Wall -Wno-timescale -I rtl/include -s pmp_csr_tb \
		-o $@ rtl/cpu/core/ex/csr_registers.v sim/tb/pmp_csr_tb.sv

$(PMP_CORE_SIMV): rtl/cpu_rv32im.f sim/tb/core_pmp_user_tb.sv | $(BUILD_DIR)
	iverilog -g2012 -Wall -Wno-timescale -s core_pmp_user_tb \
		-o $@ -f rtl/cpu_rv32im.f sim/tb/core_pmp_user_tb.sv

rv32f-random: | $(BUILD_DIR)
	verilator --cc --exe --build -Wno-fatal \
		--Mdir $(RV32F_RANDOM_DIR) --top-module rv32f_unit \
		rtl/cpu/core/ex/rv32f_unit.sv sim/rv32f_random_harness.cpp
	$(RV32F_RANDOM_DIR)/Vrv32f_unit

$(SOC_CPU_SIMV): $(CPU_MEM) config $(SOC_RTL) \
		sim/tb/soc_cpu_boot_tb.sv | $(BUILD_DIR)
	iverilog -g2012 -Wall -Wno-timescale -s soc_cpu_boot_tb \
		-o $(SOC_CPU_SIMV) -f rtl/rtl_smoke.f sim/tb/soc_cpu_boot_tb.sv

freertos-firmware: | $(BUILD_DIR)
	$(MAKE) -C $(FREERTOS_DEMO_DIR) firmware CPU_CLOCK_HZ=100000000 \
		CONFIG_LINKER=$(abspath fw/freertos_soc.ld)
	python3 scripts/bin_to_mem.py --bytes 8192 \
		$(FREERTOS_DEMO_DIR)/build/rom.bin $(FREERTOS_ROM_MEM)
	python3 scripts/bin_to_mem.py --bytes 65536 \
		$(FREERTOS_DEMO_DIR)/build/imem.bin $(FREERTOS_ITCM_MEM)
	python3 scripts/bin_to_mem.py --bytes 65536 \
		$(FREERTOS_DEMO_DIR)/build/dmem.bin $(FREERTOS_DTCM_MEM)

$(FREERTOS_SIMV): freertos-firmware config $(SOC_RTL) \
		sim/tb/soc_freertos_boot_tb.sv | $(BUILD_DIR)
	iverilog -g2012 -Wall -Wno-timescale -s soc_freertos_boot_tb \
		-o $(FREERTOS_SIMV) -f rtl/rtl_smoke.f \
		sim/tb/soc_freertos_boot_tb.sv

freertos-test: $(FREERTOS_SIMV)
	vvp $(FREERTOS_SIMV)

$(CPU_IRQ_SIMV): $(CPU_IRQ_MEM) config $(SOC_RTL) \
		sim/tb/soc_cpu_interrupt_timer_tb.sv | $(BUILD_DIR)
	iverilog -g2012 -Wall -Wno-timescale -s soc_cpu_interrupt_timer_tb \
		-o $(CPU_IRQ_SIMV) -f rtl/rtl_smoke.f \
		sim/tb/soc_cpu_interrupt_timer_tb.sv

$(CACHED_DRAM_SIMV): $(CACHED_DRAM_MEM) config $(SOC_RTL) \
		sim/tb/soc_cpu_cached_dram_tb.sv | $(BUILD_DIR)
	iverilog -g2012 -Wall -Wno-timescale -s soc_cpu_cached_dram_tb \
		-o $(CACHED_DRAM_SIMV) -f rtl/rtl_smoke.f \
		sim/tb/soc_cpu_cached_dram_tb.sv

$(UART_SIMV): rtl/uart/host_uart_mmio.sv sim/tb/host_uart_mmio_tb.sv | $(BUILD_DIR)
	iverilog -g2012 -Wall -Wno-timescale -s host_uart_mmio_tb \
		-o $(UART_SIMV) rtl/uart/host_uart_mmio.sv \
		sim/tb/host_uart_mmio_tb.sv

$(STRESS_SIMV): $(STRESS_MEM) config $(SOC_RTL) sim/models/axi_dram_model.sv \
		sim/tb/soc_dram_stress_tb.sv | $(BUILD_DIR)
	iverilog -g2012 -Wall -Wno-timescale -s soc_dram_stress_tb \
		-o $(STRESS_SIMV) -f rtl/rtl_smoke.f \
		sim/models/axi_dram_model.sv sim/tb/soc_dram_stress_tb.sv

$(CNN_DMA_SIMV): rtl/cnn/cnn_input_dma.sv sim/tb/cnn_input_dma_tb.sv | $(BUILD_DIR)
	iverilog -g2012 -Wall -Wno-timescale -s cnn_input_dma_tb \
		-o $(CNN_DMA_SIMV) rtl/cnn/cnn_input_dma.sv \
		sim/tb/cnn_input_dma_tb.sv

$(ETH_DMA_SIMV): rtl/ethernet/ethernet_rx_dma_shell.sv \
		sim/tb/ethernet_rx_dma_tb.sv | $(BUILD_DIR)
	iverilog -g2012 -Wall -Wno-timescale -s ethernet_rx_dma_tb \
		-o $@ rtl/ethernet/ethernet_rx_dma_shell.sv \
		sim/tb/ethernet_rx_dma_tb.sv

$(IRQ_TIMER_SIMV): rtl/interrupt/local_interrupt_controller.sv \
		rtl/timer/machine_timer.sv sim/tb/interrupt_timer_tb.sv | $(BUILD_DIR)
	iverilog -g2012 -Wall -Wno-timescale -s interrupt_timer_tb -o $@ \
		rtl/interrupt/local_interrupt_controller.sv \
		rtl/timer/machine_timer.sv sim/tb/interrupt_timer_tb.sv

$(PROTOCOL_MMIO_SIMV): $(PROTOCOL_RTL) \
		sim/protocol/protocol2_mmio_wrapper_tb.sv | $(BUILD_DIR)
	iverilog -g2012 -Wall -Wno-timescale -I rtl/include \
		-s protocol2_mmio_wrapper_tb -o $@ $(PROTOCOL_RTL) \
		sim/protocol/protocol2_mmio_wrapper_tb.sv

$(PROTOCOL_SCHED_SIMV): rtl/protocol/core/protocol2_rt_engine.sv \
		sim/protocol/protocol2_rt_scheduler_tb.sv | $(BUILD_DIR)
	iverilog -g2012 -Wall -Wno-timescale -I rtl/include \
		-s protocol2_rt_scheduler_tb -o $@ \
		rtl/protocol/core/protocol2_rt_engine.sv \
		sim/protocol/protocol2_rt_scheduler_tb.sv

$(PROTOCOL_SAFETY_SIMV): rtl/protocol/core/protocol2_rt_engine.sv \
		sim/protocol/protocol2_rt_safety_tb.sv | $(BUILD_DIR)
	iverilog -g2012 -Wall -Wno-timescale -I rtl/include \
		-s protocol2_rt_safety_tb -o $@ \
		rtl/protocol/core/protocol2_rt_engine.sv \
		sim/protocol/protocol2_rt_safety_tb.sv

$(PROTOCOL_EXT_TICK_SIMV): rtl/protocol/core/protocol2_rt_engine.sv \
		sim/protocol/protocol2_rt_external_tick_tb.sv | $(BUILD_DIR)
	iverilog -g2012 -Wall -Wno-timescale -I rtl/include \
		-s protocol2_rt_external_tick_tb -o $@ \
		rtl/protocol/core/protocol2_rt_engine.sv \
		sim/protocol/protocol2_rt_external_tick_tb.sv

$(PROTOCOL_HX5_SEQ_SIMV): \
		rtl/protocol/core/protocol2_hx5_rt_sequencer.sv \
		sim/protocol/protocol2_hx5_rt_sequencer_tb.sv | $(BUILD_DIR)
	iverilog -g2012 -Wall -Wno-timescale -I rtl/include \
		-s protocol2_hx5_rt_sequencer_tb -o $@ \
		rtl/protocol/core/protocol2_hx5_rt_sequencer.sv \
		sim/protocol/protocol2_hx5_rt_sequencer_tb.sv

$(POSE_PROTOCOL_SIMV): rtl/pose/pose_protocol_command_adapter.sv \
		sim/protocol/pose_protocol_command_adapter_tb.sv | $(BUILD_DIR)
	iverilog -g2012 -Wall -Wno-timescale \
		-s pose_protocol_command_adapter_tb -o $@ \
		rtl/pose/pose_protocol_command_adapter.sv \
		sim/protocol/pose_protocol_command_adapter_tb.sv

protocol-test: $(PROTOCOL_MMIO_SIMV) $(PROTOCOL_SCHED_SIMV) \
		$(PROTOCOL_SAFETY_SIMV) $(PROTOCOL_EXT_TICK_SIMV) \
		$(PROTOCOL_HX5_SEQ_SIMV) $(POSE_PROTOCOL_SIMV)
	vvp $(PROTOCOL_MMIO_SIMV)
	vvp $(PROTOCOL_SCHED_SIMV)
	vvp $(PROTOCOL_SAFETY_SIMV)
	vvp $(PROTOCOL_EXT_TICK_SIMV)
	vvp $(PROTOCOL_HX5_SEQ_SIMV)
	vvp $(POSE_PROTOCOL_SIMV)

protocol-long: | $(BUILD_DIR)
	verilator --binary --timing --assert -Wno-fatal -Irtl/include \
		--top-module protocol2_rt_scheduler_tb -GFAST_FRAME_COUNT=1000000 \
		--Mdir $(BUILD_DIR)/protocol2_long -o protocol2_long \
		rtl/protocol/core/protocol2_rt_engine.sv \
		sim/protocol/protocol2_rt_scheduler_tb.sv
	$(BUILD_DIR)/protocol2_long/protocol2_long

protocol-real-10k: | $(BUILD_DIR)
	verilator --binary --timing --assert -Wno-fatal -Irtl/include \
		--top-module protocol2_rt_scheduler_tb \
		-GREAL_FRAME_COUNT=10000 -GFAST_FRAME_COUNT=0 \
		--Mdir $(BUILD_DIR)/protocol2_real_10k -o protocol2_real_10k \
		rtl/protocol/core/protocol2_rt_engine.sv \
		sim/protocol/protocol2_rt_scheduler_tb.sv
	$(BUILD_DIR)/protocol2_real_10k/protocol2_real_10k

protocol-sva: | $(BUILD_DIR)
	verilator --binary --timing --assert -Wno-fatal -DPROTOCOL2_RT_SVA \
		-Irtl/include --top-module protocol2_rt_safety_tb \
		--Mdir $(BUILD_DIR)/protocol2_sva -o protocol2_sva \
		rtl/protocol/core/protocol2_rt_engine.sv \
		sim/protocol/protocol2_rt_assertions.sv \
		sim/protocol/protocol2_rt_safety_tb.sv
	$(BUILD_DIR)/protocol2_sva/protocol2_sva

soc-sva: $(STRESS_MEM) config | $(BUILD_DIR)
	verilator --binary --timing --assert -Wno-fatal -DASL_SOC_SVA \
		-Wno-TIMESCALEMOD -Wno-UNUSEDSIGNAL -Wno-UNUSEDPARAM \
		-Wno-PINCONNECTEMPTY -Wno-WIDTHTRUNC -Wno-WIDTHEXPAND \
		--top-module soc_dram_stress_tb --Mdir $(BUILD_DIR)/soc_sva \
		-o soc_sva -f rtl/rtl_smoke.f sim/models/axi_dram_model.sv \
		sim/assertions/axi_master_assertions.sv \
		sim/tb/soc_dram_stress_tb.sv
	$(BUILD_DIR)/soc_sva/soc_sva

cached-sva: $(CACHED_DRAM_MEM) config | $(BUILD_DIR)
	verilator --binary --timing --assert -Wno-fatal -DASL_SOC_SVA \
		-Wno-TIMESCALEMOD -Wno-UNUSEDSIGNAL -Wno-UNUSEDPARAM \
		-Wno-PINCONNECTEMPTY -Wno-WIDTHTRUNC -Wno-WIDTHEXPAND \
		--top-module soc_cpu_cached_dram_tb \
		--Mdir $(BUILD_DIR)/cached_sva -o cached_sva \
		-f rtl/rtl_smoke.f sim/assertions/axi_master_assertions.sv \
		sim/tb/soc_cpu_cached_dram_tb.sv
	$(BUILD_DIR)/cached_sva/cached_sva

verify-all: format-check test rv32f-random lint protocol-long protocol-real-10k protocol-sva \
	soc-sva cached-sva

test: headers cpu-source-check protocol-source-check $(SIMV) $(INFRA_SIMV) \
	$(CPU_SIMV) $(RV32F_UNIT_SIMV) $(RV32F_CORE_SIMV) $(RV32F_TRAP_SIMV) \
	$(PMP_CSR_SIMV) $(PMP_CORE_SIMV) \
	$(SOC_CPU_SIMV) $(FREERTOS_SIMV) $(CPU_IRQ_SIMV) \
	$(CACHED_DRAM_SIMV) $(UART_SIMV) \
	$(CNN_DMA_SIMV) $(ETH_DMA_SIMV) $(IRQ_TIMER_SIMV) $(STRESS_SIMV) \
	protocol-test
	vvp $(SIMV)
	vvp $(INFRA_SIMV)
	vvp $(CPU_SIMV)
	vvp $(RV32F_UNIT_SIMV)
	vvp $(RV32F_CORE_SIMV)
	vvp $(RV32F_TRAP_SIMV)
	vvp $(PMP_CSR_SIMV)
	vvp $(PMP_CORE_SIMV)
	vvp $(SOC_CPU_SIMV)
	vvp $(FREERTOS_SIMV)
	vvp $(CPU_IRQ_SIMV)
	vvp $(CACHED_DRAM_SIMV)
	vvp $(UART_SIMV)
	vvp $(CNN_DMA_SIMV)
	vvp $(ETH_DMA_SIMV)
	vvp $(IRQ_TIMER_SIMV)
	vvp $(STRESS_SIMV)

lint: config
	verilator --lint-only -Wall -Wno-fatal -Wno-TIMESCALEMOD \
		-Wno-UNUSEDSIGNAL -Wno-UNUSEDPARAM -Wno-PINCONNECTEMPTY \
		-f rtl/rtl_smoke.f --top-module soc_core_top
	verilator --lint-only -Wall -Wno-fatal -Wno-TIMESCALEMOD \
		-Wno-UNUSEDSIGNAL -Wno-UNSIGNED -Wno-UNUSEDPARAM \
		rtl/memory/axi_bram_slave.sv --top-module axi_bram_slave
	verilator --lint-only -Wall -Wno-fatal -Wno-TIMESCALEMOD \
		-Wno-UNUSEDSIGNAL -Wno-UNUSEDPARAM -Wno-PINCONNECTEMPTY \
		-Wno-DECLFILENAME -Wno-WIDTHTRUNC -Wno-WIDTHEXPAND \
		-f rtl/cpu_rv32im.f --top-module rv32im_cpu_subsystem

clean:
	rm -f $(SIMV) $(INFRA_SIMV) $(CPU_SIMV) $(RV32F_UNIT_SIMV) \
		$(RV32F_CORE_SIMV) $(RV32F_TRAP_SIMV) $(PMP_CSR_SIMV) \
		$(PMP_CORE_SIMV) $(SOC_CPU_SIMV) $(FREERTOS_SIMV) $(UART_SIMV) \
		$(STRESS_SIMV) $(CNN_DMA_SIMV) $(ETH_DMA_SIMV) $(IRQ_TIMER_SIMV) $(CPU_ELF) $(CPU_BIN) $(CPU_MEM) \
		$(CPU_IRQ_SIMV) $(CPU_IRQ_ELF) $(CPU_IRQ_BIN) $(CPU_IRQ_MEM) \
		$(CACHED_DRAM_SIMV) $(CACHED_DRAM_ELF) $(CACHED_DRAM_BIN) $(CACHED_DRAM_MEM) \
		$(FREERTOS_ROM_MEM) $(FREERTOS_ITCM_MEM) $(FREERTOS_DTCM_MEM) \
		$(STRESS_ELF) $(STRESS_BIN) $(STRESS_MEM) $(PROTOCOL_MMIO_SIMV) \
		$(PROTOCOL_SCHED_SIMV) $(PROTOCOL_SAFETY_SIMV) $(PROTOCOL_EXT_TICK_SIMV) \
		$(PROTOCOL_HX5_SEQ_SIMV) $(POSE_PROTOCOL_SIMV)
