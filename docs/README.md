# 文件索引

本目錄只保留與目前RTL、firmware介面或驗證結果直接相關的文件。若文件內容與程式碼不一致，
以下列順序判定：`config/asl_soc_config.json`、RTL／firmware header、測試、文件。

## 團隊協作

- [`TEAM_GIT_TUTORIAL.md`](TEAM_GIT_TUTORIAL.md)：Fork、功能分支、Commit、Push、Pull Request與同步upstream的完整教學。

## 系統架構

- [`ARCHITECTURE.md`](ARCHITECTURE.md)：目前SoC架構、資料流、CPU/RTOS、板級邊界與未完成項目的唯一總覽。

## 記憶體與介面契約

- [`ADDRESS_MAP.md`](ADDRESS_MAP.md)：CPU可見位址與cacheability。
- [`MEMORY_FABRIC.md`](MEMORY_FABRIC.md)：Boot ROM、ITCM、DTCM與外部AXI fabric。
- [`MMIO_REGISTERS.md`](MMIO_REGISTERS.md)：目前SoC MMIO register定義。
- [`AXI_MULTICHANNEL_DMA.md`](AXI_MULTICHANNEL_DMA.md)：Ethernet與CNN共用DMA的通道及ownership規則。

## Protocol 2.0／HX5

- [`HX5_D20_TABLESYNC.md`](HX5_D20_TABLESYNC.md)：HX5-D20固定profile、command／feedback ABI與初始化需求。
- [`DYNAMIXEL_PROTOCOL2_RTL_REPORT.md`](DYNAMIXEL_PROTOCOL2_RTL_REPORT.md)：Protocol 2.0硬體化設計、限制與可主張範圍。

## RTOS與驗證

- [`RTOS_PMP_GUIDE.md`](RTOS_PMP_GUIDE.md)：FreeRTOS啟動、U-mode、PMP與MPRV使用方式。
- [`VERIFICATION_STATUS.md`](VERIFICATION_STATUS.md)：目前通過項目與仍需實機確認的工作。
