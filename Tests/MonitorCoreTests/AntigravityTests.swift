import Foundation
import Testing
@testable import MonitorCore

private let summary = #"""
{"groups":[
 {"displayName":"Gemini Models","buckets":[
  {"bucketId":"gemini-weekly","window":"weekly","resetTime":"2026-11-28T10:03:05Z","description":"used some","remainingFraction":0.665221},
  {"bucketId":"gemini-5h","window":"5h","resetTime":"2026-11-22T13:46:39Z","description":"used some","remainingFraction":0.927019}]},
 {"displayName":"Claude and GPT models","buckets":[
  {"bucketId":"3p-weekly","window":"weekly","resetTime":"2026-11-29T08:53:46Z","remainingFraction":1},
  {"bucketId":"3p-5h","window":"5h","resetTime":"2026-11-22T13:53:46Z","remainingFraction":1}]},
 {"displayName":"Gemini 4 Argon","buckets":[
  {"bucketId":"gemini-argon-wtu-weekly","displayName":"Gemini 4 Argon Weekly Limit","window":"weekly","resetTime":"2026-11-29T08:53:46Z","remainingFraction":1},
  {"bucketId":"gemini-off","window":"5h","disabled":true,"remainingFraction":0.1}]}
]}
"""#

@Test func antigravitySummaryBecomesFamilyWindows() throws {
    let result = try UsageParser.parse(Data(summary.utf8), provider: .antigravity)
    #expect(result.windows.map(\.label) == ["Gemini · Weekly", "Gemini · 5 hours", "Claude & GPT · Weekly", "Claude & GPT · 5 hours", "Gemini 4 Argon · Weekly"])
    #expect(abs(result.windows[0].used - 33.4779) < 0.001)
    #expect(result.windows[0].resetsAt == ISO8601DateFormatter().date(from: "2026-11-28T10:03:05Z"))
    // Untouched buckets report a rolling reset, which is not a real reset time.
    #expect(result.windows[2].used == 0 && result.windows[2].resetsAt == nil)
}

@Test func antigravityEmptySummaryIsRejected() {
    #expect(throws: (any Error).self) { try UsageParser.parse(Data(#"{"groups":[]}"#.utf8), provider: .antigravity) }
}

private func form(_ request: URLRequest) -> [String: String] {
    var parts = URLComponents(); parts.percentEncodedQuery = String(decoding: request.httpBody!, as: UTF8.self)
    return Dictionary(uniqueKeysWithValues: parts.queryItems!.map { ($0.name, $0.value ?? "") })
}

@Test func antigravitySignInUsesGoogleWithOfflineAccess() throws {
    OAuthAttempt.antigravitySecretOverride = ""
    #expect(!Provider.antigravity.isAvailable)
    #expect(throws: (any Error).self) { try OAuthAttempt(provider: .antigravity, redirectURI: URL(string: "http://127.0.0.1:1/oauth2callback")!) }
    OAuthAttempt.antigravitySecretOverride = "test-secret"
    let flow = try OAuthAttempt(provider: .antigravity, redirectURI: URL(string: "http://127.0.0.1:54321/oauth2callback")!, verifier: "v", state: "s")
    let url = URLComponents(url: flow.authorizationURL, resolvingAgainstBaseURL: false)!
    let query = Dictionary(uniqueKeysWithValues: url.queryItems!.map { ($0.name, $0.value!) })
    #expect(url.host == "accounts.google.com")
    #expect(query["client_id"]?.hasPrefix("1071006060591-") == true)
    #expect(query["access_type"] == "offline")
    #expect(query["scope"]?.contains("https://www.googleapis.com/auth/cloud-platform") == true)
    #expect(query["client_secret"] == nil)
    let token = try flow.tokenRequest(code: "abc")
    #expect(token.url?.absoluteString == "https://oauth2.googleapis.com/token")
    let body = form(token)
    #expect(body["grant_type"] == "authorization_code" && body["code"] == "abc" && body["code_verifier"] == "v")
    #expect(body["client_secret"] == "test-secret")
    let renewal = form(try OAuthAttempt.renewalRequest(provider: .antigravity, refreshToken: "r/1"))
    #expect(renewal["grant_type"] == "refresh_token" && renewal["refresh_token"] == "r/1" && renewal["client_secret"] != nil)
}

private actor HostTransport: UsageTransport {
    var requests: [URLRequest] = []
    let dailyError: (any Error)?
    init(dailyError: (any Error)?) { self.dailyError = dailyError }
    func get(_ request: URLRequest) async throws -> Data {
        requests.append(request)
        if request.url!.host == "daily-cloudcode-pa.googleapis.com", let dailyError { throw dailyError }
        return Data(summary.utf8)
    }
}

@Test func antigravityReadsTheDailyHostAsAntigravity() async throws {
    let transport = HostTransport(dailyError: nil)
    let result = try await UsageClient(transport: transport).fetch(provider: .antigravity, credential: Credential(kind: .bearer, secret: "tok"))
    #expect(result.windows.count == 5)
    let requests = await transport.requests
    #expect(requests.count == 1)
    #expect(requests[0].httpMethod == "POST" && requests[0].url?.path == "/v1internal:retrieveUserQuotaSummary")
    #expect(requests[0].value(forHTTPHeaderField: "Authorization") == "Bearer tok")
    #expect(requests[0].value(forHTTPHeaderField: "User-Agent")?.hasPrefix("antigravity/") == true)
}

@Test func antigravityFallsBackToProdOnlyWhenDailyRefusesTheAccount() async throws {
    let refused = HostTransport(dailyError: MonitorError.authenticationRequired("denied"))
    _ = try await UsageClient(transport: refused).fetch(provider: .antigravity, credential: Credential(kind: .bearer, secret: "tok"))
    #expect(await refused.requests.map { $0.url!.host! } == ["daily-cloudcode-pa.googleapis.com", "cloudcode-pa.googleapis.com"])
    let limited = HostTransport(dailyError: HTTPStatusError(status: 500))
    await #expect(throws: HTTPStatusError.self) { try await UsageClient(transport: limited).fetch(provider: .antigravity, credential: Credential(kind: .bearer, secret: "tok")) }
    #expect(await limited.requests.count == 1)
}
