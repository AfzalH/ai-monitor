import Foundation
import Testing
@testable import MonitorCore
private actor FixtureTransport: UsageTransport {
    var requests: [URLRequest] = []
    func get(_ request: URLRequest) async throws -> Data {
        requests.append(request)
        if request.url!.path.hasSuffix("rate-limit-reset-credits") { throw MonitorError.message("Unavailable") }
        return Data(#"{"plan_type":"plus","rate_limit":{"primary_window":{"used_percent":17,"limit_window_seconds":18000}}}"#.utf8)
    }
}
@Test func resetFailureKeepsUsageAndAccountScope() async throws {
    let transport = FixtureTransport()
    let client = UsageClient(transport: transport)
    let result = try await client.fetch(provider: .codex, credential: Credential(kind: .bearer, secret: "fixture", scope: "second-account"))
    #expect(result.windows.first?.used == 17)
    #expect(result.resets == nil)
    #expect(result.note != nil)
    let requests = await transport.requests
    #expect(requests.count == 2)
    #expect(requests.allSatisfy { $0.value(forHTTPHeaderField: "ChatGPT-Account-Id") == "second-account" })
    #expect(requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == "Bearer fixture" })
}
