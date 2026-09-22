# ASL CNN 1 kHz Dexterous Hand SoC

獨立的FPGA fabric RV32IMF SoC專案。目前提供可合成、可整機模擬且不綁定板卡的
`soc_core_top`；Clock／DDR controller／Ethernet MAC/PHY／QSPI與實體I/O需由後續
board wrapper整合。

## Baseline

- Fabric RV32IMF CPU，包含單精度F-extension與32-entry浮點暫存器檔。
- Boot ROM、64 KiB ITCM、64 KiB DTCM。
- Cached／uncached地址解碼與AXI Behavioral DRAM。
- 32-bit Ethernet L2 frame stream與RX DMA shell。
- CNN MMIO／DMA shell及固定延遲stub。
- Host UART、Pose Lookup、1 kHz Pose Player與硬體Safety override。
- CPU/RTOS控制面、固定HX5 Protocol 2.0 RT sequencer及Command／Feedback SRAM。

目前系統架構與已實作／未實作邊界位於：

[`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)

所有保留文件與用途見[`docs/README.md`](docs/README.md)。

記憶體與AXI fabric契約見
[`docs/MEMORY_FABRIC.md`](docs/MEMORY_FABRIC.md)。

## Directory layout

```text
rtl/
  top/           soc_core_top與未來board wrapper邊界
  cpu/           專案自有RV32IMF pipeline／RV32M/F／CSR／cache與SoC整合
  memory/        Boot ROM、ITCM、DTCM與DRAM介面
  interconnect/  地址解碼、Cache bypass與AXI仲裁
  ethernet/      通用L2/payload stream接收與RX DMA
  cnn/           CNN command/result shell與stub
  uart/          Host UART
  pose/          Pose table、player與limiter
  safety/        E-stop、watchdog與RS-485 inhibit
  protocol/      專案自有Protocol 2.0 UART／封包／RT engine／MMIO RTL
sim/
  tb/            Testbench
  models/        Behavioral DRAM、Ethernet source與裝置模型
fw/
  *.S            Boot、interrupt與DRAM測試firmware
  *.ld           Boot與FreeRTOS linker scripts
  include/       MMIO與共享ABI header
config/          可產生RTL與C header的唯一設定來源
docs/            ABI、驗證結果與設計決策
scripts/         Build、產生器與回歸工具
constraints/     後續板卡時脈與pin constraints
```

## Current boundary

目前交付物是板卡無關的SoC core與behavioral simulation環境。CPU、記憶體介面、DMA、
CNN stub、Pose、Protocol 2.0、Safety及FreeRTOS基準已可整機回歸；真實CNN、正式控制task、
Ethernet MAC/IP/UDP、DDR controller、USB bridge與實體板級I/O仍屬後續整合範圍。

## Current implementation status

目前已完成的可執行整合項目：

- `config/asl_soc_config.json`是唯一可編輯平台設定，產生RTL與firmware header。
- `soc_core_top`已凍結Ethernet stream、外部AXI4、Safety及Pose-to-Protocol介面。
- CPU相容uncached MMIO request/ready介面與CNN／Ethernet／Pose／Safety register bank。
- 雙通道AXI burst DMA的S2MM channel可依`tkeep`把Ethernet frame寫入uncached DRAM；
  MM2S channel由DRAM完整讀取CNN輸入。兩個方向可同時前進，burst預設為16 beats並遵守
  AXI 4 KiB邊界。
- CNN MM2S DMA計算讀取checksum，再由stub於固定cycles後產生
  Class ID、Confidence與IRQ。
- Class 0／1／2的Neutral／Pose A／Pose B硬體路徑已驗證；正式預設由CPU/RTOS提交20軸command bank。
- E-stop、external fault及watchdog不依賴CPU；E-stop assertion對輸出是組合式立即生效。
- 已驗證的Protocol 2.0 UART、packet TX/RX、RT engine、SRAM與MMIO wrapper已放入
  `rtl/protocol/core`，最終RS-485 DE由Safety gate。
- Protocol預設採best-effort deadline模式：1 kHz仍是frame trigger cadence，但不再以
  worst-case schedule budget拒絕4 Mbps／20-device傳輸；軟體可寫入非零deadline恢復
  strict real-time enforcement。
- Behavioral AXI DRAM與端到端smoke test已建立。
- RV32IMF CPU source已完整放入`rtl/cpu/core`；file list不再引用兄弟專案的CPU RTL。
  FPU與32-entry floating register file已納入，預設`ENABLE_CPU_FPU=1`且`MISA.F=1`；
  資源受限build仍可用parameter停用FPU。
- CPU已加入RISC-V U-mode與8-entry PMP（TOR／NA4／NAPOT、lock、取指／load／store
  access-fault），可讓RTOS kernel留在M-mode並隔離U-mode task；整合方式見
  [`docs/RTOS_PMP_GUIDE.md`](docs/RTOS_PMP_GUIDE.md)。
- FreeRTOS 11.3 M-mode基準映像已可從Boot ROM啟動，程式／常數／資料分別載入ITCM與DTCM；
  整機回歸會驗證兩個task、machine-timer tick與FPU context switch。正式trajectory、CNN及
  Protocol driver task尚未接入。
- CPU由8 KiB initialized Boot ROM啟動，64 KiB ITCM／DTCM使用inferred BRAM，
  本地位址不會進外部DRAM AXI。
- CPU general DRAM cached路徑已驗證4-beat line refill、cache hit及write-through。
- CPU uncached MMIO已直接接到新SoC page decoder，不經舊`rtos_core` MMIO decoder。
- 8-source local interrupt controller與64-bit Machine Timer已接到RV32IMF MEIP／MTIP及time CSR。
- 四slot外部AXI arbiter已接入：CPU instruction/data分別使用slot 0／1，雙通道DMA的
  S2MM／MM2S共用slot 2，slot 3保留；address grant在AW/AR backpressure期間會鎖定。
- 最小RV32IMF firmware會寫DTCM signature、讀Protocol ID／CNN status，並驗證
  `FADD.S`、`FMUL.S`、`FDIV.S`、`FCVT.W.S`、`FLW/FSW`、`fcsr`與`mstatus.FS`。

- Host UART 8-N-1 TX/RX、MMIO、IRQ、framing與overrun處理已接入。
- CPU helper會依官方Indirect Data格式打包成單一HX5-D20 Sync Write：20軸各傳Goal Position
  低16位與Goal Current 16位，並建立165-byte全手回授Read。硬體adapter保留為elaboration相容
  選項，兩者不會同時成為MMIO writer。右手ID預設110，
  也可由軟體修改。命令／回授bank各為256 bytes；實際配置與封包ABI見
  [`docs/HX5_D20_TABLESYNC.md`](docs/HX5_D20_TABLESYNC.md)。
- 真實INT8 datapath仍未固定；目前CNN DMA後端接固定延遲stub。CPU／Ethernet／CNN
  DRAM滿載及Protocol 1 kHz scheduler/timing回歸已建立。詳見
[`docs/VERIFICATION_STATUS.md`](docs/VERIFICATION_STATUS.md)。

## Run

```sh
make test
make lint
make freertos-test
make protocol-long protocol-real-10k protocol-sva soc-sva cached-sva
# 或一次執行全部：make verify-all
```

`make test`會先執行CPU與Protocol source ownership guards，避免file list日後又誤接
`../rtos_core`的RTL。另有RV32F core／trap、Protocol external-tick、Pose malformed-frame、
一百萬個加速frame、10,000個真實100,000-cycle frame及Protocol／SoC／cached-DRAM SVA回歸，
詳細項目見
[`docs/VERIFICATION_STATUS.md`](docs/VERIFICATION_STATUS.md)。
