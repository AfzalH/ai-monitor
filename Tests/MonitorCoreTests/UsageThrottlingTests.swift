import Foundation
import Testing
@testable import MonitorCore

private actor ThrottleTransport: UsageTransport {
    var calls = 0
    let retryAt: Date?
    let limited: Bool
    init(limited: Bool, retryAt: Date? = nil) { self.limited = limited; self.retryAt = retryAt }
    func get(_ request: URLRequest) async throws -> Data {
        calls += 1
        if limited { throw HTTPRateLimitError(retryAt: retryAt) }
        return Data("fixture".utf8)
    }
}
private func fixtureRequest(_ token: String = "fixture") -> URLRequest {
    var request = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
    request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
    return request
}
@Test func retryAfterSupportsSecondsAndHTTPDate() {
    let now = Date(timeIntervalSince1970: 0)
    #expect(HTTPRateLimitError.retryDate("600", now: now) == now.addingTimeInterval(600))
    #expect(HTTPRateLimitError.retryDate("Thu, 01 Jan 1970 00:10:00 GMT", now: now) == now.addingTimeInterval(600))
    #expect(HTTPRateLimitError.retryDate("invalid", now: now) == nil)
    #expect(HTTPRateLimitError.retryDate("-1", now: now) == nil)
}
@Test func claudeSpacingPersistsAndSeparatesCredentials() async throws {
    let suite = UUID().uuidString
    defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
    let gate = ClaudeUsageThrottle(suiteName: suite)
    let transport = ThrottleTransport(limited: false)
    let now = Date()
    _ = try await gate.get(fixtureRequest(), using: transport, now: now)
    do {
        _ = try await gate.get(fixtureRequest(), using: transport, now: now.addingTimeInterval(60))
        Issue.record("Repeated request bypassed spacing")
    } catch let error as UsageRefreshDeferred { #expect(!error.rateLimited); #expect(error.until == now.addingTimeInterval(300)) }
    let restored = ClaudeUsageThrottle(suiteName: suite)
    do {
        _ = try await restored.get(fixtureRequest(), using: transport, now: now.addingTimeInterval(100))
        Issue.record("Restart bypassed spacing")
    } catch is UsageRefreshDeferred {}
    _ = try await restored.get(fixtureRequest("second"), using: transport, now: now)
    #expect(await transport.calls == 2)
    _ = try await restored.get(fixtureRequest(), using: transport, now: now.addingTimeInterval(300))
    #expect(await transport.calls == 3)
    let data = UserDefaults(suiteName: suite)!.data(forKey: "claudeUsageThrottle")!
    #expect(!String(decoding: data, as: UTF8.self).contains("fixture"))
}
@Test func claudeBackoffHonorsServerAndEscalatesWithoutExtraRequests() async throws {
    let suite = UUID().uuidString
    defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
    let gate = ClaudeUsageThrottle(suiteName: suite)
    let now = Date()
    let transport = ThrottleTransport(limited: true, retryAt: now.addingTimeInterval(1200))
    do { _ = try await gate.get(fixtureRequest(), using: transport, now: now); Issue.record("Expected throttling") }
    catch let error as UsageRefreshDeferred { #expect(error.rateLimited); #expect(error.until == now.addingTimeInterval(1201)) }
    do { _ = try await gate.get(fixtureRequest(), using: transport, now: now.addingTimeInterval(900)); Issue.record("Retried too early") }
    catch is UsageRefreshDeferred {}
    #expect(await transport.calls == 1)
    do { _ = try await gate.get(fixtureRequest(), using: transport, now: now.addingTimeInterval(1201)); Issue.record("Expected throttling") }
    catch let error as UsageRefreshDeferred { #expect(error.until == now.addingTimeInterval(3001)) }
    do { _ = try await gate.get(fixtureRequest(), using: transport, now: now.addingTimeInterval(3001)); Issue.record("Expected throttling") }
    catch let error as UsageRefreshDeferred { #expect(error.until == now.addingTimeInterval(6601)) }
}
@Test func missingRetryAfterStillPausesFifteenMinutes() async throws {
    let suite = UUID().uuidString
    defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
    let now = Date()
    do { _ = try await ClaudeUsageThrottle(suiteName: suite).get(fixtureRequest(), using: ThrottleTransport(limited: true), now: now); Issue.record("Expected throttling") }
    catch let error as UsageRefreshDeferred { #expect(error.until == now.addingTimeInterval(900)) }
}
@Test func reconnectKeepsCooldownWhileBrowserOrganizationsAreIndependent() async throws {
    let suite = UUID().uuidString
    defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
    let gate = ClaudeUsageThrottle(suiteName: suite)
    let transport = ThrottleTransport(limited: true)
    let now = Date()
    let accountID = UUID()
    do { _ = try await gate.get(fixtureRequest(), using: transport, accountID: accountID, now: now) }
    catch is UsageRefreshDeferred {}
    let restored = ClaudeUsageThrottle(suiteName: suite)
    do {
        _ = try await restored.get(fixtureRequest("new token"), using: transport, accountID: accountID, now: now.addingTimeInterval(60))
        Issue.record("Reconnect bypassed backoff")
    } catch let error as UsageRefreshDeferred { #expect(error.rateLimited); #expect(error.until == now.addingTimeInterval(900)) }
    #expect(await transport.calls == 1)
    let successful = ThrottleTransport(limited: false)
    for org in ["one", "two"] {
        var request = URLRequest(url: URL(string: "https://claude.ai/api/organizations/\(org)/usage")!)
        request.setValue("same session", forHTTPHeaderField: "Cookie")
        _ = try await gate.get(request, using: successful, accountID: UUID(), now: now)
    }
    #expect(await successful.calls == 2)
}
