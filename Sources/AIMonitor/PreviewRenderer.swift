import SwiftUI
import AppKit

@MainActor enum PreviewRenderer {
    static func write(to path: String, store: AccountStore) throws {
        let content = DashboardView().environmentObject(store).frame(width: 520).environment(\.colorScheme, .light)
        let hosting = NSHostingView(rootView: content)
        let size = hosting.fittingSize
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = hosting
        hosting.frame = NSRect(origin: .zero, size: size)
        hosting.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        hosting.layoutSubtreeIfNeeded()
        guard let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
            throw NSError(domain: "AI Monitor", code: 1)
        }
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else { throw NSError(domain: "AI Monitor", code: 2) }
        try data.write(to: URL(fileURLWithPath: path))
    }
}
