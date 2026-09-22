# Verification Status

更新日期：2026-09-22

## Passing regression

執行：

```sh
make test
make lint
```

目前結果：

- Icarus端到端smoke regression：`283 checks passed`。
- AXI/BRAM infrastructure regression：`13 checks passed`。
- 獨立RV32IMF Boot ROM regression：`16 checks passed`。
- RV32F arithmetic／conversion／flag unit regression：`29 checks passed`。
- RV32F RNE differential regression：`180,000 checks passed`（不計入下方標準回歸總數）。
- RV32F core pipeline／forwarding／MEM-stall regression通過。
- RV32F FS=Off／reserved dynamic rounding-mode精確trap regression通過。
- 完整`SoC Core`內部CPU boot regression：`17 checks passed`。
- FreeRTOS 11.3整機基準回歸：`7 checks passed`；兩個task、machine-timer tick與FPU context
  switch於`403,963 cycles`內完成。
- CPU／LIC／Machine Timer interrupt firmware regression：`10 checks passed`。
- CPU cached DRAM／4-beat cache-line refill regression：`8 checks passed`。
- Host UART serial/fault regression：`16 checks passed`。
- CNN input burst DMA boundary／fault regression：`20 checks passed`。
- Ethernet RX DMA boundary／ownership／fault regression：`16 checks passed`。
- LIC／Machine Timer register與精確邊界unit regression：`21 checks passed`。
- CPU／Ethernet／CNN randomized delayed-DRAM saturation regression：`16 checks passed`。
- 本地Protocol MMIO／baud／fault／HX5 full-frame／20-device regression：`68 checks passed`。
- Protocol RT safety regression：`9 checks passed`。
- 固定HX5 RT sequencer profile／兩筆transaction／bank／feedback regression：`27 checks passed`。
- Protocol external-frame-tick regression通過；internal timer不會在external mode偷跑frame。
- Pose Protocol adapter malformed-frame regression通過；缺軸、重複軸、越界軸均不得commit。
- 平台JSON負向設定測試：`11 tests passed`。
- 另通過RV32F core／trap、external-tick、Pose adapter，以及2個完整時序frame加10,000個加速frame
  的scheduler regression。單項計數會隨測試擴充，本文不維護容易失真的總和。
- Protocol一百萬個加速frame及10,000個真實100,000-cycle frame長時間回歸通過；
  Protocol SVA七項property通過。
- SoC AXI backpressure SVA涵蓋AW、W、AR穩定性與word access契約。
- Cached DRAM亦以Verilator/SVA交叉驗證一筆4-beat refill服務同一cache line的全部load。
- Verilator synthesizable RTL lint：無error、無warning。
- CPU source ownership guard：25個core RTL檔案位於本專案，file list無外部CPU RTL引用。
- Protocol source ownership guard：11個core RTL檔案位於本專案，file list無外部Protocol RTL引用。
- JSON平台設定驗證成功，產生43個RTL/C共用常數。

已檢查內容：

- MMIO、DMA uncached與general DRAM cached地址屬性。
- Ethernet `valid/ready/data/keep/last`到AXI DRAM的byte-lane與frame byte count。
- Frame completion自動啟動CNN DMA及fixed-latency stub。
- CNN MM2S DMA以最長16-beat burst完整讀取DRAM input、處理非4-byte整數長度、4 KiB
  boundary切分並比對checksum／byte count；由AXI slot 2回報ID／RESP／RLAST錯誤。
- CNN DMA fault injection涵蓋zero length、unaligned address、超過最大長度、AXI error response、
  unexpected RID及missing RLAST；錯誤request不會發出AXI交易。
- Ethernet S2MM DMA以burst寫入，fault injection涵蓋zero-byte、oversize、BRESP error與
  unexpected BID；oversize frame不會發出超出frame buffer的AXI write。
- Auto-CNN frame完成後buffer ownership保持到CNN done/error，stream backpressure避免下一frame
  覆寫CNN正在讀取的DRAM資料。
- CNN Class ID／Confidence／Done IRQ。
- CNN class設定、result及Ethernet sequence的MMIO讀寫路徑。
- 未配置的MMIO page會完成request並回報`mmio_error`，不會讓CPU永久等待。
- 既有Protocol 2.0 ID register可經SoC MMIO讀取。
- Protocol UART、TX/RX、packet SRAM、RT engine及MMIO wrapper均由`rtl/protocol/core`
  的本地來源實際編譯。
- Class 1選擇Pose A，依序輸出20個motor index與position後才commit。
- E-stop無需等待clock即可清除`torque_enable_allow`並assert `rs485_de_inhibit`。
- 實體fault解除後仍保持latched，且只能在安全狀態明確clear。
- Watchdog timeout進入相同硬體安全狀態。
- Protocol要求DE時可正常通過；E-stop assertion可組合式強制壓低最終DE。
- Latched safety fault會同步送入Protocol wrapper的`external_abort`，停用RT、flush
  Protocol TX/RX/UART direction FSM，並使舊command snapshot失效；安全解除後需有新的
  完整command bank才可重新傳輸。
- Firmware generated/config MMIO headers通過C11 syntax與static assertion檢查。
- AXI write owner由AW鎖定到B，read owner由AR鎖定到RLAST。
- AW／AR尚未handshake而被backpressure時，arbiter會鎖住address grant；SVA曾找到並關閉
  competing master造成address改變的問題。
- Round-robin競爭、read backpressure、2-beat burst及per-byte write strobe。
- Read-only Boot ROM write回`SLVERR`。
- CPU由8 KiB Boot ROM執行真實RV32IMF firmware並寫入DTCM signature。
- Boot ROM／ITCM／DTCM的inferred BRAM初始化與RTL file-list相依已納入build，避免RTL更新後
  誤用舊模擬執行檔。
- 獨立CPU與完整SoC Boot regression均由`rtl/cpu/core`內的pipeline/cache實際編譯執行。
- CPU uncached MMIO讀到Protocol 2.0 ID及CNN status。
- `MISA=0x40101120`，F與U bit均為1；firmware仍以`rv32imf_zicsr`／`ilp32f`建立。
- U-mode、8-entry PMP與MPRV已通過49項CSR／比對測試，涵蓋TOR、NA4、NAPOT、entry priority、
  跨區拒絕、lock、MPRV及cause 1／5／7；完整CPU回歸亦確認`mret`可進入U-mode，且被拒絕的store
  不會送上data bus；跳到非X區域也會精確產生instruction access fault。
- Boot firmware實際通過FADD.S、FMUL.S、FDIV.S、FCVT.W.S、FLW／FSW、fcsr與
  `mstatus.FS=Dirty`檢查，且沒有unexpected trap。
- RV32F unit通過29項算術、比較、轉換、rounding、NaN／Inf與exception flag檢查；
  另以host IEEE-754 reference完成180,000筆FADD／FSUB／FMUL／FDIV／FSQRT／FMA隨機差分；
  core層再驗證FMA、RAW forwarding、MEM stall結果保存及精確illegal trap。
- Boot ROM／ITCM／DTCM本地請求不會逃逸到外部DRAM AXI。
- CPU general DRAM store使用write-through單拍AXI，首次load使用一筆4-beat cache-line refill，
  同一line後續load由D-cache hit完成且資料一致。
- Internal CPU啟用時，外部debug MMIO requester不會與CPU爭用。
- CPU firmware以LIC software pending觸發`mcause=0x8000000B`，完成claim/complete後再由
  `mtimecmp`觸發`mcause=0x80000007`；CPU time CSR與MMIO mtime共用同一counter。
- 20軸Pose依官方Indirect Data格式正確打包成86-byte Sync Write body及5-byte Read body；
  測試逐byte檢查ID 110、address 799/634、20筆4-byte控制資料、padding及兩顆command bank。
- 連續Pose frame在Protocol bank B／A間交替，且commit sequence讀回一致。
- Pose player與Protocol RT engine共用同一個SoC `rt_frame_tick`；回歸確認external-tick
  mode不會由內部period counter額外產生frame。
- Pose adapter以20-bit seen mask驗證完整軸集合；缺軸、重複、順序錯誤、`pose_last`
  錯誤或index 20–31均拒絕commit，保留上一個完整bank。
- Host UART TX/RX 8-N-1、baud divisor、TX/RX IRQ、W1C、framing與overrun。
- RV32IMF boot firmware可經Host UART MMIO送出boot marker。
- Stress firmware透過正常CPU MMIO設定legacy Protocol descriptor／command SRAM與CNN DMA，
  再持續掃描uncached DRAM。
- 五個完整100,000-cycle Protocol frame在CPU／Ethernet／CNN DRAM滿載模擬下完成，
  trigger interval均為100,000 cycles，沒有deadline miss。
- Behavioral DRAM除5-cycle read、4-cycle write-response及3-cycle ready stall外，另以固定seed
  對每筆加入0–11、0–9及0–7 cycle的可重現隨機長尾。
- 隨機延遲滿載實測：CPU 9,237次read、CNN 132,432次read、Ethernet 11,809次write／29個
  25,600-byte frame、CNN 20次完成。
- CPU與CNN同時要求read channel時，round-robin最大觀察等待分別為45／41 cycles，兩者均持續前進。
- Protocol使用真實6 Mbps RS-485 TX path；frame cycles為2,377，700 us deadline的
  minimum slack為67,623 cycles。
- Legacy generic Protocol RT的`COMM_DEADLINE=0`與`COMMAND_DEADLINE=0`代表best-effort模式；
  4 Mbps／20-device相容回歸不再被133,298-cycle worst-case budget阻擋，20個response皆通過
  CRC與ID mapping，實測frame cycles為67,869。
- Legacy generic Protocol額外驗證strict timing三者關係、25筆descriptor硬體上限、owner／baud／descriptor／
  commit byte strobe、760-byte deterministic stuffing容量、RT-layer `ABORT_ON_ERROR`，以及
  abort後protocol／UART datapath的同步flush與RS-485 DE解除。
- HX5單手回歸送入一個完整165-parameter Status Packet，payload刻意包含`FF FF FD`；UART、
  de-stuff、CRC、ID 110、RT scatter、最後一個parameter及atomic feedback commit均通過。
- SoC預設固定HX5 RT sequencer另以27項單元檢查驗證兩筆transaction、profile設定、bank
  commit、feedback寫入與stale-command阻擋。其合成路徑不包含descriptor SRAM、walker、
  period counters、budget arithmetic或multi-device scatter。
- DRAM滿載測試因behavioral環境沒有HX5 Status Packet responder，明確設定
  `USE_HX5_RT_SEQUENCER=0`執行單筆無回傳交易；固定HX5兩筆transaction由前述27項專用
  回歸驗證，兩個結果不可混為同一種profile。

## Remaining work

下列項目無法由目前已凍結的SoC Core介面與Behavioral model自行關閉：

- FreeRTOS 11.3基準application已接入整機模擬，兩個task會經machine-timer tick反覆切換，
  並以不同`f8`值驗證浮點context保存／恢復。尚未接入的是正式1 kHz trajectory task、
  Protocol/CNN driver task與U-mode system-call port；仍需量測正式控制task的worst-case
  execution time與stack high-watermark。
- `board_top_xilinx`：實際FPGA型號、Clock Wizard、MIG、PHY/MAC、QSPI STARTUPE、pin與XDC，
  以及post-synthesis／post-route timing、BRAM/URAM/DSP用量。
- Ethernet/IP/UDP parser與frame assembler：文件中的packet ABI仍是草案，必須先固定endianness、
  header、fragment、CRC coverage、drop policy及MAC提供的是L2 frame或UDP payload。
- 真實INT8 CNN：模型graph、tensor shape、quantization scale/zero-point、class ABI、MAC/SRAM預算
  尚未固定；目前DMA shell與fixed-latency stub已驗證完整command/result/error介面。
- HX5數位profile已完成官方80-byte全手寫入、165-byte全手回授、可選4/4.5/6 Mbps、
  軟體可設hand ID（右手預設110）與256-byte command/feedback bank；實機仍需確認控制器
  已燒錄相同的雙層Indirect Address mapping、外部Bus baud、碰撞安全、Bus Watchdog及
  RS-485電氣／BER。Generic Protocol RTL的20-device測試保留作壓力回歸，不代表HX5
  外部匯流排拓撲。
- MIG上的最佳burst/outstanding數、single-cycle TCM fast path與ITCM runtime loader屬於目標FPGA
  timing/resource及boot-flow取捨；目前16-beat雙通道DMA與BRAM-init boot是功能正確的baseline，
  並已在隨機backpressure、同時S2MM/MM2S與滿載deadline下驗證。
- Host UART目前已完成可由firmware輸出class/status的硬體與MMIO路徑；正式telemetry文字或binary
  message格式需先固定軟體ABI，USB-UART實體pin則屬於board wrapper。
