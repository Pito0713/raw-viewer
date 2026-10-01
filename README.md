# RAW Viewer

免費、開源的 macOS RAW 快速瀏覽器，可以把兩張照片**半透明疊在一起**比對差異。

> 🚧 早期開發中（v0.1 MVP）。目前只支援 Sony ARW。詳見 [計劃書](docs/PLAN.md)。

## 功能

- 開啟資料夾快速瀏覽 Sony ARW，方向鍵切換上一張／下一張
- 直接讀 ARW 內嵌預覽，切換幾乎不用等；停下來後在背景解完整 RAW
- **疊圖比對**：自選 A、B 兩張，A 以可調不透明度疊在 B 上
- 兩張同步縮放、平移；Shift＋拖曳可單獨移動 A，構圖不同也能對到想比的位置
- 顯示快門、光圈、ISO、焦距

## 系統需求

- macOS 14 Sonoma 以上
- 完整解析度解碼使用 macOS 內建 RAW 支援，可支援的 Sony 機型以 Apple「macOS 支援的數位相機 RAW 格式」清單為準；預覽不受此限制

## 建置與執行

需要 Xcode 15 以上（或 Swift 5.10 工具鏈）。

```bash
scripts/build-app.sh            # 建置 build/RawViewer.app（release）
open build/RawViewer.app

# 開發時直接開某個資料夾
build/RawViewer.app/Contents/MacOS/RawViewer -openFolder /path/to/arw
```

測試：

```bash
swift test
# 加上真實 ARW 樣本（不放進 repo，可從 https://raw.pixls.us/data/Sony/ 下載）
RAW_VIEWER_SAMPLES=/path/to/arw swift test
```

## 快捷鍵

| 按鍵 | 動作 |
|---|---|
| ← / → | 上一張／下一張（比對時 A、B 一起移動） |
| A / B | 把目前這張設為 A／B |
| C | 進入／離開疊圖比對 |
| S | 交換 A、B |
| 1–9, 0 | A 不透明度 10%–100% |
| [ / ] | 不透明度 −5% / +5% |
| 拖曳 / 觸控板雙指滑動 | 平移 |
| Shift＋拖曳 | 只移動 A |
| R | 重設 A 位置 |
| 滾輪 / 雙指捏合 | 縮放 |
| Z | 100% ↔ 符合視窗 |
| F / 雙擊 | 符合視窗 |
| 縮圖：點 / ⌥點 | 比對時設為 A / B（右鍵選單也可以） |

## 授權

[MIT](LICENSE)
