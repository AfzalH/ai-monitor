import Foundation
import Testing
import MonitorCore
@testable import AIMonitor

@Test @MainActor func loopbackCallbackRejectsWrongStateThenAcceptsTheRightAttempt() async throws {
    let server = OAuthCallbackServer()
    let port = try await server.start()
    defer { server.stop() }
    server.attempt = try OAuthAttempt(provider: .claude, redirectURI: URL(string: "http://localhost:\(port)/callback")!, state: "right-state")
    let session = URLSession(configuration: .ephemeral)
    let (_, invalid) = try await session.data(from: URL(string: "http://127.0.0.1:\(port)/callback?code=bad&state=wrong-state")!)
    #expect((invalid as? HTTPURLResponse)?.statusCode == 400)
    let waiter = Task { try await server.waitForCode() }
    let (body, valid) = try await session.data(from: URL(string: "http://127.0.0.1:\(port)/callback?code=real-code&state=right-state")!)
    #expect((valid as? HTTPURLResponse)?.statusCode == 200)
    #expect(try await waiter.value == "real-code")
    #expect(!String(decoding: body, as: UTF8.self).contains("real-code"))
}
@Test @MainActor func cancellingBrowserLoginReleasesTheCallbackWaiter() async throws {
    let server = OAuthCallbackServer()
    _ = try await server.start()
    defer { server.stop() }
    let waiter = Task { try await server.waitForCode() }
    waiter.cancel()
    do { _ = try await waiter.value; Issue.record("Cancelled callback unexpectedly succeeded") }
    catch { #expect(error is CancellationError) }
}
