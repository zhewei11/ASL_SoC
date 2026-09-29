# ASL SoC 動作軟體層

這個目錄把辨識結果轉成 HX5-D20 可執行的多階段動作。它不取代既有
Protocol 2.0 RTL；RTOS 只產生每個 1 kHz frame 的 20 軸目標，封包、CRC、
6 Mbps UART/RS-485、雙 command bank 與 feedback 仍由既有硬體處理。

## 為什麼不能直接用「一個字母 = 一組角度」

每個字母都必須以安全的順序移動不同手指，例如先鬆開拇指、形成四指手形、
調整指間距、最後放置拇指；回到 OPEN 時也可能需要不同順序。因此執行單位是：

```text
CNN 結果
  -> 信心值與連續樣本濾波
  -> 字母 Queue
  -> OPEN -> 多個 phase keyframe -> hold -> 多個返回 phase -> OPEN
  -> Q4.12 radian -> 每軸校正 -> HX5 raw position
  -> 現有 Protocol 2.0 command bank
```

目前資料含 24 個靜態字母 `A-I,K-Y`。`J`、`Z` 是動態字母，ABI 已保留 ID，
但在建立專用軌跡並重新完成碰撞審查前，播放器會拒絕它們。

## 目錄

- `include/asl_motion.h`：固定 class ABI、辨識濾波、Queue、播放器與校正 API。
- `src/asl_motion.c`：無 heap、每 tick 固定工作量的 C11 實作。
- `generated/`：從已核准軌跡壓縮出的 phase keyframes 與來源 `plan_id`。
- `ports/asl_soc_hx5_port.*`：接到 `fw/include/hx5_rt_control.h` 的 SoC adapter。
- `ports/asl_soc_cnn_port.*`：一致地讀取 CNN sequence/result，並把 8-bit
  confidence 轉成 Q15。
- `examples/freertos_integration.c`：用 frame-done interrupt 驅動的 FreeRTOS 範本。
- `tools/export_asl_actions.py`：重新驗證 collision report 並產生 C table。

## Class ABI

- `0`：OPEN／no gesture
- `1..26`：依英文字母順序 A..Z
- `255`：無效

CNN 若輸出緊密的 24 類索引 `A-I,K-Y = 0..23`，先呼叫
`asl_source_index_to_class_id()`，不要直接把 CNN index 當成 class ID。

預設濾波需要 4 個連續高信心樣本、3 個 OPEN 樣本解除 latch，並有 250 ms
repeat guard。門檻為約 0.85（Q15 的 27852）；實際值應依模型驗證集與相機
frame rate 調整。每次取得新辨識結果前，以實際經過時間呼叫
`asl_class_filter_advance_time_ms()`；1 kHz timer 也可直接使用其單毫秒 wrapper
`asl_class_filter_tick_1khz()`。低於門檻的連續樣本視為 release；不同字母穩定後
可直接形成下一個事件，同一字母要先出現 release 才能再次觸發，以支援 double
letter 而不連續重複排隊。

## 動作資料與核准邊界

輸入來自：

```text
../../SW/hx5_asl_fingerspelling/generated/trajectory_<letter>.json
../../SW/hx5_asl_fingerspelling/generated/trajectory_<letter>_collision_report.json
```

產生工具只接受：

1. 軌跡與報告的 `plan_id` 完全相同。
2. `approved == true`。
3. `unexpected_collision_sample_count == 0`。
4. 起點與終點都是 OPEN。
5. 具備 `target_hold` phase。

重新產生：

```bash
cd /Users/zhangzhewei/Documents/dexterous_hand/ASL_SoC
python3 software/tools/export_asl_actions.py
```

這裡的「approved」只代表對應 `plan_id` 的 URDF mesh collision 檢查通過。
它不代表實機力矩安全，也不代表 Deaf／ASL 使用者已確認手形可辨識。JSON
更新後必須先重跑來源專案的碰撞檢查，不能只重跑 exporter。

## 端到端模擬測試

```bash
cd /Users/zhangzhewei/Documents/dexterous_hand/ASL_SoC
make -C software test LETTER=A
```

測試會先讓全部 24 個字母走完每個 1 kHz keyframe，核對 phase 終點、總時間、
hold 與最後返回 OPEN；接著以指定 `LETTER` 產生 20 軸 raw position 和完整 HX5
command body，再交給真實 Protocol 2.0 RTL。UART monitor 會在 6 Mbps 檢查：

- RS-485 `DE` 確實拉高。
- Protocol 2.0 header、broadcast ID 和 length。
- 86-byte HX5 indirect Sync Write body 的每一 byte。
- 線上封包 CRC。

測試使用 `center=2048`、`100 counts/rad`、`goal_current=0x0123` 的模擬校正，
用來驗證資料路徑，不可拿來驅動實機。換成實機校正表後，才能確認真實馬達角度。

## RTOS 串接順序

1. 量測並填入 20 軸 `asl_joint_calibration_t`：OPEN center、方向、
   counts/radian、軟體上下限。任何 `valid == 0` 都會阻止輸出。
2. 設定每軸 `goal_current`，先以低力矩完成單軸與 OPEN 姿態驗證。
3. 初始化 `asl_soc_hx5_port_initialize()`；目前硬體設定使用 6 Mbps。
4. 先提交完整 OPEN command bank，確認 feedback 與實際手形都是 OPEN。
5. Protocol frame-done ISR 喚醒最高優先級 motion task。只有 port ready 時才推進
   一個 `asl_action_player_tick_1khz()`，然後提交下一個完整 command bank。
6. CNN task 只送穩定 class 到 Queue，不可直接寫 MMIO，也不可中斷正在執行的
   phase sequence。
7. timeout、feedback error、過流或 E-stop 時停止 RT sequencer／torque；不要從
   任意中間姿態直接跳到 OPEN。故障恢復要先由人工確認，再走獨立 recovery path。

## 校正公式

每軸轉換為：

```text
raw = center_raw + direction * radian * counts_per_radian
```

輸入角度是 signed Q4.12 radians，`counts_per_radian_q16` 是 unsigned Q16.16。
結果會限制在 `minimum_raw..maximum_raw`，但 clamp 不是碰撞保護；上下限仍需由
實際機構與 HX5 文件量測建立，不能照抄範例值。

## 尚未宣稱完成的項目

- J、Z 動態手勢軌跡。
- 20 軸實機校正常數與安全 `goal_current`。
- 量化後 1 kHz replay 的 Gazebo／實機回歸測試。
- 手形的 ASL 使用者辨識驗收，以及需要手腕方向的 G、H、P、Q 等姿態。

上述項目完成前，先以馬達離線或低力矩、可立即斷電的環境驗證，不要直接進入
正式展示或長時間連續運轉。
