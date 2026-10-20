import Foundation
import Testing
@testable import MonitorCore

private func attempt(_ provider: Provider = .claude) throws -> OAuthAttempt {
    try OAuthAttempt(provider: provider, redirectURI: URL(string: provider == .claude ? "http://localhost:54321/callback" : "http://127.0.0.1:1455/auth/callback")!, verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk", state: "expected-state")
}
@Test func browserAuthorizationUsesPKCEAndTheExactCallback() throws {
    let flow = try attempt()
    let url = URLComponents(url: flow.authorizationURL, resolvingAgainstBaseURL: false)!
    let items = try #require(url.queryItems)
    let query = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value!) })
    #expect(url.scheme == "https")
    #expect(url.host == "claude.com")
    #expect(query["code_challenge"] == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    #expect(query["state"] == "expected-state")
    #expect(query["redirect_uri"] == "http://localhost:54321/callback")
    #expect(!flow.authorizationURL.absoluteString.contains(flow.verifier))
}
@Test func callbackRejectsOtherAttemptsAndAmbiguousParameters() throws {
    let flow = try attempt()
    for target in ["/callback?code=a&state=wrong", "/wrong?code=a&state=expected-state", "/callback?code=a&code=b&state=expected-state", "/callback?code=a&state=expected-state&state=wrong", "/callback?state=expected-state", "https://evil.test/callback?code=a&state=expected-state"] {
        #expect(throws: (any Error).self) { try flow.callbackCode(from: target) }
    }
    #expect(try flow.callbackCode(from: "/callback?code=authorized-code&state=expected-state") == "authorized-code")
}
@Test func tokenExchangeIsBoundToProviderAndVerifier() throws {
    let claude = try attempt().tokenRequest(code: "test-code")
    let json = try JSONSerialization.jsonObject(with: claude.httpBody!) as! [String: String]
    #expect(claude.url?.absoluteString == "https://platform.claude.com/v1/oauth/token")
    #expect(claude.httpMethod == "POST")
    #expect(json["code_verifier"] == "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")
    #expect(json["state"] == "expected-state")
    let codex = try attempt(.codex).tokenRequest(code: "code+with&symbols")
    #expect(codex.url?.host == "auth.openai.com")
    let body = String(decoding: codex.httpBody!, as: UTF8.self)
    #expect(body.contains("code=code%2Bwith%26symbols"))
    #expect(body.contains("redirect_uri=http%3A%2F%2F127.0.0.1%3A1455%2Fauth%2Fcallback"))
}
@Test func oauthTokenResponseKeepsRenewalDetails() throws {
    let now = Date()
    let credential = try attempt().credential(from: Data(#"{"access_token":"test-access","refresh_token":"test-refresh","expires_in":28800,"token_type":"Bearer"}"#.utf8), now: now)
    #expect(credential.secret == "test-access")
    #expect(credential.kind == .bearer)
    #expect(credential.refreshToken == "test-refresh")
    #expect(credential.expiresAt == now.addingTimeInterval(28800))
    #expect(!credential.needsRenewal(at: now.addingTimeInterval(28700)))
    #expect(credential.needsRenewal(at: now.addingTimeInterval(28740)))
}
@Test func renewalRequestsMatchProviderCLIs() throws {
    for (provider, host, scope) in [(Provider.claude, "platform.claude.com", "user:profile user:inference"), (.codex, "auth.openai.com", "openid profile email")] {
        let request = try OAuthAttempt.renewalRequest(provider: provider, refreshToken: "test-refresh")
        let data = try #require(request.httpBody)
        let body = try #require(try JSONSerialization.jsonObject(with: data) as? [String: String])
        #expect(request.httpMethod == "POST")
        #expect(request.url?.host == host)
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(body["grant_type"] == "refresh_token")
        #expect(body["refresh_token"] == "test-refresh")
        #expect(body["scope"] == scope)
        #expect(body["client_id"]?.isEmpty == false)
    }
}
private actor TokenEndpoint: UsageTransport {
    let response: Data?
    init(_ response: Data?) { self.response = response }
    func get(_ request: URLRequest) async throws -> Data {
        guard let response else { throw HTTPStatusError(status: 400) }
        return response
    }
}
@Test func renewalKeepsDetailsTheProviderOmits() async throws {
    let previous = Credential(kind: .bearer, secret: "old", scope: "account-b", refreshToken: "test-refresh", expiresAt: Date())
    let renewed = try await UsageClient(transport: TokenEndpoint(Data(#"{"access_token":"new"}"#.utf8))).renew(provider: .codex, credential: previous)
    #expect(renewed.secret == "new")
    #expect(renewed.refreshToken == "test-refresh")
    #expect(renewed.scope == "account-b")
    #expect(renewed.expiresAt == nil)
}
@Test func rejectedRenewalAsksToReconnect() async throws {
    let previous = Credential(kind: .bearer, secret: "old", refreshToken: "revoked")
    do { _ = try await UsageClient(transport: TokenEndpoint(nil)).renew(provider: .claude, credential: previous); Issue.record("Expected rejection") }
    catch MonitorError.authenticationRequired {}
    do { _ = try await UsageClient(transport: TokenEndpoint(nil)).renew(provider: .claude, credential: Credential(kind: .bearer, secret: "pasted")); Issue.record("Expected reconnect") }
    catch MonitorError.authenticationRequired {}
}
