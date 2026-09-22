# Address Map and Cacheability Contract

本文件中的數值由`config/asl_soc_config.json`產生；請勿直接修改generated header。

| Region | Start | End (inclusive) | CPU attribute |
|---|---:|---:|---|
| Boot ROM | `0x0000_0000` | `0x0000_1FFF` | local, uncached |
| ITCM | `0x0001_0000` | `0x0001_FFFF` | local, uncached |
| DTCM | `0x0002_0000` | `0x0002_FFFF` | local, uncached |
| Local MMIO | `0x1003_0000` | `0x1003_FFFF` | device, uncached |
| DMA DRAM window | `0x2000_0000` | `0x20FF_FFFF` | normal, uncached |
| General DRAM | `0x2100_0000` | `0x23FF_FFFF` | normal, cached |

MMIO pages：

| Peripheral | Base |
|---|---:|
| Protocol 2.0 RT | `0x1003_0000` |
| Interrupt controller | `0x1003_1000` |
| CNN shell | `0x1003_2000` |
| Ethernet/DMA shell | `0x1003_3000` |
| Machine timer | `0x1003_4000` |
| Pose Player | `0x1003_5000` |
| Safety supervisor | `0x1003_6000` |
| Host UART | `0x1003_7000` |

`address_attributes.sv`實作固定cacheability規則。Ethernet/CNN DMA descriptor與buffer必須配置在
`0x2000_0000–0x20FF_FFFF`；若firmware把DMA buffer放到cached區，硬體不提供cache coherence。

各page register定義見[`MMIO_REGISTERS.md`](MMIO_REGISTERS.md)。

## External AXI contract

- 32-bit address、32-bit data、4-bit byte strobe及4-bit ID。
- `soc_core_top`對外使用AXI4五通道訊號；目前Ethernet RX master只發出`AWLEN=0`單拍寫入。
- CPU cached data path會發出`ARLEN=3`的4-beat cache-line refill，store為write-through單拍write；
  此路徑已用burst-capable behavioral BRAM及AXI SVA驗證。
- DRAM滿載testbench目前配置128 KiB實體陣列以降低模擬記憶體，但地址仍從
  `0x2000_0000`開始；其CPU/CNN/Ethernet traffic使用單拍交易並加入可重現隨機延遲。
- MIG wrapper必須維持相同地址與response語意；PHY或板卡選擇不得改變此介面。
