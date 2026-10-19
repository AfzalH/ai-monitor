import Foundation
@preconcurrency import Network
import MonitorCore

/// A short-lived callback listener bound only to IPv4 loopback, never the LAN.
@MainActor final class OAuthCallbackServer {
    var attempt: OAuthAttempt?
    private var listener: NWListener?
    private var ready: CheckedContinuation<UInt16, any Error>?
    private var waiter: CheckedContinuation<String, any Error>?
    private var result: Result<String, any Error>?
    private var claimed = false
    private var connections: [UUID: CallbackConnection] = [:]
    func start(port: UInt16 = 0) async throws -> UInt16 {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!)
        let listener = try NWListener(using: parameters)
        self.listener = listener
        listener.newConnectionHandler = { [weak self] connection in
            Task { @MainActor in self?.receive(connection) }
        }
        listener.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                guard let self else { return }
                switch state {
                case .ready:
                    if let port = self.listener?.port?.rawValue { self.ready?.resume(returning: port); self.ready = nil }
                case .failed:
                    self.ready?.resume(throwing: MonitorError.message("The local sign-in port is unavailable. Close other pending sign-ins and try again.")); self.ready = nil
                    self.stop()
                case .cancelled:
                    self.ready?.resume(throwing: CancellationError()); self.ready = nil
                default: break
                }
            }
        }
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                ready = continuation
                listener.start(queue: .main)
            }
        } onCancel: { Task { @MainActor in self.stop() } }
    }
    func waitForCode() async throws -> String {
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                if let result { continuation.resume(with: result) } else { waiter = continuation }
            }
        } onCancel: { Task { @MainActor in self.stop() } }
    }
    func stop() {
        listener?.cancel(); listener = nil
        ready?.resume(throwing: CancellationError()); ready = nil
        finish(.failure(CancellationError()))
        let active = Array(connections.values)
        connections.removeAll()
        for connection in active { connection.close() }
    }
    private func finish(_ result: Result<String, any Error>) {
        guard self.result == nil else { return }
        self.result = result
        waiter?.resume(with: result); waiter = nil
    }
    private func receive(_ connection: NWConnection) {
        guard connections.count < 8, result == nil else { connection.cancel(); return }
        let id = UUID()
        let reader = CallbackConnection(connection: connection, request: { [weak self] text in
            guard let self, let attempt = self.attempt, self.result == nil, !self.claimed else { return (400, "This sign-in is no longer active.", nil) }
            let lines = text.components(separatedBy: "\r\n")
            let words = (lines.first ?? "").split(separator: " ")
            let hosts = lines.dropFirst().filter { $0.lowercased().hasPrefix("host:") }
                .map { String($0.dropFirst(5)).trimmingCharacters(in: .whitespaces).lowercased() }
            let port = attempt.redirectURI.port ?? 0
            guard words.count == 3, words[0] == "GET", hosts.count == 1,
                  ["localhost:\(port)", "127.0.0.1:\(port)"].contains(hosts[0]) else { return (400, "Invalid sign-in callback.", nil) }
            do {
                let code = try attempt.callbackCode(from: String(words[1]))
                // Stop accepting new requests immediately. Deliver the code only after the browser response is sent.
                self.claimed = true
                self.listener?.cancel()
                self.listener = nil
                return (200, "Authorization received. Return to QuotaBar for AI to finish connecting.", .success(code))
            } catch let error as OAuthCallbackError {
                self.claimed = true; self.listener?.cancel(); self.listener = nil
                return (200, "Sign-in was declined. Return to QuotaBar for AI to try again.", .failure(error))
            } catch { return (400, "This callback does not match the active sign-in.", nil) }
        }, complete: { [weak self] outcome in
            if let outcome { self?.finish(outcome) }
            self?.connections[id] = nil
        })
        connections[id] = reader
        reader.start()
    }
}

@MainActor private final class CallbackConnection {
    typealias Reply = (status: Int, message: String, result: Result<String, any Error>?)
    private let connection: NWConnection
    private let request: (String) -> Reply
    private let complete: (Result<String, any Error>?) -> Void
    private var buffer = Data()
    private var timeout: Task<Void, Never>?
    private var closed = false
    init(connection: NWConnection, request: @escaping (String) -> Reply, complete: @escaping (Result<String, any Error>?) -> Void) {
        self.connection = connection; self.request = request; self.complete = complete
    }
    func start() {
        connection.start(queue: .main)
        timeout = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(15)); self?.close() } catch {}
        }
        read()
    }
    func close(_ result: Result<String, any Error>? = nil) {
        guard !closed else { return }; closed = true
        timeout?.cancel(); connection.cancel(); complete(result)
    }
    private func read() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, ended, error in
            Task { @MainActor in
                guard let self, !self.closed else { return }
                if let data { self.buffer.append(data) }
                guard self.buffer.count <= 16_384 else { self.close(); return }
                if let text = String(data: self.buffer, encoding: .utf8), text.contains("\r\n\r\n") {
                    self.reply(self.request(text))
                } else if ended || error != nil { self.close() }
                else { self.read() }
            }
        }
    }
    private func reply(_ response: Reply) {
        let body = "<!doctype html><html><head><meta name=viewport content='width=device-width,initial-scale=1'><title>QuotaBar for AI</title></head><body style='font:18px system-ui;max-width:560px;margin:80px auto;padding:24px'><h1>QuotaBar for AI</h1><p>\(response.message)</p><p>You can close this tab.</p></body></html>"
        let header = "HTTP/1.1 \(response.status) \(response.status == 200 ? "OK" : "Bad Request")\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(body.utf8.count)\r\nCache-Control: no-store\r\nContent-Security-Policy: default-src 'none'; style-src 'unsafe-inline'\r\nConnection: close\r\n\r\n"
        connection.send(content: Data((header + body).utf8), completion: .contentProcessed { [weak self] _ in
            Task { @MainActor in self?.close(response.result) }
        })
    }
}
