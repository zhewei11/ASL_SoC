# SoC MMIO Registers

所有request都使用32-bit byte address。以下規則是Platform ABI 1.0的固定access semantics：

- Register是little-endian、32-bit且必須4-byte aligned；firmware只使用自然對齊的32-bit存取。
- Master必須保持`valid/address/write/wdata/wstrb`直到`ready`；每次`valid && ready`只完成一筆交易。
- `wstrb[3:0]`分別控制`wdata[31:24]`至`wdata[7:0]`的四個byte lane；RW register保留未被
  strobe選中的byte。WO pulse或W1C欄位只採用其所在byte lane。
- RO register寫入與合法page內未定義offset的寫入都忽略；合法page內未定義offset讀回0。
- 未實作page在同cycle完成、讀回0並assert`mmio_error`，不會誤寫其他周邊。內部CPU目前
  不把`mmio_error`轉成exception，因此firmware不得用未實作page探測功能，必須讀System
  Control capability bits。
- 除明確標示W1P、W1C或read-to-consume的register外，讀取沒有side effect。跨周邊或DMA
  ownership交接需要嚴格排序時，firmware使用`fence iorw, iorw`。

## Local Interrupt Controller — `0x1003_1000`

| Offset | Name | Access | Description |
|---:|---|---|---|
| `0x000` | ID | RO | `0x4C494330` (`LIC0`) |
| `0x004` | INFO | RO | Source count與priority width |
| `0x008` | PENDING | RO | Latched pending mask |
| `0x00C` | ENABLE | RW | Enable mask |
| `0x010` | EDGE | RW | 1=edge、0=level source |
| `0x014` | RAW | RO | Raw source levels |
| `0x018` | THRESHOLD | RW | Global priority threshold |
| `0x01C` | CLAIM_COMPLETE | R/W | Read claim；write同一ID完成 |
| `0x020+4n` | PRIORITY[n] | RW | Source n+1 priority |
| `0x040` | PENDING_SET | WO | Software-set mask |
| `0x044` | PENDING_CLEAR | WO | Software-clear mask |
| `0x048` | IN_SERVICE | RO | Claimed source mask |

固定source ID如下。這些數值是firmware ABI，後續不得重新編號；若來源被移除，ID保留。

| ID | Source | Reset trigger mode |
|---:|---|---|
| 1 | Ethernet frame | edge |
| 2 | CNN | level |
| 3 | Protocol 2.0 | level |
| 4 | Host UART | level |
| 5 | Watchdog | level |
| 6 | Safety | level |
| 7 | Pose-to-Protocol error | level |
| 8 | Ethernet frame error | edge |

相同priority時最低source ID優先。CPU的`mcause`仍是Machine External Interrupt；實際來源必須
讀`CLAIM_COMPLETE`取得，服務完成後把同一ID寫回。

## CNN — `0x1003_2000`

| Offset | Name | Access | Description |
|---:|---|---|---|
| `0x000` | CONTROL | RW/W1P | bit0 Start、bit1 Auto-start enable、bit2 Clear IRQ |
| `0x004` | STATUS | RO | bit1 Busy、bit2 Done pulse、bit3 Error、bit4 IRQ |
| `0x008` | INPUT_ADDRESS | RW | Manual-start DMA input address |
| `0x00C` | INPUT_BYTES | RW | Manual-start input length |
| `0x010` | INPUT_CHECKSUM | RO | Latest Ethernet RX checksum |
| `0x014` | CLASS_CONFIG | RW | bit31 force、bits15:8 confidence、bits7:0 class |
| `0x018` | RESULT | RO | bits15:8 confidence、bits7:0 class |
| `0x01C` | SEQUENCE | RO | Completed CNN command count |
| `0x020` | DMA_CHECKSUM | RO | MM2S burst DMA由DRAM讀回資料的XOR checksum |
| `0x024` | DMA_BYTES_READ | RO | 最近一次成功MM2S DMA的實際byte count |

Auto-start預設開啟。Ethernet frame成功DMA完成後會自動啟動CNN；若同cycle又由軟體Start，
manual address/length具有優先權。Start handshake會先鎖存address/length，避免單cycle command
pulse結束後DMA讀到後續mux值。

## Ethernet RX DMA — `0x1003_3000`

| Offset | Name | Access | Description |
|---:|---|---|---|
| `0x000` | STATUS | RO | bit0 done、bit1 error、bit2 buffer held by CNN |
| `0x004` | BUFFER_BASE | RO | Uncached DRAM frame buffer base |
| `0x008` | MAX_BYTES | RO | Maximum accepted frame bytes |
| `0x00C` | FRAME_BYTES | RO | Latest completed byte count |
| `0x010` | CHECKSUM | RO | Latest XOR checksum |
| `0x014` | SEQUENCE | RO | Completed frame count |

Auto-CNN模式下，成功frame完成後DMA會保留buffer ownership並對stream施加backpressure；
CNN完成或錯誤後才釋放，避免下一frame覆寫CNN正在讀取的資料。Malformed、zero-byte及
oversize frame會吸收到`last`，但不會在buffer範圍外發出AXI write。

## Machine Timer — `0x1003_4000`

| Offset | Name | Access | Description |
|---:|---|---|---|
| `0x000` | MTIMECMP_LO | RW | 64-bit compare low word |
| `0x004` | MTIMECMP_HI | RW | 64-bit compare high word |
| `0x008` | MTIME_LO | RW | CPU-clock counter low word |
| `0x00C` | MTIME_HI | RW | CPU-clock counter high word |

`mtime >= mtimecmp`時直接驅動RV32IMF MTIP；reset compare為全1，軟體寫mtime的cycle暫停自增。

## Pose Player — `0x1003_5000`

| Offset | Name | Access | Description |
|---:|---|---|---|
| `0x000` | CONTROL | W1P | bit0 apply manual class |
| `0x004` | STATUS | RO | bit16 busy、bits7:0 active class |
| `0x008` | CLASS | RW | Manual target class |
| `0x00C` | MAX_STEP | RW | Maximum raw-position delta per 1 kHz frame |
| `0x010` | SEQUENCE | RO | Committed 20-axis frame count |
| `0x014` | PROTOCOL_STATUS | RO | bit0 hardware adapter present、bit1 busy、bit2 error、bit3 committed bank |
| `0x018` | PROTOCOL_SEQUENCE | RO | Latest sequence verified after Protocol bank commit |
| `0x01C` | HAND_ID | RW | HX5-D20 target ID, default 110; values 0–252 |

在預設`CPU_OWNS_PROTOCOL_COMMANDS=1`模式，Pose Player輸出僅保留作為可觀察介面；
CPU/RTOS透過Protocol MMIO選擇inactive command bank，並建立一個HX5-D20 Sync Write body
與一個Read body。若以elaboration參數選擇`=0`，則改由硬體adapter完成相同操作。每軸循環命令4 bytes，
依序為Goal Position低16位及Goal Current 16位；20軸payload共80 bytes。Read一次取得
20軸位置、速度、電流與五指45-byte觸覺資料。兩個body含對齊共96 bytes，寫入後再更新
sequence與commit。兩種command producer是互斥的；完整ABI見
[`HX5_D20_TABLESYNC.md`](HX5_D20_TABLESYNC.md)。

## Safety — `0x1003_6000`

| Offset | Name | Access | Description |
|---:|---|---|---|
| `0x000` | STATUS | RO | Torque allow、DE inhibit、watchdog及latched fault |
| `0x004` | CONTROL | RW/W1P | bit0 torque request、bit1 WDT enable、bit2 kick、bit3 clear |

Software控制只能增加限制，不能覆蓋`emergency_stop_n`或`external_fault`。即使Protocol core
正在assert DE，Safety supervisor仍會直接gate最終`rs485_de`。

## Host UART — `0x1003_7000`

| Offset | Name | Access | Description |
|---:|---|---|---|
| `0x000` | ID | RO | `0x55415254` (`UART`) |
| `0x004` | STATUS | RO | TX ready/busy、RX valid、framing/overrun、IRQ |
| `0x008` | TX_DATA | WO | 寫入低8-bit；TX busy時request保持等待 |
| `0x00C` | RX_DATA | RO | 讀取低8-bit並consume；無資料時request保持等待 |
| `0x010` | DIVISOR | RO | 每個UART bit的clock數 |
| `0x014` | IRQ_ENABLE | RW | bit0 TX done、bit1 RX valid、bit2 error |
| `0x018` | IRQ_STATUS | RW1C | bit0 TX done、bit1 RX valid、bit2 framing/overrun |

UART使用8-N-1，支援RX雙級同步、framing error、保留最舊byte的overrun行為及IRQ。

## System Control／版本能力 — `0x1003_8000`

此page全部為RO。它描述目前bitstream真正實作的能力，不用來表示尚未完成的roadmap。

| Offset | Name | Access | Description |
|---:|---|---|---|
| `0x000` | SYSTEM_ID | RO | `0x41534C30` (`ASL0`) |
| `0x004` | PLATFORM_ABI_VERSION | RO | bits31:16 major、bits15:0 minor；目前1.0 |
| `0x008` | RTL_VERSION | RO | bits31:16 major、bits15:0 minor；目前1.1（加入external debug） |
| `0x00C` | MISA | RO | 固定`0x40101120`，即RV32IMF加U-mode，A/C bit為0 |
| `0x010` | CAPABILITIES0 | RO | 已實作能力bit map，見下表 |
| `0x014` | CPU_HZ | RO | CPU clock frequency，預設100,000,000 |
| `0x018` | TOPOLOGY | RO | bits15:8 IRQ source count、bits7:0 hart count |
| `0x01C` | BUILD_ID | RO | 可重現release/build識別；開發版預設0 |

`CAPABILITIES0`：

| Bit | Capability |
|---:|---|
| 0–6 | RV32I、M、F、U-mode、PMP、HPM、L1 cache |
| 7 | RISC-V External Debug 1.0最小組態（JTAG DTM、halt/resume、abstract register/memory） |
| 8–15 | Protocol 2.0、LIC、Machine Timer、Host UART、Ethernet DMA、CNN、Pose、Safety |

目前值為`0x0000_FFFF`。軟體應以bit測試能力，不應用版本號推測單項功能。bit 7不代表
Program Buffer、SBA、trigger或single-step；debugger應先讀`abstractcs`與各標準能力欄位。

Protocol 2.0 register page位於`0x1003_0000`，register ABI沿用既有
[`fw/include/protocol2_mmio.h`](../fw/include/protocol2_mmio.h)，不需引用外部專案header。
SoC預設使用固定HX5 sequencer；原descriptor region 4只保留Read control、response timeout與
inter-byte timeout三個相容設定，不再實例化1 KiB descriptor RAM。
預設亦設定`CPU_OWNS_PROTOCOL_COMMANDS=1`，由RTOS透過MMIO寫入command bank；硬體Pose
adapter只在相容模式實例化。
