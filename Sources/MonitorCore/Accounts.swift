import Foundation
public enum AuthKind: String, Codable, Sendable { case bearer, cookie }
public struct Credential: Codable, Sendable {
    public var kind: AuthKind
    public var secret: String
    public var scope: String?
    public init(kind: AuthKind, secret: String, scope: String? = nil) { self.kind = kind; self.secret = secret; self.scope = scope }
    public static func codexFile(_ data: Data) throws -> Credential {
        let root = try UsageParser.object(data)
        guard let tokens = root["tokens"] as? [String: Any],
              let token = tokens["access_token"] as? String, !token.isEmpty else {
            throw MonitorError.message("This file has no ChatGPT subscription login. Sign in using Codex first.")
        }
        return Credential(kind: .bearer, secret: token, scope: tokens["account_id"] as? String)
    }
}
public struct Account: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public var name: String
    public let provider: Provider
    public init(id: UUID = UUID(), name: String, provider: Provider) { self.id = id; self.name = name; self.provider = provider }
}
public struct Workspace: Identifiable, Sendable {
    public let id: String
    public let name: String
}
