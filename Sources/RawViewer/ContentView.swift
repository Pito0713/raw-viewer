import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Bindable var model: ViewerModel
    @State private var showHelp = false
    @State private var keyMonitor: Any?

    var body: some View {
        VStack(spacing: 0) {
            if model.photos.isEmpty {
                emptyState
            } else {
                ImageCanvas(model: model)
                if model.mode == .compare { compareBar }
                ThumbnailStrip(model: model)
            }
        }
        .frame(minWidth: 800, minHeight: 560)
        .navigationTitle(model.folder?.lastPathComponent ?? "RAW Viewer")
        .toolbar {
            ToolbarItemGroup {
                Button { model.showOpenPanel() } label: { Label("開啟資料夾", systemImage: "folder") }
                Button { model.toggleCompare() } label: {
                    Label(model.mode == .compare ? "結束比對" : "疊圖比對", systemImage: "square.on.square")
                }
                .disabled(model.photos.count < 2)
                Button { showHelp.toggle() } label: { Label("快捷鍵", systemImage: "keyboard") }
                    .popover(isPresented: $showHelp) { ShortcutHelp() }
            }
        }
        .onDrop(of: [.fileURL], isTargeted: nil, perform: handleDrop)
        .alert("無法開啟", isPresented: .constant(model.errorMessage != nil && !model.photos.isEmpty)) {
            Button("好") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
        .onAppear(perform: installKeyMonitor)
        .onDisappear { keyMonitor.map(NSEvent.removeMonitor) }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "photo.on.rectangle.angled").font(.system(size: 56)).foregroundStyle(.secondary)
            Text("開啟含有 Sony ARW 的資料夾").font(.title2)
            Text("按 ⌘O，或把資料夾拖進視窗").foregroundStyle(.secondary)
            if let message = model.errorMessage { Text(message).foregroundStyle(.red) }
            Button("開啟資料夾…") { model.showOpenPanel() }.controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var compareBar: some View {
        HStack(spacing: 14) {
            Text("A").bold().foregroundStyle(.orange)
            Text(model.photoA?.name ?? "-").lineLimit(1).truncationMode(.middle).frame(maxWidth: 220, alignment: .leading)
            Slider(value: $model.opacity, in: 0...1) {
                Text("A 不透明度")
            }
            .frame(maxWidth: 360)
            Text(String(format: "%3.0f%%", model.opacity * 100)).monospacedDigit().frame(width: 44)
            Text("B").bold().foregroundStyle(.cyan)
            Text(model.photoB?.name ?? "-").lineLimit(1).truncationMode(.middle).frame(maxWidth: 220, alignment: .leading)
            Spacer()
            Button("交換 A/B") { model.swapAB() }
            Button("重設 A 位置") { model.resetAOffset() }.disabled(model.aOffset == .zero)
            Button("符合視窗") { model.resetView() }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            guard let url else { return }
            let folder = url.hasDirectoryPath ? url : url.deletingLastPathComponent()
            Task { @MainActor in model.open(folder: folder) }
        }
        return true
    }

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handleKey(event) ? nil : event
        }
    }

    /// 回傳 true 表示已處理（不再傳給系統）。
    private func handleKey(_ event: NSEvent) -> Bool {
        let blocked: NSEvent.ModifierFlags = [.command, .control, .option]
        guard event.modifierFlags.intersection(blocked).isEmpty,
            !(event.window?.firstResponder is NSText),
            !model.photos.isEmpty
        else { return false }

        switch event.keyCode {
        case 123: model.step(-1); return true  // ←
        case 124: model.step(1); return true  // →
        default: break
        }

        guard let key = event.charactersIgnoringModifiers?.lowercased() else { return false }
        switch key {
        case "a": model.setA(model.current)
        case "b": model.setB(model.current)
        case "c": model.toggleCompare()
        case "s": model.swapAB()
        case "f": model.resetView()
        case "z": model.toggleActualSize()
        case "r": model.resetAOffset()
        case "[": model.nudgeOpacity(-0.05)
        case "]": model.nudgeOpacity(0.05)
        case "0": model.setOpacityStep(10)
        case "1"..."9": model.setOpacityStep(Int(key)!)
        default: return false
        }
        return true
    }
}

private struct ShortcutHelp: View {
    private let rows: [(String, String)] = [
        ("← / →", "上一張／下一張（比對時 A、B 一起移動）"),
        ("A / B", "把目前這張設為 A／B"),
        ("C", "進入／離開疊圖比對"),
        ("S", "交換 A、B"),
        ("1–9, 0", "A 不透明度 10%–100%"),
        ("[ / ]", "不透明度 −5% / +5%"),
        ("拖曳 / 觸控板雙指", "平移"),
        ("Shift＋拖曳", "只移動 A"),
        ("R", "重設 A 位置"),
        ("滾輪 / 雙指捏合", "縮放"),
        ("Z", "100% ↔ 符合視窗"),
        ("F / 雙擊", "符合視窗"),
        ("縮圖：點 / ⌥點", "比對時設為 A / B"),
    ]

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
            ForEach(rows, id: \.0) { key, action in
                GridRow {
                    Text(key).bold().monospaced()
                    Text(action)
                }
            }
        }
        .padding(16)
    }
}
