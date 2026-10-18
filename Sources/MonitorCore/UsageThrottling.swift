import Foundation
import CryptoKit

public struct HTTPRateLimitError: LocalizedError, Sendable {
    public let retryAt: Date?
    public init(retryAt: Date?) { self.retryAt = retryAt }
    public var errorDescription: String? { "The provider is throttling usage requests." }
    public static func retryDate(_ value: String?, now: Date = Date()) -> Date? {
        guard let value else { return nil }
        if let seconds = Double(value.trimmingCharacters(in: .whitespaces)), seconds.isFinite, seconds >= 0 {
            return now.addingTimeInterval(seconds)
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss z"
        return formatter.date(from: value)
    }
}

public struct UsageRefreshDeferred: LocalizedError, Sendable {
    public let until: Date
    public let rateLimited: Bool
    public var errorDescription: String? {
        let time = until.formatted(date: .omitted, time: .shortened)
        return rateLimited ? "Claude throttled usage checks. Paused until \(time)." : "Claude usage checks are spaced out. Next check after \(time)."
    }
}

/// An app-wide gate covers setup, manual refresh and background refresh alike.
/// Only a digest of the credential is persisted, never its value or usage data.
public actor ClaudeUsageThrottle {
    public static let shared = ClaudeUsageThrottle()
    private struct Entry: Codable {
        var until: Date
        var failures: Int
        var rateLimited: Bool
    }
    private let defaults: UserDefaults
    private var entries: [String: Entry]
    private var inFlight: Set<String> = []
    public init(suiteName: String? = nil) {
        let defaults = suiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard
        self.defaults = defaults
        entries = defaults.data(forKey: "claudeUsageThrottle").flatMap { try? JSONDecoder().decode([String: Entry].self, from: $0) } ?? [:]
    }
    private func persist() {
        if let data = try? JSONEncoder().encode(entries) { defaults.set(data, forKey: "claudeUsageThrottle") }
    }
    public func get(_ request: URLRequest, using transport: any UsageTransport, accountID: UUID? = nil, now: Date = Date()) async throws -> Data {
        let credential = request.value(forHTTPHeaderField: "Authorization") ?? request.value(forHTTPHeaderField: "Cookie") ?? "anonymous"
        // Browser organizations have separate usage windows. Keep duplicate entries
        // for the same credential + endpoint together, and preserve reconnect
        // cooldowns with the app account ID even when the token changes.
        let identity = credential + "|" + (request.url?.absoluteString ?? "")
        let key = SHA256.hash(data: Data(identity.utf8)).map { String(format: "%02x", $0) }.joined()
        let keys = [key] + (accountID.map { ["account:" + $0.uuidString] } ?? [])
        let previous = keys.compactMap { entries[$0] }.max { $0.failures < $1.failures }
        if let entry = keys.compactMap({ entries[$0] }).filter({ $0.until > now }).max(by: { $0.until < $1.until }) {
            throw UsageRefreshDeferred(until: entry.until, rateLimited: entry.rateLimited)
        }
        if keys.contains(where: { inFlight.contains($0) }) {
            throw UsageRefreshDeferred(until: now.addingTimeInterval(300), rateLimited: false)
        }
        for key in keys { entries[key] = Entry(until: now.addingTimeInterval(300), failures: previous?.failures ?? 0, rateLimited: false) }
        persist()
        inFlight.formUnion(keys)
        defer { inFlight.subtract(keys) }
        do {
            let data = try await transport.get(request)
            for key in keys { entries[key]?.failures = 0 }
            persist()
            return data
        } catch let error as HTTPRateLimitError {
            let failures = min(3, (previous?.failures ?? 0) + 1)
            let delay = 900 * pow(2, Double(failures - 1))
            let until = max(now.addingTimeInterval(delay), error.retryAt?.addingTimeInterval(1) ?? now)
            for key in keys { entries[key] = Entry(until: until, failures: failures, rateLimited: true) }
            persist()
            throw UsageRefreshDeferred(until: until, rateLimited: true)
        }
        // Other failures and cancellations keep the five-minute spacing: the
        // server may have counted the request even if no response reached us.
    }
}
