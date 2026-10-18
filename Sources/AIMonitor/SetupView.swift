import SwiftUI
import AppKit
import UniformTypeIdentifiers
import MonitorCore

struct SetupView: View {
    @EnvironmentObject var store: AccountStore
    @Environment(\.dismiss) var dismiss
    var existing: Account?
    @State private var provider: Provider = .claude
    @State private var name = ""
    @State private var method = 0
    @State private var secret = ""
    @State private var scope = ""
    @State private var credential: Credential?
    @State private var workspaces: [Workspace] = []
    @State private var selectedWorkspace = ""
    @State private var busy = false
    @State private var error: String?
    @State private var login: BrowserLogin?
    @State private var generation = UUID()
    @State private var operation: Task<Void, Never>?
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text(existing == nil ? "Add an account" : "Reconnect account").font(.title2.bold())
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            Text("Keep every subscription in one place. Each connection is stored separately in your Mac's Keychain.")
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Form {
                Picker("Provider", selection: $provider) {
                    ForEach(Provider.allCases, id: \.self) { Text($0.title).tag($0) }
                }.disabled(existing != nil || busy)
                TextField("Account name", text: $name, prompt: Text("e.g. Personal or Backup"))
                Picker("Connect with", selection: $method) {
                    if provider != .opencode { Text("Default browser sign-in").tag(0) }
                    Text(provider == .opencode ? "Go API key" : "Access token").tag(1)
                    if provider == .codex { Text("Codex login file").tag(2) }
                    if provider == .opencode { Text("Console session, advanced").tag(3) }
                }.disabled(busy)
            }
            if method == 0 {
                Text("Opens your default browser. Authorize the subscription account you want to monitor, then return here. To add another account, select it on the provider’s sign-in page.")
                    .font(.callout).foregroundStyle(.secondary)
                Button("Sign in to \(provider.title)…") {
                    login?.close(); generation = UUID(); credential = nil
                    let expectedProvider = provider
                    let expectedGeneration = generation
                    let browser = BrowserLogin(provider: provider) { result in
                        guard provider == expectedProvider, generation == expectedGeneration else { return }
                        prepare(result)
                    }
                    login = browser; browser.show()
                }.disabled(busy)
                if let login { BrowserLoginStatus(login: login) }
            } else if method == 1 {
                if provider == .opencode {
                    Button("Open OpenCode console in browser") { NSWorkspace.shared.open(URL(string: "https://opencode.ai/console")!) }
                }
                SecureField(provider == .opencode ? "OpenCode Go API key" : "OAuth access token", text: $secret)
                if provider == .codex { TextField("ChatGPT account ID, optional", text: $scope) }
                Text(provider == .opencode ? "Use the key from your OpenCode Go workspace. Sign in in your browser and copy a Go key here. For Zen billing, use the advanced console-session option." : "Use a subscription OAuth access token, not a paid API key. When it expires, reconnect the account. Tokens are never written to the account list.")
                    .font(.caption).foregroundStyle(.secondary)
            } else if method == 3 {
                Button("Open OpenCode console in browser") { NSWorkspace.shared.open(URL(string: "https://opencode.ai/console")!) }
                SecureField("Console Cookie header", text: $secret).disabled(busy)
                Text("For Go or Zen billing detection, paste your own opencode.ai console Cookie header from browser developer tools. Browser sessions cannot transfer to the app automatically. A Go API key is simpler for Go subscriptions.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Load workspaces") {
                    prepare(Credential(kind: .cookie, secret: secret.trimmingCharacters(in: .whitespacesAndNewlines)))
                }.disabled(busy || secret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            } else {
                HStack {
                    Button("Import current Codex login") { importCodex(URL(fileURLWithPath: ProcessInfo.processInfo.environment["CODEX_HOME"] ?? (NSHomeDirectory() + "/.codex")).appendingPathComponent("auth.json")) }
                    Button("Choose auth.json…") {
                        let panel = NSOpenPanel(); panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
                        panel.allowedContentTypes = [.json]; panel.showsHiddenFiles = true
                        if panel.runModal() == .OK, let url = panel.url { importCodex(url) }
                    }
                }.disabled(busy)
                Text("Copies the current access token into Keychain. To add another account, choose its auth.json file. The app never modifies or refreshes CLI credentials.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if !workspaces.isEmpty {
                Picker("Workspace", selection: $selectedWorkspace) {
                    ForEach(workspaces) { Text($0.name).tag($0.id) }
                }
            }
            if credential != nil { Label("Sign-in received. Verify and save to start monitoring.", systemImage: "checkmark.circle.fill").foregroundStyle(.teal).font(.callout) }
            if let error { Text(error).font(.callout).foregroundStyle(.red).textSelection(.enabled) }
            Spacer(minLength: 0)
            HStack {
                if busy { ProgressView().controlSize(.small) }
                Spacer()
                Button("Verify and save") { save() }.buttonStyle(.borderedProminent)
                    .disabled(busy || (method == 1 ? secret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty : credential == nil))
            }
        }
        .padding(24).frame(width: 510, height: 490)
        .onAppear { if let existing { provider = existing.provider; name = existing.name } }
        .onChange(of: provider) { _, newValue in reset(); method = newValue == .opencode ? 1 : 0 }
        .onChange(of: method) { _, _ in reset() }
        .onChange(of: secret) { _, _ in if method == 3 { credential = nil; workspaces = []; selectedWorkspace = "" } }
        .onDisappear { reset() }
    }
    private func reset() { generation = UUID(); operation?.cancel(); login?.close(); login = nil; credential = nil; workspaces = []; selectedWorkspace = ""; secret = ""; scope = ""; error = nil }
    private func importCodex(_ url: URL) {
        do { prepare(try Credential.codexFile(Data(contentsOf: url))) }
        catch { self.error = error.localizedDescription }
    }
    private func prepare(_ value: Credential) {
        busy = true; error = nil; credential = nil
        let expectedGeneration = generation
        let currentProvider = provider
        operation = Task {
            do {
                let spaces = try await store.client.workspaces(provider: currentProvider, credential: value)
                try Task.checkCancellation()
                guard generation == expectedGeneration else { return }
                if value.kind == .cookie && spaces.isEmpty { throw MonitorError.message("No workspace was found for this account.") }
                workspaces = spaces; selectedWorkspace = spaces.first?.id ?? ""; credential = value
            } catch { self.error = error.localizedDescription }
            busy = false
        }
    }
    private func save() {
        busy = true; error = nil
        let currentProvider = provider
        let expectedGeneration = generation
        operation = Task {
            do {
                var auth: Credential
                if method == 1 {
                    auth = Credential(kind: .bearer, secret: secret.trimmingCharacters(in: .whitespacesAndNewlines), scope: scope.isEmpty ? nil : scope)
                } else {
                    guard let value = credential else { throw MonitorError.message("Sign in first.") }
                    auth = value
                }
                if !selectedWorkspace.isEmpty { auth.scope = selectedWorkspace }
                try Task.checkCancellation()
                guard generation == expectedGeneration else { return }
                let account = Account(id: existing?.id ?? UUID(), name: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? currentProvider.title : name.trimmingCharacters(in: .whitespacesAndNewlines), provider: currentProvider)
                try await store.verifyAndSave(account: account, credential: auth)
                secret = ""; credential = nil; dismiss()
            } catch { self.error = error.localizedDescription }
            busy = false
        }
    }
}
