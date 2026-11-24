import AppKit
import AuthenticationServices
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
    private let transport: any UsageTransport
    private let webAuth: any SignInPresenter
    init(provider: Provider, transport: any UsageTransport = NetworkTransport(),
         presenter: any SignInPresenter = WebAuthenticationPresenter(), completion: @escaping (Credential) -> Void) {
        self.provider = provider; self.transport = transport; self.webAuth = presenter; self.completion = completion
    }
    func close() {
        generation = UUID(); operation?.cancel(); timeout?.cancel(); server?.stop(); server = nil; webAuth.dismiss(); isRunning = false
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
                let redirect = switch provider {
                case .claude: "http://localhost:\(port)/callback"
                case .antigravity: "http://127.0.0.1:\(port)/oauth2callback"
                default: "http://127.0.0.1:\(port)/auth/callback"
                }
                let attempt = try OAuthAttempt(provider: provider, redirectURI: URL(string: redirect)!)
                activeServer.attempt = attempt
                let started = webAuth.start(url: attempt.authorizationURL) { [weak self] in
                    // The person closed the sign-in sheet before the redirect arrived.
                    guard let self, self.generation == expectedGeneration, self.isRunning else { return }
                    self.close(); self.error = "The sign-in window closed before sign-in finished. Start again."
                }
                guard started else { throw MonitorError.message("Could not open the sign-in window. Try again.") }
                status = "Finish signing in in the sign-in window. QuotaBar for AI will receive the result automatically."
                let code = try await activeServer.waitForCode()
                webAuth.dismiss()
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

@MainActor protocol SignInPresenter: AnyObject {
    /// Shows the sign-in page. `onUserCancel` runs if the session ends (closed or failed) before the redirect arrives.
    func start(url: URL, onUserCancel: @escaping @MainActor () -> Void) -> Bool
    func dismiss()
}

/// Shows the provider's sign-in page in an `ASWebAuthenticationSession`.
/// The providers' OAuth clients only accept loopback redirects, so the code still
/// arrives at `OAuthCallbackServer`; the session is dismissed once it does.
@MainActor final class WebAuthenticationPresenter: NSObject, SignInPresenter, ASWebAuthenticationPresentationContextProviding {
    private var session: ASWebAuthenticationSession?
    func start(url: URL, onUserCancel: @escaping @MainActor () -> Void) -> Bool {
        dismiss()
        // The scheme never matches: completion only fires when the session ends without our redirect.
        let finished: @Sendable (URL?, (any Error)?) -> Void = { [weak self] _, _ in
            Task { @MainActor in
                // `dismiss()` clears `session` first, so this only runs when the session ended on its own.
                guard let self, self.session != nil else { return }
                self.session = nil
                onUserCancel()
            }
        }
        let session = ASWebAuthenticationSession(url: url, callbackURLScheme: "quotabar-oauth", completionHandler: finished)
        session.presentationContextProvider = self
        session.prefersEphemeralWebBrowserSession = false
        self.session = session
        guard session.start() else { self.session = nil; return false }
        return true
    }
    func dismiss() {
        guard let session else { return }
        self.session = nil
        session.cancel()
    }
    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated { NSApp.keyWindow ?? NSApp.windows.first { $0.isVisible } ?? ASPresentationAnchor() }
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
