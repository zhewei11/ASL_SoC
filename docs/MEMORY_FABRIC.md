# Local Memory and External AXI Fabric

## Inferred local memory

`rtl/memory/axi_bram_slave.sv`是Boot ROM、ITCM與DTCM的共同Xilinx fabric baseline。

- 32-bit AXI4 data與4-bit ID。
- 支援INCR burst，CPU cache line的4-beat read可直接使用。
- 支援per-byte write strobe。
- 同一instance一次接受一個read或write transaction，write優先。
- 每個beat使用同步讀取狀態，讓綜合器推導block RAM而不是非同步LUT RAM。
- `READ_ONLY=1`時拒絕所有write並回`SLVERR`，用於Boot ROM。
- `INIT_FILE`可由JTAG/BRAM initialized firmware產生的hex檔初始化。

預定instance：

| Instance | Base | Bytes | Mode |
|---|---:|---:|---|
| Boot ROM | `0x0000_0000` | 8 KiB | Read-only、initialized |
| ITCM | `0x0001_0000` | 64 KiB | Read/write |
| DTCM | `0x0002_0000` | 64 KiB | Read/write |

本模組不實例化舊ASIC macro，也不依賴特定Xilinx primitive。上板資源收斂時可在相同AXI
wrapper內改用XPM，而不改CPU或address map。

## External AXI arbiter

`rtl/interconnect/axi4_4x1_arbiter.sv`提供四個master到外部DRAM的一個AXI4介面：

| Slot | Owner |
|---:|---|
| 0 | CPU instruction cache的外部DRAM refill |
| 1 | CPU data cache的外部DRAM refill/write-through |
| 2 | 雙通道AXI burst DMA：Ethernet S2MM＋CNN MM2S |
| 3 | 保留 |

Read與write各自round-robin。Write owner從AW handshake鎖定到B handshake；read owner從AR
handshake鎖定到`RVALID && RREADY && RLAST`。因此另一個master不能在burst中間插入。

目前使用前三個slot；雙通道DMA以同一AXI master在slot 2獨立進行read/write。每個burst預設
最多16個32-bit beat，且不得跨越4 KiB邊界。Boot ROM／ITCM／DTCM先由本地
`axi4_1x3_decoder`攔截，不佔用外部arbiter；只有未命中本地區域的CPU請求會到slot 0／1。
Arbiter限制每個方向最多一筆outstanding transaction，先以可證明正確性為優先；
未來若增加outstanding深度，必須加入ID/owner scoreboard，不能只移除owner lock。

Behavioral DRAM model支援AXI INCR burst、可參數化read response latency、write response latency及transaction
間ready stall，並可疊加fixed-seed隨機長尾。滿載回歸目前使用5／4／3 cycles固定延遲，
另加入0–11／0–9／0–7 cycles隨機read／write／ready stall，確認arbiter仍能讓CPU及CNN
有界前進。CPU cached window另用burst-capable behavioral BRAM驗證4-beat refill與write-through；
兩條路徑均通過AXI payload-stability SVA。
