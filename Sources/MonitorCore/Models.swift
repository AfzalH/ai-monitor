import Foundation

public enum Provider: String, Codable, CaseIterable, Sendable {
    case claude, codex, opencode
    public var title: String { switch self { case .claude: "Claude"; case .codex: "Codex"; case .opencode: "OpenCode" } }
}
public struct QuotaWindow: Identifiable, Sendable {
    public var id: String { label }
    public let label: String
    public let used: Double
    public let resetsAt: Date?
    public var remaining: Double { max(0, 100 - used) }
    public init(_ label: String, used: Double, resetsAt: Date? = nil) {
        self.label = label; self.used = used; self.resetsAt = resetsAt
    }
}
public struct ResetCredits: Sendable {
    public let available: Int
    public let expirations: [Date]
}
public struct UsageSnapshot: Sendable {
    public var plan: String
    public var windows: [QuotaWindow]
    public var resets: ResetCredits?
    public var note: String?
    public var balance: Double?
    public var fetchedAt = Date()
    public init(plan: String, windows: [QuotaWindow], balance: Double? = nil) {
        self.plan = plan; self.windows = windows; self.balance = balance
    }
}
public enum MonitorError: LocalizedError {
    case invalidPayload, message(String), authenticationRequired(String)
    public var errorDescription: String? {
        switch self { case .invalidPayload: "The provider returned an unrecognized usage response."; case .message(let text), .authenticationRequired(let text): text }
    }
}
