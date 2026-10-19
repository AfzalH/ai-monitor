import AppKit
import SwiftUI
import MonitorCore

@MainActor final class BrowserLogin: ObservableObject {
    @Published private(set) var status = "Preparing secure sign-in…"
    @Published private(set) var error: String?
    @Published private(set) var isRunning = false
    let provider: Provider
    private var operation: Task<Void, Never>?
    private var timeout: Task<Void, Never>?
    private var server: OAuthCallbackServer?
    private var generation = UUID()
    private let completion: (Credential) -> Void
    private let openBrowser: (URL) -> Bool
    private let transport: any UsageTransport
    init(provider: Provider, transport: any UsageTransport = NetworkTransport(),
         openBrowser: @escaping (URL) -> Bool = { NSWorkspace.shared.open($0) }, completion: @escaping (Credential) -> Void) {
        self.provider = provider; self.transport = transport; self.openBrowser = openBrowser; self.completion = completion
    }
    func close() {
        generation = UUID(); operation?.cancel(); timeout?.cancel(); server?.stop(); server = nil; isRunning = false
    }
    func show() {
        close(); error = nil; isRunning = true; status = "Preparing secure sign-in…"
        let expectedGeneration = generation
        timeout = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(600))
                guard let self, self.generation == expectedGeneration else { return }
                self.close(); self.error = "Sign-in timed out. Start again to open a fresh browser request."
            } catch {}
        }
        operation = Task { [weak self] in
            guard let self else { return }
            do {
                guard provider != .opencode else { throw MonitorError.message("Open the OpenCode console and paste a Go API key.") }
                let callback = OAuthCallbackServer()
                server = callback
                let port: UInt16
                if provider == .codex {
                    do { port = try await callback.start(port: 1455) }
                    catch {
                        try Task.checkCancellation()
                        let fallback = OAuthCallbackServer(); server = fallback
                        port = try await fallback.start(port: 1457)
                    }
                } else { port = try await callback.start() }
                try Task.checkCancellation()
                guard generation == expectedGeneration, let activeServer = server else { return }
                let redirect = provider == .claude ? "http://localhost:\(port)/callback" : "http://127.0.0.1:\(port)/auth/callback"
                let attempt = try OAuthAttempt(provider: provider, redirectURI: URL(string: redirect)!)
                activeServer.attempt = attempt
                guard openBrowser(attempt.authorizationURL) else { throw MonitorError.message("Could not open your default browser. Check your macOS browser setting and try again.") }
                status = "Finish signing in in your browser. QuotaBar for AI will receive the result automatically."
                let code = try await activeServer.waitForCode()
                try Task.checkCancellation()
                status = "Completing sign-in…"
                let data = try await transport.get(attempt.tokenRequest(code: code))
                try Task.checkCancellation()
                guard generation == expectedGeneration else { return }
                let credential = try attempt.credential(from: data)
                activeServer.stop(); server = nil; timeout?.cancel(); isRunning = false
                status = "Sign-in received."
                completion(credential)
                NSApp?.activate(ignoringOtherApps: true)
            } catch {
                guard generation == expectedGeneration else { return }
                server?.stop(); server = nil; timeout?.cancel(); isRunning = false
                if !(error is CancellationError) { self.error = error.localizedDescription }
            }
        }
    }
}

struct BrowserLoginStatus: View {
    @ObservedObject var login: BrowserLogin
    var body: some View {
        if let error = login.error {
            Label(error, systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
        } else {
            HStack(alignment: .top, spacing: 8) {
                if login.isRunning { ProgressView().controlSize(.small) }
                Text(login.status).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
