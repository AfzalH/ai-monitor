import Foundation
import CryptoKit
import Security

public struct OAuthAttempt: Sendable {
    public let provider: Provider
    public let redirectURI: URL
    public let verifier: String
    public let state: String
    public init(provider: Provider, redirectURI: URL, verifier: String? = nil, state: String? = nil) throws {
        guard provider != .opencode else { throw MonitorError.message("OpenCode uses a Go API key or console session.") }
        self.provider = provider; self.redirectURI = redirectURI
        self.verifier = try verifier ?? Self.randomToken()
        self.state = try state ?? Self.randomToken()
    }
    private static func randomToken() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { throw MonitorError.message("Could not create a secure sign-in request.") }
        return Data(bytes).base64URLEncoded
    }
    private var clientID: String {
        provider == .claude ? "9d1c250a-e61b-44d9-88ed-5944d1962f5e" : "app_EMoamEEZ73f0CkXaXp7hrann"
    }
    public var authorizationURL: URL {
        var url = URLComponents(string: provider == .claude ? "https://claude.com/cai/oauth/authorize" : "https://auth.openai.com/oauth/authorize")!
        var items = ["client_id": clientID, "response_type": "code", "redirect_uri": redirectURI.absoluteString,
                     "scope": provider == .claude ? "user:profile user:inference" : "openid profile email offline_access",
                     "code_challenge": Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncoded,
                     "code_challenge_method": "S256", "state": state]
        if provider == .claude { items["code"] = "true" }
        else { items["id_token_add_organizations"] = "true"; items["codex_cli_simplified_flow"] = "true"; items["prompt"] = "login" }
        url.queryItems = items.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        return url.url!
    }
    public func callbackCode(from target: String) throws -> String {
        guard target.hasPrefix("/"), !target.hasPrefix("//"),
              let url = URLComponents(string: target), url.scheme == nil, url.host == nil,
              url.path == redirectURI.path, url.fragment == nil else { throw MonitorError.invalidPayload }
        let items = url.queryItems ?? []
        func single(_ name: String) -> String? {
            let values = items.filter { $0.name == name }
            return values.count == 1 ? values.first?.value : nil
        }
        guard single("state") == state else { throw MonitorError.invalidPayload }
        if single("error") != nil { throw OAuthCallbackError.denied }
        guard let code = single("code"), !code.isEmpty, code.utf8.count <= 8192 else { throw MonitorError.invalidPayload }
        return code
    }
    public func tokenRequest(code: String) throws -> URLRequest {
        var request = URLRequest(url: URL(string: provider == .claude ? "https://platform.claude.com/v1/oauth/token" : "https://auth.openai.com/oauth/token")!)
        request.httpMethod = "POST"; request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        var values = ["grant_type": "authorization_code", "code": code, "client_id": clientID,
                      "redirect_uri": redirectURI.absoluteString, "code_verifier": verifier]
        if provider == .claude {
            values["state"] = state
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: values)
        } else {
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
            request.httpBody = Data(values.sorted { $0.key < $1.key }.map {
                $0.key.addingPercentEncoding(withAllowedCharacters: allowed)! + "=" + $0.value.addingPercentEncoding(withAllowedCharacters: allowed)!
            }.joined(separator: "&").utf8)
        }
        return request
    }
    public func credential(from data: Data) throws -> Credential {
        let root = try UsageParser.object(data)
        guard let token = root["access_token"] as? String, !token.isEmpty else { throw MonitorError.invalidPayload }
        var scope: String?
        if provider == .codex {
            for jwt in [root["id_token"] as? String, token].compactMap({ $0 }) {
                let parts = jwt.split(separator: ".", omittingEmptySubsequences: false)
                guard parts.count == 3 else { continue }
                var raw = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
                raw += String(repeating: "=", count: (4 - raw.count % 4) % 4)
                if let data = Data(base64Encoded: raw), let claims = try? UsageParser.object(data),
                   let auth = claims["https://api.openai.com/auth"] as? [String: Any],
                   let id = auth["chatgpt_account_id"] as? String, !id.isEmpty { scope = id; break }
            }
        }
        return Credential(kind: .bearer, secret: token, scope: scope)
    }
}
private extension Data {
    var base64URLEncoded: String { base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "") }
}

public enum OAuthCallbackError: LocalizedError {
    case denied
    public var errorDescription: String? { "Sign-in was declined. Start again when you're ready." }
}
