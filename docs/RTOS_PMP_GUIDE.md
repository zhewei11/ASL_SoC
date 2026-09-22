# RTOS U-mode／PMP 使用指南

本CPU現在支援Machine mode、User mode及8個標準PMP entry。設計目的不是加入Linux所需的
MMU／Supervisor mode，而是讓小型RTOS kernel與ISR留在M-mode，將不可信或較低關鍵度的task
放在U-mode。既有只跑M-mode的bare-metal與RTOS映像不需設定PMP，行為維持不變。

## 硬體功能

- `mret`依`mstatus.MPP`切換至M或U；trap時硬體保存原privilege至MPP並返回M-mode。
- `misa.U=1`，目前值為`0x40101120`。
- 8個PMP entry：`pmpcfg0/1`與`pmpaddr0..7`，支援OFF、TOR、NA4、NAPOT及lock。
- U-mode未命中任何PMP entry時預設拒絕；M-mode未命中時預設允許。
- 取指、load、store違規分別產生`mcause=1/5/7`，`mtval`保存失敗位址。
- U-mode存取Machine CSR或執行`mret`／`wfi`會產生illegal-instruction trap。
- `mcounteren.CY/TM/IR`控制U-mode能否讀`cycle/time/instret`。
- `mstatus.MPRV`讓M-mode kernel的load/store暫時套用`MPP`權限，適合在system call中
  複製或檢查task buffer；它不影響instruction fetch，`mret`返回U-mode時會自動清除。
- 被PMP拒絕的取指不會啟動新的I-cache refill；被拒絕的load/store不會進入data bus。

PMP config byte為`L | 00 | A[1:0] | X | W | R`。硬體依規格使用最低編號的匹配entry；
一筆存取若跨出該entry邊界，即使相鄰entry也允許，仍會拒絕。locked TOR entry也會鎖住
前一個`pmpaddr`，直到reset才能修改。

## RTOS啟動順序

kernel啟動與中斷handler仍在M-mode，建議依下列順序建立第一個受保護task：

1. 在M-mode設定task code、data、stack與允許使用的MMIO區域。entry數只有8個，優先使用TOR
   合併連續區域；不要把整個SoC MMIO頁開給U-mode。
2. 設定`mtvec`、kernel stack及必要的`mcounteren`。
3. 將task入口寫入`mepc`，把`mstatus.MPP`清成U，然後執行`mret`。
4. U-mode task以`ecall`要求kernel服務；handler由`mcause=8`辨識U-mode syscall。
5. context switch除通用暫存器與`mepc/mstatus`外，也要保存每個task的PMP設定。若多個task
   使用FPU，仍需保存`f0..f31`與`fcsr`，或依`mstatus.FS`實作lazy save。

以下為一個最小的PMP配置概念。實際位址應由linker配置產生，避免手寫常數：

```asm
    # entry 0: TOR [0, 0x10000), read + execute
    li      t0, (0x10000 >> 2)
    csrw    pmpaddr0, t0
    li      t0, 0x0d              # A=TOR, X=1, R=1
    csrw    pmpcfg0, t0

    # enter task at task_entry in U-mode
    la      t0, task_entry
    csrw    mepc, t0
    li      t0, (3 << 11)
    csrc    mstatus, t0            # MPP=U
    mret
```

## 驗證

```sh
make build/pmp_csr build/core_pmp_user
vvp build/pmp_csr
vvp build/core_pmp_user
make freertos-test
```

這兩個測試也已納入`make test`。`pmp_csr_tb.sv`驗證PMP編碼與例外語意；
`core_pmp_user_tb.sv`由真實pipeline設定PMP、執行`mret`，再確認U-mode instruction-fetch與
store fault都被精確攔截。`freertos-test`會建置相鄰`rtos_core/freertos_demo`中的FreeRTOS
11.3映像，將Boot ROM、ITCM、DTCM三段載入本SoC，驗證兩個task、machine timer tick及
浮點context switch。這是M-mode FreeRTOS基準；受PMP保護的U-mode task仍需搭配system-call
入口與每task PMP context，不能直接把標準FreeRTOS port的task降權。

本SoC的ITCM與DTCM是Harvard資料路徑，load/store無法讀ITCM。因此整合建置使用
`fw/freertos_soc.ld`，將`.text`放入ITCM，但把`.rodata`、jump table與一般data放入DTCM；
新增C/C++程式碼時必須維持這項配置。
