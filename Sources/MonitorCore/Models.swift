import Foundation

public enum Provider: String, Codable, CaseIterable, Sendable {
    case claude, codex, opencode, antigravity
    /// Antigravity needs a client secret supplied at build time.
    public var isAvailable: Bool { self != .antigravity || OAuthAttempt.antigravityClientSecret != nil }
    public var title: String { switch self { case .claude: "Claude"; case .codex: "Codex"; case .opencode: "OpenCode"; case .antigravity: "Antigravity" } }
}
public struct QuotaWindow: Identifiable, Codable, Sendable {
    public var id: String { label }
    public let label: String
    public let used: Double
    public let resetsAt: Date?
    public var remaining: Double { max(0, 100 - used) }
    public init(_ label: String, used: Double, resetsAt: Date? = nil) {
        self.label = label; self.used = used; self.resetsAt = resetsAt
    }
}
public struct ResetCredits: Codable, Sendable {
    public let available: Int
    public let expirations: [Date]
}
public struct ExtraUsage: Codable, Equatable, Sendable {
    public let used: Double?
    public let limit: Double?
    public let utilization: Double?
    public let currency: String?
    public let resetsAt: Date?
    public init(used: Double? = nil, limit: Double? = nil, utilization: Double? = nil, currency: String? = nil, resetsAt: Date? = nil) {
        self.used = used; self.limit = limit; self.utilization = utilization; self.currency = currency; self.resetsAt = resetsAt
    }
    public var percentUsed: Double? {
        if let utilization { return utilization }
        if let used, let limit, limit > 0 { return used / limit * 100 }
        return nil
    }
    public var percentRemaining: Double? { percentUsed.map { max(0, 100 - $0) } }
}
public struct UsageSnapshot: Codable, Sendable {
    public var plan: String
    public var windows: [QuotaWindow]
    public var resets: ResetCredits?
    public var extraUsage: ExtraUsage?
    public var note: String?
    public var balance: Double?
    public var fetchedAt = Date()
    public init(plan: String, windows: [QuotaWindow], balance: Double? = nil, extraUsage: ExtraUsage? = nil) {
        self.plan = plan; self.windows = windows; self.balance = balance; self.extraUsage = extraUsage
    }
}
public enum MonitorError: LocalizedError {
    case invalidPayload, message(String), authenticationRequired(String)
    public var errorDescription: String? {
        switch self { case .invalidPayload: "The provider returned an unrecognized usage response."; case .message(let text), .authenticationRequired(let text): text }
    }
}
