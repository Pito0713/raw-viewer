import AppKit
import Observation
import RawViewerCore
import SwiftUI

enum ViewerMode {
    case browse, compare
}

@MainActor
@Observable
final class ViewerModel {
    private(set) var folder: URL?
    private(set) var photos: [PhotoFile] = []
    private(set) var current = 0
    private(set) var mode: ViewerMode = .browse
    private(set) var aIndex: Int?
    private(set) var bIndex: Int?
    var errorMessage: String?

    /// A 疊在 B 上的不透明度（0...1）。
    var opacity = 0.5

    // 視圖變換：先以「符合視窗」大小置中，再縮放 zoom、平移 pan（螢幕點）。
    private(set) var zoom: CGFloat = 1
    private(set) var pan: CGSize = .zero
    /// A 相對 B 的位移（未縮放前的座標），讓構圖不同的兩張也能手動對到想比的位置。
    private(set) var aOffset: CGSize = .zero
    var canvasSize: CGSize = .zero

    let store = ImageStore()
    @ObservationIgnored private var fullResolutionTask: Task<Void, Never>?

    static let zoomRange: ClosedRange<CGFloat> = 1...64

    // MARK: - 資料夾

    func open(folder: URL) {
        do {
            let photos = try PhotoScanner.scan(folder: folder)
            store.reset()
            self.folder = folder
            self.photos = photos
            current = 0
            mode = .browse
            aIndex = nil
            bIndex = nil
            aOffset = .zero
            resetView()
            errorMessage = photos.isEmpty ? "這個資料夾沒有 Sony ARW 檔" : nil
            refreshLoads()
        } catch {
            errorMessage = "無法開啟資料夾：\(error.localizedDescription)"
        }
    }

    func showOpenPanel() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "開啟"
        panel.message = "選擇含有 Sony ARW 檔的資料夾"
        if panel.runModal() == .OK, let url = panel.url {
            open(folder: url)
        }
    }

    // MARK: - 選取與導覽

    var currentPhoto: PhotoFile? { photos.indices.contains(current) ? photos[current] : nil }
    var photoA: PhotoFile? { aIndex.flatMap { photos.indices.contains($0) ? photos[$0] : nil } }
    var photoB: PhotoFile? { bIndex.flatMap { photos.indices.contains($0) ? photos[$0] : nil } }

    /// 瀏覽模式：上一張／下一張。比對模式：A、B 一起往前或往後移，方便連拍逐對比較。
    func step(_ delta: Int) {
        switch mode {
        case .browse:
            select(current + delta)
        case .compare:
            guard let a = aIndex, let b = bIndex,
                photos.indices.contains(a + delta), photos.indices.contains(b + delta)
            else { return }
            aIndex = a + delta
            bIndex = b + delta
            current = a + delta
            refreshLoads()
        }
    }

    func select(_ index: Int) {
        guard photos.indices.contains(index) else { return }
        current = index
        refreshLoads()
    }

    func setA(_ index: Int) {
        guard photos.indices.contains(index) else { return }
        aIndex = index
        current = index
        refreshLoads()
    }

    func setB(_ index: Int) {
        guard photos.indices.contains(index) else { return }
        bIndex = index
        refreshLoads()
    }

    func swapAB() {
        guard mode == .compare else { return }
        (aIndex, bIndex) = (bIndex, aIndex)
        aOffset = CGSize(width: -aOffset.width, height: -aOffset.height)
        if let aIndex { current = aIndex }
    }

    /// 進入比對時，沒選過的話 A = 目前這張、B = 下一張（最後一張則為上一張）。
    func toggleCompare() {
        if mode == .compare {
            mode = .browse
        } else {
            guard photos.count >= 2 else { return }
            if aIndex == nil { aIndex = current }
            if bIndex == nil || bIndex == aIndex {
                bIndex = aIndex! + 1 < photos.count ? aIndex! + 1 : aIndex! - 1
            }
            mode = .compare
        }
        refreshLoads()
    }

    func setOpacityStep(_ step: Int) {
        opacity = Double(step) / 10
    }

    func nudgeOpacity(_ delta: Double) {
        opacity = min(1, max(0, opacity + delta))
    }

    // MARK: - 縮放與平移

    func resetView() {
        zoom = 1
        pan = .zero
    }

    func resetAOffset() {
        aOffset = .zero
    }

    func panBy(_ delta: CGSize) {
        pan.width += delta.width
        pan.height += delta.height
    }

    func moveABy(_ delta: CGSize) {
        guard mode == .compare else { return panBy(delta) }
        aOffset.width += delta.width / zoom
        aOffset.height += delta.height / zoom
    }

    /// 以 anchor（相對畫布中心的點）為中心縮放，讓游標下的內容不動。
    func zoom(by factor: CGFloat, anchor: CGPoint) {
        let newZoom = min(Self.zoomRange.upperBound, max(Self.zoomRange.lowerBound, zoom * factor))
        guard newZoom != zoom else { return }
        let contentX = (anchor.x - pan.width) / zoom
        let contentY = (anchor.y - pan.height) / zoom
        zoom = newZoom
        pan = CGSize(width: anchor.x - newZoom * contentX, height: anchor.y - newZoom * contentY)
        if zoom == 1 { pan = .zero }
    }

    /// 切換「符合視窗」和「100%（1 個影像像素 = 1 個螢幕像素）」。
    func toggleActualSize() {
        guard let url = (mode == .compare ? photoB : currentPhoto)?.url,
            let meta = store.metadata(for: url),
            let width = meta.pixelWidth, let height = meta.pixelHeight,
            canvasSize.width > 0, canvasSize.height > 0
        else { return }
        if zoom > 1 {
            resetView()
            return
        }
        let backingScale = NSScreen.main?.backingScaleFactor ?? 2
        let fitScale = min(canvasSize.width / CGFloat(width), canvasSize.height / CGFloat(height))
        zoom(by: 1 / (fitScale * backingScale), anchor: .zero)
    }

    // MARK: - 載入排程

    var visiblePhotos: [PhotoFile] {
        mode == .compare ? [photoB, photoA].compactMap { $0 } : [currentPhoto].compactMap { $0 }
    }

    /// 立即載入畫面上的預覽並預載前後兩張；停留 250ms 後才解完整 RAW，避免快速翻頁時白做工。
    private func refreshLoads() {
        let visible = visiblePhotos
        visible.forEach { store.requestPreview($0.url) }
        let anchor = mode == .compare ? (bIndex ?? current) : current
        for offset in [1, -1, 2, -2] where photos.indices.contains(anchor + offset) {
            store.requestPreview(photos[anchor + offset].url)
        }

        fullResolutionTask?.cancel()
        fullResolutionTask = Task { [store] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            visible.forEach { store.requestFull($0.url) }
        }
    }
}
