import Foundation
import Testing
@testable import MonitorCore
@Test func codexImportPreservesAccountScope() throws {
    let credential = try Credential.codexFile(Data(#"{"tokens":{"access_token":"test-token","account_id":"account-b","refresh_token":"never-import-me"}}"#.utf8))
    #expect(credential.scope == "account-b")
    #expect(credential.secret == "test-token")
    let serialized = String(decoding: try JSONEncoder().encode(credential), as: UTF8.self)
    #expect(!serialized.contains("never-import-me"))
}
@Test func apiKeyIsNotAChatGPTSubscriptionLogin() {
    #expect(throws: (any Error).self) { try Credential.codexFile(Data(#"{"OPENAI_API_KEY":"sk-test"}"#.utf8)) }
}
