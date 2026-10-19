import Foundation
public protocol UsageTransport: Sendable {
    func get(_ request: URLRequest) async throws -> Data
}
// Credentials must never follow an HTTP redirect to another host.
private final class NoRedirects: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
public final class NetworkTransport: UsageTransport, Sendable {
    private let session: URLSession
    public init() {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil; config.urlCache = nil
        config.timeoutIntervalForRequest = 25
        config.waitsForConnectivity = true
        config.timeoutIntervalForResource = 60
        session = URLSession(configuration: config, delegate: NoRedirects(), delegateQueue: nil)
    }
    public func get(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw MonitorError.invalidPayload }
        switch http.statusCode {
        case 200..<300: return data
        case 401: throw MonitorError.message("Sign-in expired. Reconnect this account.")
        case 403: throw MonitorError.message("Access denied. Reconnect or check this account's permissions.")
        case 429: throw HTTPRateLimitError(retryAt: HTTPRateLimitError.retryDate(http.value(forHTTPHeaderField: "Retry-After")))
        default: throw MonitorError.message("The provider returned HTTP \(http.statusCode). Try again later.")
        }
    }
}
public struct UsageClient: Sendable {
    let transport: any UsageTransport
    private let claudeThrottle: ClaudeUsageThrottle?
    public init() { transport = NetworkTransport(); claudeThrottle = .shared }
    public init(transport: any UsageTransport, claudeThrottle: ClaudeUsageThrottle? = nil) {
        self.transport = transport; self.claudeThrottle = claudeThrottle
    }
    private func get(_ url: String, credential: Credential, provider: Provider, scope: Bool = true, accountID: UUID? = nil) async throws -> Data {
        var request = URLRequest(url: URL(string: url)!)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("AI-Monitor/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue(credential.kind == .bearer ? "Bearer \(credential.secret)" : credential.secret,
                         forHTTPHeaderField: credential.kind == .bearer ? "Authorization" : "Cookie")
        if provider == .claude, credential.kind == .bearer { request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta") }
        if scope, let id = credential.scope {
            if provider == .codex { request.setValue(id, forHTTPHeaderField: "ChatGPT-Account-Id") }
            if provider == .opencode { request.setValue(id, forHTTPHeaderField: "x-org-id") }
        }
        if provider == .claude, request.url?.path.hasSuffix("/usage") == true, let claudeThrottle {
            return try await claudeThrottle.get(request, using: transport, accountID: accountID)
        }
        return try await transport.get(request)
    }
    public func workspaces(provider: Provider, credential: Credential) async throws -> [Workspace] {
        guard credential.kind == .cookie, provider != .codex else { return [] }
        let url = provider == .claude ? "https://claude.ai/api/organizations" : "https://opencode.ai/console/api/orgs"
        let data = try await get(url, credential: credential, provider: provider, scope: false)
        guard let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { throw MonitorError.invalidPayload }
        return rows.compactMap { row in
            guard let id = row[provider == .claude ? "uuid" : "id"] as? String else { return nil }
            return Workspace(id: id, name: row["name"] as? String ?? id)
        }
    }
    public func fetch(provider: Provider, credential: Credential, accountID: UUID? = nil) async throws -> UsageSnapshot {
        switch provider {
        case .claude:
            let url: String
            if credential.kind == .cookie {
                guard let id = credential.scope, id.range(of: "^[A-Za-z0-9_-]+$", options: .regularExpression) != nil else { throw MonitorError.message("Select a Claude organization first.") }
                url = "https://claude.ai/api/organizations/\(id)/usage"
            } else { url = "https://api.anthropic.com/api/oauth/usage" }
            return try UsageParser.parse(await get(url, credential: credential, provider: provider, accountID: accountID), provider: provider)
        case .codex:
            var result = try UsageParser.parse(await get("https://chatgpt.com/backend-api/wham/usage", credential: credential, provider: provider), provider: provider)
            do {
                result.resets = try UsageParser.resets(await get("https://chatgpt.com/backend-api/wham/rate-limit-reset-credits", credential: credential, provider: provider))
            } catch { result.note = "Banked resets unavailable. \(error.localizedDescription)" }
            return result
        case .opencode:
            if credential.kind == .bearer {
                return try UsageParser.parse(await get("https://opencode.ai/zen/go/v1/usage", credential: credential, provider: provider), provider: provider)
            }
            guard credential.scope?.isEmpty == false else { throw MonitorError.message("Select an OpenCode workspace first.") }
            let base = "https://opencode.ai/console/api/"
            let data = try await get(base + "go/status", credential: credential, provider: provider)
            if let result = try? UsageParser.console(data) { return result }
            // Only a confirmed absence of Go can be treated as pay-as-you-go.
            let raw = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
            guard raw is NSNull || (raw as? [String: Any])?["access"] is NSNull else { throw MonitorError.invalidPayload }
            let org = try UsageParser.object(await get(base + "orgs/current", credential: credential, provider: provider))
            guard org["hasGoSubscription"] as? Bool == false else { throw MonitorError.invalidPayload }
            let billing = try UsageParser.object(await get(base + "billing/status", credential: credential, provider: provider))
            guard billing["mode"] as? String == "pay-as-you-go" else { throw MonitorError.message("This OpenCode billing plan is not supported yet.") }
            let summary = try UsageParser.object(await get(base + "usage/summary?range=30d", credential: credential, provider: provider))
            guard let spend = UsageParser.number(summary["totalCostMicroCents"]) else { throw MonitorError.invalidPayload }
            var result = UsageSnapshot(plan: "Zen · Pay as you go", windows: [], balance: UsageParser.number(billing["balanceMicroCents"]).map { $0 / 100_000_000 })
            result.note = String(format: "$%.2f spent in the last 30 days. No subscription quota reported.", spend / 100_000_000)
            return result
        }
    }
}
