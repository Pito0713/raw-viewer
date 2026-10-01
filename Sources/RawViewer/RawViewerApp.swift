import AppKit
import SwiftUI

@main
struct RawViewerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = ViewerModel()

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
                .onAppear(perform: openFolderFromArguments)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("開啟資料夾…") { model.showOpenPanel() }
                    .keyboardShortcut("o")
            }
        }
    }

    /// 開發用：`RawViewer -openFolder /path/to/folder` 直接開啟資料夾。
    /// 不能直接傳路徑當參數——AppKit 會把它當成「開啟檔案」，SwiftUI 就不建立主視窗。
    private func openFolderFromArguments() {
        guard model.folder == nil, let path = UserDefaults.standard.string(forKey: "openFolder") else { return }
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue {
            model.open(folder: URL(fileURLWithPath: path))
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // 以 swift run 執行時沒有 .app bundle，需要手動成為一般前景 App。
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
