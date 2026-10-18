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
@Test func oauthTokenResponseDoesNotPersistRefreshToken() throws {
    let credential = try attempt().credential(from: Data(#"{"access_token":"test-access","refresh_token":"do-not-persist","token_type":"Bearer"}"#.utf8))
    #expect(credential.secret == "test-access")
    #expect(credential.kind == .bearer)
    #expect(!String(decoding: try JSONEncoder().encode(credential), as: UTF8.self).contains("do-not-persist"))
}
