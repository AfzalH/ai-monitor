import AppKit
import SwiftUI
import Combine

/// Explicit status-item placement avoids MenuBarExtra's fixed edge alignment.
@MainActor final class StatusBarController: NSObject {
    private let store: AccountStore
    private let item: NSStatusItem
    private var panel: QuotaPanel?
    private var settingsWindow: NSWindow?
    private var subscription: AnyCancellable?
    private var menuMonitor: MenuBarRefreshScheduler?
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var dismissalObservers: [NSObjectProtocol] = []
    private var screen: NSScreen?

    init(store: AccountStore) {
        self.store = store
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        if let button = item.button {
            button.image = MenuBarIcon.gauge
            button.imagePosition = .imageLeading
            button.target = self
            button.action = #selector(toggle)
            button.setAccessibilityLabel("QuotaBar for AI")
        }
        updateTitle()
        menuMonitor = MenuBarRefreshScheduler(store: store)
        subscription = store.objectWillChange.sink { [weak self] _ in
            Task { @MainActor in self?.updateTitle() }
        }
    }
    private func updateTitle() {
        item.button?.title = store.menuLabel.isEmpty ? "" : " " + store.menuLabel
        if let panel, panel.isVisible {
            item.button?.window?.contentView?.layoutSubtreeIfNeeded()
            position(panel, height: panel.frame.height)
        }
    }

    @objc func toggle() {
        if panel != nil { close(); return }
        guard let button = item.button, let window = button.window else { return }
        screen = window.screen ?? NSScreen.main
        guard let screen else { return }
        let panel = QuotaPanel(contentRect: NSRect(x: 0, y: 0, width: 520, height: 240),
                               styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.hasShadow = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.collectionBehavior = [.transient, .fullScreenAuxiliary, .moveToActiveSpace]
        self.panel = panel
        let dashboard = DashboardView(screenHeight: screen.visibleFrame.height,
                                      settingsAction: { [weak self] in self?.openSettings() },
                                      heightChanged: { [weak self, weak panel] height in
            Task { @MainActor in
                guard let self, let panel, self.panel === panel else { return }
                self.position(panel, height: height)
                if !panel.isVisible {
                    panel.makeKeyAndOrderFront(nil)
                    self.installDismissal()
                    Task { await self.store.refresh(onOpen: true) }
                }
            }
        }).environmentObject(store)
        let hosting = NSHostingView(rootView: dashboard)
        hosting.sizingOptions = []
        hosting.wantsLayer = true
        hosting.layer?.cornerRadius = 12
        hosting.layer?.masksToBounds = true
        panel.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        // The first measured content height opens the panel, avoiding a flash
        // at maximum height before a short list has been laid out.
    }
    private func position(_ panel: NSPanel, height: CGFloat) {
        guard let button = item.button, let window = button.window,
              let screen = window.screen ?? screen else { return }
        let anchor = window.convertToScreen(button.convert(button.bounds, to: nil))
        let bounds = screen.visibleFrame
        let size = NSSize(width: min(520, bounds.width), height: min(height, bounds.height))
        let frame = PopoutPlacement.frame(size: size, anchor: anchor, screen: bounds)
        panel.setFrame(frame, display: true)
    }
    private func installDismissal() {
        dismissalObservers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        })
        dismissalObservers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        })
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] event in
            guard let self else { return event }
            if event.type == .keyDown {
                if event.keyCode == 53 { self.close(); return nil }
            } else if event.window !== self.panel && event.window !== self.item.button?.window {
                self.close()
            }
            return event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in self?.close() }
    }
    private func close() {
        for observer in dismissalObservers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            NotificationCenter.default.removeObserver(observer)
        }
        dismissalObservers.removeAll()
        if let localMonitor { NSEvent.removeMonitor(localMonitor); self.localMonitor = nil }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor); self.globalMonitor = nil }
        panel?.orderOut(nil)
        panel = nil
    }
    func shutdown() {
        close()
        settingsWindow?.close()
        subscription = nil
        menuMonitor?.stop()
        menuMonitor = nil
        NSStatusBar.system.removeStatusItem(item)
    }
    private func openSettings() {
        close()
        if settingsWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 650, height: 690),
                                  styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            window.title = "QuotaBar for AI Settings"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: SettingsView().environmentObject(store))
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}

private final class QuotaPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

enum PopoutPlacement {
    static func frame(size: NSSize, anchor: NSRect, screen: NSRect) -> NSRect {
        let x = max(screen.minX, min(anchor.midX - size.width / 2, screen.maxX - size.width))
        let top = min(screen.maxY, anchor.minY)
        return NSRect(x: x, y: max(screen.minY, top - size.height), width: size.width, height: size.height)
    }
}
