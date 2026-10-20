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
    catch let error as UsageRefreshDeferred { #expect(error.rateLimited); #expect(error.until == now.addingTimeInterval(1320)) }
    do { _ = try await gate.get(fixtureRequest(), using: transport, now: now.addingTimeInterval(900)); Issue.record("Retried too early") }
    catch is UsageRefreshDeferred {}
    #expect(await transport.calls == 1)
    do { _ = try await gate.get(fixtureRequest(), using: transport, now: now.addingTimeInterval(1320)); Issue.record("Expected throttling") }
    catch let error as UsageRefreshDeferred { #expect(error.until == now.addingTimeInterval(3120)) }
    do { _ = try await gate.get(fixtureRequest(), using: transport, now: now.addingTimeInterval(3120)); Issue.record("Expected throttling") }
    catch let error as UsageRefreshDeferred { #expect(error.until == now.addingTimeInterval(6720)) }
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

private struct OfflineTransport: UsageTransport {
    var code: URLError.Code = .notConnectedToInternet
    func get(_ request: URLRequest) async throws -> Data { throw URLError(code) }
}
@Test func offlineClaudeAttemptDoesNotConsumeProviderCooldown() async throws {
    let suite = UUID().uuidString
    defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
    let gate = ClaudeUsageThrottle(suiteName: suite)
    let now = Date()
    let accountID = UUID()
    do { _ = try await gate.get(fixtureRequest(), using: OfflineTransport(), accountID: accountID, now: now) }
    catch let error as URLError { #expect(error.code == .notConnectedToInternet) }
    let restored = ClaudeUsageThrottle(suiteName: suite)
    let result = try await restored.get(fixtureRequest(), using: ThrottleTransport(limited: false), accountID: accountID, now: now.addingTimeInterval(1))
    #expect(result == Data("fixture".utf8))
}

@Test func ambiguousTimeoutKeepsClaudeCooldown() async throws {
    let suite = UUID().uuidString
    defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
    let gate = ClaudeUsageThrottle(suiteName: suite)
    let now = Date()
    do { _ = try await gate.get(fixtureRequest(), using: OfflineTransport(code: .timedOut), now: now) }
    catch let error as URLError { #expect(error.code == .timedOut) }
    do {
        _ = try await gate.get(fixtureRequest(), using: ThrottleTransport(limited: false), now: now.addingTimeInterval(60))
        Issue.record("Ambiguous timeout bypassed provider spacing")
    } catch let deferred as UsageRefreshDeferred {
        #expect(deferred.until == now.addingTimeInterval(300))
        #expect(!deferred.rateLimited)
    }
}

private actor ScriptedTransport: UsageTransport {
    private var outcomes: [Error?]
    init(_ outcomes: [Error?]) { self.outcomes = outcomes }
    func get(_ request: URLRequest) async throws -> Data {
        if let error = outcomes.removeFirst() { throw error }
        return Data("{}".utf8)
    }
}
@Test func nonThrottledResponseClearsEarlierBackoff() async throws {
    let suite = UUID().uuidString
    defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
    let gate = ClaudeUsageThrottle(suiteName: suite)
    let now = Date()
    let transport = ScriptedTransport([HTTPRateLimitError(retryAt: nil), MonitorError.authenticationRequired("Sign-in expired. Reconnect this account."), HTTPRateLimitError(retryAt: nil)])
    do { _ = try await gate.get(fixtureRequest(), using: transport, now: now); Issue.record("Expected throttling") }
    catch is UsageRefreshDeferred {}
    do { _ = try await gate.get(fixtureRequest(), using: transport, now: now.addingTimeInterval(900)); Issue.record("Expected sign-in error") }
    catch MonitorError.authenticationRequired {}
    // The sign-in error still keeps the usual five-minute spacing.
    do { _ = try await gate.get(fixtureRequest(), using: transport, now: now.addingTimeInterval(1000)); Issue.record("Retried too early") }
    catch let error as UsageRefreshDeferred { #expect(!error.rateLimited) }
    do { _ = try await gate.get(fixtureRequest(), using: transport, now: now.addingTimeInterval(1200)); Issue.record("Expected throttling") }
    catch let error as UsageRefreshDeferred { #expect(error.until == now.addingTimeInterval(2100)) }
}
@Test func reconnectSkipsSpacingButNotThrottling() async throws {
    let suite = UUID().uuidString
    defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
    let gate = ClaudeUsageThrottle(suiteName: suite)
    let now = Date()
    let accountID = UUID()
    let transport = ScriptedTransport([MonitorError.authenticationRequired("Sign-in expired. Reconnect this account."), nil, HTTPRateLimitError(retryAt: nil)])
    do { _ = try await gate.get(fixtureRequest("expired"), using: transport, accountID: accountID, now: now); Issue.record("Expected sign-in error") }
    catch MonitorError.authenticationRequired {}
    do { _ = try await gate.get(fixtureRequest("expired"), using: transport, accountID: accountID, now: now.addingTimeInterval(10)); Issue.record("Retried too early") }
    catch is UsageRefreshDeferred {}
    _ = try await gate.get(fixtureRequest("renewed"), using: transport, accountID: accountID, now: now.addingTimeInterval(20))
    do { _ = try await gate.get(fixtureRequest("renewed"), using: transport, accountID: accountID, now: now.addingTimeInterval(400)); Issue.record("Expected throttling") }
    catch is UsageRefreshDeferred {}
    do { _ = try await gate.get(fixtureRequest("another"), using: transport, accountID: accountID, now: now.addingTimeInterval(500)); Issue.record("Reconnect bypassed throttling") }
    catch let error as UsageRefreshDeferred { #expect(error.rateLimited) }
}
@Test func userReconnectGetsOneRequestThroughAccountBackoff() async throws {
    let suite = UUID().uuidString
    defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
    let gate = ClaudeUsageThrottle(suiteName: suite)
    let now = Date()
    let accountID = UUID()
    let transport = ScriptedTransport([HTTPRateLimitError(retryAt: nil), HTTPRateLimitError(retryAt: nil), nil])
    do { _ = try await gate.get(fixtureRequest("old"), using: transport, accountID: accountID, now: now); Issue.record("Expected throttling") }
    catch is UsageRefreshDeferred {}
    // A renewed token in the background still waits for the backoff.
    do { _ = try await gate.get(fixtureRequest("renewed"), using: transport, accountID: accountID, now: now.addingTimeInterval(60)); Issue.record("Renewal bypassed throttling") }
    catch let error as UsageRefreshDeferred { #expect(error.rateLimited) }
    // Reconnecting reaches the provider. Another 429 throttles again.
    do { _ = try await gate.get(fixtureRequest("signed-in"), using: transport, accountID: accountID, reconnecting: true, now: now.addingTimeInterval(120)); Issue.record("Expected throttling") }
    catch let error as UsageRefreshDeferred { #expect(error.rateLimited && error.until == now.addingTimeInterval(1920)) }
    _ = try await gate.get(fixtureRequest("signed-in-again"), using: transport, accountID: accountID, reconnecting: true, now: now.addingTimeInterval(180))
    // After a successful reconnect only the usual spacing applies.
    do { _ = try await gate.get(fixtureRequest("signed-in-again"), using: transport, accountID: accountID, now: now.addingTimeInterval(240)); Issue.record("Retried too early") }
    catch let error as UsageRefreshDeferred { #expect(!error.rateLimited && error.until == now.addingTimeInterval(480)) }
}
