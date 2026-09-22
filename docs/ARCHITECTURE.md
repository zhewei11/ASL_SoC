# ASL CNN 1 kHz SoC 架構

> 狀態基準：2026-09-22。本文描述目前 repository 中已存在的 RTL、韌體介面與模擬邊界，
> 不是板卡規格或未來功能提案。

本專案是一個可獨立模擬的 FPGA fabric SoC core：以專案內的 RV32IMF CPU 執行控制軟體，
接收 Ethernet L2 payload stream，透過 DMA 搬移影像資料，取得 CNN 分類結果，再由 CPU/RTOS
提交 20 軸 HX5-D20 命令給 DYNAMIXEL Protocol 2.0 硬體。板級 clock、DDR controller、
Ethernet MAC/PHY、USB-UART bridge 與 RS-485 transceiver 不屬於目前 `soc_core_top`。

若文件與實作不一致，判定順序如下：

1. `config/asl_soc_config.json`
2. RTL 與產生的 RTL／C header
3. 自動化測試
4. 本文件及其他說明文件

## 1. 系統邊界

目前最高層是 [`rtl/top/soc_core_top.sv`](../rtl/top/soc_core_top.sv)，定位為可合成、
不綁定 FPGA 型號的 SoC core。它對外提供：

- Clock、reset 與 safety 輸入。
- 32-bit Ethernet L2 payload RX stream。
- 32-bit AXI4 master，供外部 DRAM controller 接入。
- Host UART 的 serial RX/TX。
- Protocol 2.0 UART RX/TX、RS-485 direction request 與經 safety gate 後的最終 DE。
- Pose stream、狀態與 debug 訊號。

目前沒有 `board_top_xilinx`，也沒有任何已完成的 DDR MIG、Ethernet MAC/PHY、USB PHY、
QSPI boot 或 pin constraint 整合。因此「SoC 模擬通過」不等同「已可直接下載至任意開發板」。

## 2. 主要資料流

```text
Ethernet L2 RX stream
        |
        v
Ethernet S2MM DMA -----> uncached DRAM frame buffer
                                  |
                                  v
                         CNN MM2S DMA
                                  |
                                  v
                         fixed-latency CNN stub
                                  |
                           class / confidence
                                  |
                                  v
                              Pose Player
                                  |
                      observable pose stream

RV32IMF + FreeRTOS baseline
        |
        v
Protocol command bank A/B --> HX5 fixed RT sequencer --> Protocol 2.0 UART
                                                            |
                                                     safety-gated RS-485 DE
```

這條路徑有兩個重要限制：

- Ethernet 端目前只接收外部已整理好的 L2 payload stream；沒有 MAC、IP/UDP parser，
  也沒有 Ethernet TX datapath。
- CNN 端目前是固定延遲 stub，用於驗證 DMA、MMIO、IRQ 與後級控制流程；並非真實 INT8 CNN。

## 3. 模組分工

| 模組 | 位置 | 目前責任 |
|---|---|---|
| SoC 整合頂層 | `rtl/top/soc_core_top.sv` | Clock-domain 內的模組接線、參數與外部介面 |
| CPU cluster | `rtl/cpu/soc_cpu_cluster.sv` | RV32IMF、Boot ROM、ITCM、DTCM 與外部 AXI 路由 |
| MMIO subsystem | `rtl/interconnect/soc_mmio_subsystem.sv` | Peripheral page decode、LIC、timer 與 peripheral 接線 |
| AXI arbiter | `rtl/interconnect/axi4_4x1_arbiter.sv` | CPU 與 DMA 共用外部 AXI read/write channel |
| Ethernet RX | `rtl/ethernet/ethernet_rx_dma_shell.sv` | Stream 接收、frame 檢查與 S2MM DMA 控制 |
| CNN input DMA | `rtl/cnn/cnn_input_dma.sv` | 從 DRAM 以 MM2S burst 讀取 CNN input |
| CNN stub | `rtl/cnn/cnn_accelerator_stub.sv` | 固定延遲完成、class/confidence 與 IRQ |
| Pose path | `rtl/pose/` | Pose table、每 frame 限速輸出與相容模式 adapter |
| Protocol 2.0 | `rtl/protocol/core/` | 封包、CRC、UART、ping-pong SRAM 與 RT sequencer |
| Safety | `rtl/safety/safety_supervisor.sv` | E-stop、fault latch、watchdog、torque 與 DE gate |
| Host UART | `rtl/uart/host_uart_mmio.sv` | 8-N-1 console UART、FIFO 狀態與 IRQ |
| Shared frame tick | `rtl/top/rt_frame_tick.sv` | 預設 100 MHz 下每 100,000 cycles 產生 1 kHz tick |

## 4. CPU、RTOS 與本地記憶體

CPU RTL 完整保存在 `rtl/cpu/core/`，不依賴兄弟目錄的 CPU 原始碼。預設設定為：

- RV32IMF，`MISA=0x40101120`。
- Machine mode 與 User mode。
- 8-entry PMP，支援 TOR、NA4、NAPOT、lock 與 MPRV 存取檢查。
- 32-entry floating-point register file；`ENABLE_CPU_FPU=1`，可在資源受限 build 關閉。
- Instruction cache 與 data cache 都是 2-way、32 sets、16-byte line，也就是各 1 KiB。
- D-cache 採 write-through；I-cache 支援 next-line prefetch。

本地記憶體配置為 8 KiB Boot ROM、64 KiB ITCM 與 64 KiB DTCM。Instruction port 可直接
存取 Boot ROM 與 ITCM；data port 的本地區域是 DTCM。這是 Harvard 配置，程式常數若需要由
data load 讀取，linker 必須把它放入 DTCM，而不是假設 ITCM 可由 data port 讀取。

FreeRTOS 11.3 的 M-mode 基準映像已整合並驗證兩個 task、machine-timer tick 與 FPU context
switch。這只代表 RTOS bring-up 已成立；正式的 1 kHz trajectory task、CNN/Protocol driver、
U-mode task syscall port、WCET 與 stack high-watermark 尚未完成。

## 5. 位址與 cache 契約

| Region | 範圍 | CPU 屬性 |
|---|---:|---|
| Boot ROM | `0x0000_0000–0x0000_1FFF` | local、uncached、read-only |
| ITCM | `0x0001_0000–0x0001_FFFF` | local instruction memory、uncached |
| DTCM | `0x0002_0000–0x0002_FFFF` | local data memory、uncached |
| MMIO | `0x1003_0000–0x1003_FFFF` | device、uncached |
| DMA DRAM | `0x2000_0000–0x20FF_FFFF` | normal、uncached |
| General DRAM | `0x2100_0000–0x23FF_FFFF` | normal、cached |

硬體沒有 DMA/cache coherence。所有 Ethernet 或 CNN DMA descriptor 與 buffer 必須放在
uncached DRAM window；把 DMA buffer 放入 cached DRAM 會造成資料一致性風險。完整契約見
[`ADDRESS_MAP.md`](ADDRESS_MAP.md)與[`MEMORY_FABRIC.md`](MEMORY_FABRIC.md)。

## 6. 外部 AXI fabric

`soc_core_top`輸出 32-bit address、32-bit data、4-bit ID 的 AXI4 master。四個仲裁 slot 為：

| Slot | Master | 交易型態 |
|---:|---|---|
| 0 | CPU instruction | Cache-line read |
| 1 | CPU data | Cache-line read、write-through store |
| 2 | Multi-channel DMA | Ethernet S2MM write、CNN MM2S read |
| 3 | Reserved | 目前未使用 |

Read 與 write 分別 round-robin 仲裁；address handshake 遇到 backpressure 時會鎖定 owner，
write owner 由 AW 持有至 B，read owner由 AR 持有至 RLAST。DMA 最大 burst 預設 16 beats，
並在 4 KiB 邊界切分。詳細 channel ownership 見
[`AXI_MULTICHANNEL_DMA.md`](AXI_MULTICHANNEL_DMA.md)。

repository 內的 behavioral DRAM 只用於模擬。真正上板時，board wrapper 必須提供相同的
AXI response、burst 與 backpressure 語意。

## 7. MMIO 與中斷

| Peripheral | Base |
|---|---:|
| Protocol 2.0 RT | `0x1003_0000` |
| Local interrupt controller | `0x1003_1000` |
| CNN shell | `0x1003_2000` |
| Ethernet/DMA shell | `0x1003_3000` |
| Machine timer | `0x1003_4000` |
| Pose Player | `0x1003_5000` |
| Safety supervisor | `0x1003_6000` |
| Host UART | `0x1003_7000` |

LIC 的八個來源依序是 Ethernet frame、CNN、Protocol、Host UART、watchdog、safety、
pose-to-protocol error 與 Ethernet frame error。Machine timer 直接提供 CPU `MTIP`，LIC 提供
`MEIP`；`time` CSR 與 MMIO `mtime` 共用同一 counter。register offset、W1C 與 side effect
定義見[`MMIO_REGISTERS.md`](MMIO_REGISTERS.md)。

## 8. Ethernet、DMA 與 CNN

Ethernet RX 使用 `valid/ready/data/keep/last` 的 32-bit stream，將一個 frame 寫入預設位於
`0x2000_0000` 的 buffer，最大長度 25,600 bytes。S2MM 完成後可自動啟動 CNN MM2S；
buffer ownership 會保持到 CNN done 或 error，避免下一個 frame 覆寫尚未讀完的輸入。

CNN MM2S 讀取完整輸入並計算 byte count/checksum，之後交給固定延遲 stub。設定檔中的
`160x160x1`、16 lanes 與 256 KiB local SRAM 是預留的目標配置欄位，不代表目前已有相應的
MAC array 或 local SRAM datapath。真實模型的 graph、quantization、tensor ABI、memory layout
與 accelerator microarchitecture 必須另行凍結。

## 9. Pose 與 Protocol 2.0

預設 `CPU_OWNS_PROTOCOL_COMMANDS=1`。在此模式下，CPU/RTOS 是 Protocol command bank A/B 的
唯一寫入者；Pose Player 的 stream 保留為外部可觀察訊號，不會自動改寫 command SRAM。
`CPU_OWNS_PROTOCOL_COMMANDS=0` 是硬體相容模式，才會啟用 pose-to-protocol adapter。兩個 writer
不會同時存在。

預設 `USE_HX5_RT_SEQUENCER=1`，每個 frame 執行：

1. 一筆廣播 Sync Write，body 86 bytes，寫入 20 軸的 Goal Position 低 16 位與
   Goal Current 16 位。
2. 一筆單播 Read，body 5 bytes，接收預期 165-byte Status Packet。

Command 與 feedback bank 各 256 bytes，預設 bus baud 為 6 Mbps，右手 controller ID 為 110。
實際 Indirect Address mapping、bank ABI 與初始化前提見
[`HX5_D20_TABLESYNC.md`](HX5_D20_TABLESYNC.md)。Protocol 模組分層、CRC、stuffing、錯誤處理與
限制見[`DYNAMIXEL_PROTOCOL2_RTL_REPORT.md`](DYNAMIXEL_PROTOCOL2_RTL_REPORT.md)。

1 kHz 是 shared frame trigger cadence，不是無條件的通訊完成保證。communication deadline 與
command deadline 預設為 0，也就是 best-effort；只有軟體寫入非零 deadline，才啟用 strict
deadline enforcement。實機還必須驗證 bus baud、DE turn-around、controller 設定、碰撞與 BER。

## 10. Safety 與 Host UART

Safety supervisor 直接處理 E-stop、external fault、watchdog 與 torque-enable request。E-stop
assertion 會以組合路徑立即禁止 torque 並壓低最終 RS-485 DE；latched fault 解除後仍需要在
安全狀態下明確 clear。Safety fault 也會 abort/flush Protocol datapath，解除後必須提交新的完整
command bank 才能重新傳輸。

Host UART 是獨立的 8-N-1 MMIO peripheral，預設 115,200 baud，已包含 TX/RX、IRQ、framing
error 與 overrun 處理。USB 並未實作在 SoC 內；若開發板或產品需要 USB console，應在板外使用
USB-to-UART bridge，或在未來 board wrapper 整合獨立 USB device controller。

## 11. 已實作與延後項目

| 已在 RTL／模擬中建立 | 尚未建立或需實機確認 |
|---|---|
| RV32IMF、FPU、U-mode、PMP/MPRV | Production RTOS task 與 U-mode syscall port |
| Boot ROM、ITCM、DTCM、cache 與 AXI master | Board clock/reset、DDR MIG、pin/XDC、timing closure |
| Ethernet RX payload stream 與 S2MM | Ethernet MAC/PHY、IP/UDP parser、TX path |
| CNN MM2S、MMIO、IRQ、固定延遲 stub | 真實 INT8 CNN、MAC array 與 local SRAM datapath |
| Pose table/player 與兩種 command ownership 模式 | 正式 trajectory/control policy |
| Protocol 2.0 core 與固定 HX5 sequencer | RS-485 transceiver 電氣與真實 HX5 bus 驗證 |
| Safety supervisor 與 Host UART | USB bridge/controller、QSPI boot loader |
| Behavioral DRAM 與自動化回歸 | FPGA resource、post-route timing、長時間硬體可靠度 |

## 12. 設定與維護規則

`config/asl_soc_config.json`是平台參數的唯一可編輯來源，產生 RTL 與 firmware 共用常數。
修改 clock、memory map、buffer、baud 或 motor profile 時，不應直接手改 generated header。

架構文件只描述已存在的路徑；未完成的功能使用「尚未實作」標示，不把目標規格寫成現況。
新增 peripheral 或改變 ownership 時，至少同步更新：

- `config/asl_soc_config.json`
- RTL 與產生的 header
- `ADDRESS_MAP.md`／`MMIO_REGISTERS.md`
- 本文件與對應測試

## 13. 驗證入口

```sh
make test
make lint
make freertos-test
make verify-all
```

`make test`包含 CPU 與 Protocol source-ownership guard，防止 file list 再次引用 repository 外的
RTL。FreeRTOS 基準、PMP/MPRV、AXI backpressure、DMA boundary、Protocol 長時間排程與 safety
都有專用回歸。通過項目與尚需外部設備驗證的範圍，以
[`VERIFICATION_STATUS.md`](VERIFICATION_STATUS.md)為準。
