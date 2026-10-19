import SwiftUI
import AppKit

@MainActor final class ApplicationDelegate: NSObject, NSApplicationDelegate {
    let store: AccountStore
    override init() {
        IdentityMigration.prepare()
        store = AccountStore()
        super.init()
    }
    private var statusBar: StatusBarController?
    func applicationWillTerminate(_ notification: Notification) { statusBar?.shutdown() }
    func applicationDidFinishLaunching(_ notification: Notification) {
        if CommandLine.arguments.contains("--demo") { store.showDemo() }
        statusBar = StatusBarController(store: store)
    }
}

@main struct AIMonitorApp: App {
    @NSApplicationDelegateAdaptor(ApplicationDelegate.self) private var delegate
    init() {
        let arguments = CommandLine.arguments
        if let index = arguments.firstIndex(of: "--render-preview"), arguments.count > index + 1 {
            _ = NSApplication.shared
            let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("accounts.json")
            let store = AccountStore(file: file)
            store.showDemo()
            do { try PreviewRenderer.write(to: arguments[index + 1], store: store); exit(0) }
            catch { fputs("Preview rendering failed\n", stderr); exit(1) }
        }
    }
    var body: some Scene {
        // The status controller owns the single Settings window.
        Settings { EmptyView() }
    }
}
