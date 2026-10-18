import Foundation
import Testing
import MonitorCore
@testable import AIMonitor

private actor TokenTransport: UsageTransport {
    var requests: [URLRequest] = []
    func get(_ request: URLRequest) async throws -> Data {
        requests.append(request)
        return Data(#"{"access_token":"browser-fixture","token_type":"Bearer"}"#.utf8)
    }
}
@Test @MainActor func externalBrowserFlowHandsTheCredentialBackAutomatically() async throws {
    let transport = TokenTransport()
    var opened: URL?
    var received: Credential?
    let login = BrowserLogin(provider: .claude, transport: transport, openBrowser: { opened = $0; return true }) { received = $0 }
    login.show()
    defer { login.close() }
    for _ in 0..<300 where opened == nil { try await Task.sleep(for: .milliseconds(10)) }
    let authorization = try #require(opened)
    let items = URLComponents(url: authorization, resolvingAgainstBaseURL: false)!.queryItems!
    let redirect = try #require(items.first { $0.name == "redirect_uri" }?.value)
    let state = try #require(items.first { $0.name == "state" }?.value)
    var callback = URLComponents(string: redirect)!
    callback.queryItems = [.init(name: "code", value: "fixture-code"), .init(name: "state", value: state)]
    _ = try await URLSession(configuration: .ephemeral).data(from: callback.url!)
    for _ in 0..<300 where received == nil { try await Task.sleep(for: .milliseconds(10)) }
    #expect(received?.secret == "browser-fixture")
    #expect(!login.isRunning)
    #expect(login.error == nil)
    let requests = await transport.requests
    #expect(requests.count == 1)
    #expect(requests.first?.httpMethod == "POST")
    #expect(requests.first?.url?.host == "platform.claude.com")
}
@Test @MainActor func defaultBrowserFailureIsVisibleAndDoesNotConnect() async throws {
    var completed = false
    let login = BrowserLogin(provider: .claude, openBrowser: { _ in false }) { _ in completed = true }
    login.show()
    defer { login.close() }
    for _ in 0..<300 where login.isRunning { try await Task.sleep(for: .milliseconds(10)) }
    #expect(login.error != nil)
    #expect(!login.isRunning)
    #expect(!completed)
}
