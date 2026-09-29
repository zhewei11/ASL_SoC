# CPU Performance Monitor

本專案的 RV32IMF CPU 除了標準的 `mcycle` 與 `minstret`，也實作四組 64-bit hardware
performance monitor（HPM）counter。用途是讓 RTOS 在真實硬體上量測 branch prediction、cache
miss、pipeline stall 與 trap，而不依賴模擬器內部訊號。

CSR 位址遵循 RISC-V HPM 配置，但 event mask 是 ASL CPU 自己的定義；它參考 E906 的可觀測性設計，
不宣稱與玄鐵 `mhpmevent` 編碼或工具軟體二進位相容。

## CSR 配置

| 功能 | Low CSR | High CSR | Event selector |
|---|---:|---:|---:|
| HPM3 | `mhpmcounter3` `0xB03` | `0xB83` | `mhpmevent3` `0x323` |
| HPM4 | `mhpmcounter4` `0xB04` | `0xB84` | `mhpmevent4` `0x324` |
| HPM5 | `mhpmcounter5` `0xB05` | `0xB85` | `mhpmevent5` `0x325` |
| HPM6 | `mhpmcounter6` `0xB06` | `0xB86` | `mhpmevent6` `0x326` |

U-mode 的唯讀 aliases 是 `hpmcounter3..6`（`0xC03..0xC06`）與高字
`0xC83..0xC86`。M-mode 必須先設定 `mcounteren[3:6]`，否則 U-mode 存取會產生
illegal-instruction trap。

`mcountinhibit` 位於 `0x320`：

- bit 0：停止 `mcycle`。
- bit 2：停止 `minstret`。
- bit 3–6：分別停止 HPM3–HPM6。
- `time` 使用 SoC machine timer，不受 `mcountinhibit` 控制。

## Event selector

`mhpmevent3..6` 的低 8 bits 是本核心定義的 event mask，高位固定為零。每個 clock 只要所選的
任一事件成立，對應 counter 增加一次；同一週期發生兩個被選事件也只增加一次。

| Bit | Mask | 事件 |
|---:|---:|---|
| 0 | `0x01` | 已完成的 branch 或 jump |
| 1 | `0x02` | predictor redirect；包含方向／目標預測錯誤及 stale BTB |
| 2 | `0x04` | I-cache demand miss；不計背景 next-line prefetch |
| 3 | `0x08` | D-cache demand load miss；不計 write-through store miss |
| 4 | `0x10` | frontend stall cycle；非 WFI／flush 且沒有接受新取指 |
| 5 | `0x20` | backend stall cycle；EX 有有效指令但該週期無法完成 |
| 6 | `0x40` | trap entry；包含同步 exception 與非同步 interrupt |
| 7 | `0x80` | 成功完成 EX 的 load/store；不計 PMP access fault |

Reset 後的預設值方便直接觀察最常用的四項：

| Counter | 預設 selector |
|---|---|
| HPM3 | branch/jump `0x01` |
| HPM4 | predictor redirect `0x02` |
| HPM5 | I-cache demand miss `0x04` |
| HPM6 | D-cache demand load miss `0x08` |

若要量測 stall，可在 M-mode 寫入：

```c
__asm__ volatile ("csrw 0x323, %0" :: "r" (0x10u)); /* HPM3: frontend stall */
__asm__ volatile ("csrw 0x324, %0" :: "r" (0x20u)); /* HPM4: backend stall */
__asm__ volatile ("csrw 0xB03, zero");
__asm__ volatile ("csrw 0xB83, zero");
__asm__ volatile ("csrw 0xB04, zero");
__asm__ volatile ("csrw 0xB84, zero");
```

RV32 讀取 64-bit counter 時，應使用 high-low-high sequence；若兩次 high 不同就重新讀取，以避免
low word rollover 造成不一致快照。要量測一段 RTOS task，先用 `mcountinhibit` 停止 counter、清零、
設定 event selector，再解除 inhibit；量測結束後再次 inhibit 再讀值。

## 驗證

- `sim/tb/hpm_csr_tb.sv`：event selection、counter inhibit、64-bit read/write 與 U-mode gating。
- `sim/tb/cache_hpm_event_tb.sv`：I-cache demand miss、D-cache load miss及 store 排除語意。
- `sim/tb/soc_cpu_cached_dram_tb.sv`：完整 SoC 啟動後檢查 I/D-cache event 已進入 HPM counter。

執行完整回歸：

```sh
make test
make lint
```
