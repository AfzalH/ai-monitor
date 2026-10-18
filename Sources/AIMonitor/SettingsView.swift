import SwiftUI
import ServiceManagement
import MonitorCore

struct SettingsView: View {
    @EnvironmentObject var store: AccountStore
    @AppStorage("showRemaining") private var showRemaining = false
    @AppStorage("popoverHeightPercent") private var heightPercent = 40.0
    @State private var renaming: Account?
    @State private var newName = ""
    @State private var renameError: String?
    @State private var adding = false
    @State private var reconnecting: Account?
    @State private var deleting: Account?
    @State private var loginEnabled = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?
    private func move(_ account: Account, by offset: Int) {
        do { try store.moveAccount(account, by: offset) }
        catch { store.storageError = error.localizedDescription }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Your accounts").font(.title2.bold())
                    Text("Separate connections for every subscription.").foregroundStyle(.secondary)
                }
                Spacer()
                Button("Add account", systemImage: "plus") { adding = true }.buttonStyle(.borderedProminent).disabled(store.demo)
            }
            if store.demo {
                HStack { Text("You are viewing sample accounts."); Spacer(); Button("Exit demo") { store.leaveDemo() } }
                    .padding().background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
            }
            if store.accounts.isEmpty {
                ContentUnavailableView("No accounts yet", systemImage: "person.crop.circle.badge.plus", description: Text("Add Claude, Codex through ChatGPT, or OpenCode Go."))
            } else {
                List(store.accounts) { account in
                    HStack {
                        VStack(spacing: 2) {
                            Button { move(account, by: -1) } label: { Image(systemName: "chevron.up") }
                                .disabled(store.demo || store.accounts.first?.id == account.id).help("Move account up")
                                .accessibilityLabel("Move \(account.name) up")
                            Button { move(account, by: 1) } label: { Image(systemName: "chevron.down") }
                                .disabled(store.demo || store.accounts.last?.id == account.id).help("Move account down")
                                .accessibilityLabel("Move \(account.name) down")
                        }.buttonStyle(.borderless)
                        Image(systemName: account.provider.symbol).foregroundStyle(account.provider.color).frame(width: 24)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(account.name).fontWeight(.medium)
                            HStack(spacing: 6) {
                                Toggle("Menu bar", isOn: Binding(get: { store.isMenuEnabled(account) }, set: { store.setMenuEnabled(account, $0) }))
                                    .toggleStyle(.checkbox).accessibilityLabel("Show \(account.name) in menu bar")
                                TextField("Prefix", text: Binding(get: { store.menuPrefix(for: account) }, set: { store.setMenuPrefix($0, for: account) }))
                                    .textFieldStyle(.roundedBorder).frame(width: 65)
                                    .disabled(!store.isMenuEnabled(account)).accessibilityLabel("Menu bar prefix for \(account.name)")
                            }

                            Text(store.errors[account.id] ?? account.provider.title).font(.caption).foregroundStyle(store.errors[account.id] == nil ? Color.secondary : Color.orange)
                        }
                        Spacer()
                        Button("Rename") { renameError = nil; newName = account.name; renaming = account } .disabled(store.demo)
                        Button("Reconnect") { reconnecting = account }.disabled(store.demo)
                        Button { deleting = account } label: { Image(systemName: "trash") }.help("Remove account").disabled(store.demo)
                    }.padding(.vertical, 6)
                }.listStyle(.inset).clipShape(RoundedRectangle(cornerRadius: 8))
            }
            Divider()
            Picker("Quota display", selection: $showRemaining) {
                Text("Used").tag(false)
                Text("Remaining").tag(true)
            }.pickerStyle(.segmented)
            HStack {
                Text("Maximum popout height")
                Slider(value: $heightPercent, in: 30...90, step: 10)
                Text("\(Int(heightPercent))%").monospacedDigit().frame(width: 40)
            }
            Text("Select Menu bar beside each account to show its remaining quota. Selected accounts refresh every minute; Claude checks at most every five minutes and pauses longer if throttled.")
                .font(.caption).foregroundStyle(.secondary)
            Toggle("Launch at login", isOn: $loginEnabled).onChange(of: loginEnabled) { _, enabled in
                do {
                    if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                    loginError = nil
                } catch { loginError = error.localizedDescription }
            }
            Text("Opening refreshes at most once per minute. Refresh respects provider cooldowns. Reconnect when a session expires.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Link("Privacy policy", destination: URL(string: "https://www.srizon.com/privacy")!)
                Spacer()
                Button("Quit AI Monitor") { NSApp.terminate(nil) }.buttonStyle(.plain).foregroundStyle(.secondary)
            }
            if let error = renameError ?? store.storageError ?? loginError { Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled) }
        }.padding(24).frame(width: 650, height: 690)
            .sheet(isPresented: $adding) { SetupView().environmentObject(store) }
            .sheet(item: $reconnecting) { account in SetupView(existing: account).environmentObject(store) }
            .alert("Rename account", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
                TextField("Account name", text: $newName)
                Button("Save") {
                    if let account = renaming {
                        do { try store.rename(account, to: newName); renameError = nil }
                        catch { renameError = error.localizedDescription }
                    }
                    renaming = nil
                }.disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button("Cancel", role: .cancel) { renaming = nil }
            }
            .alert("Remove this account?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
                Button("Remove", role: .destructive) { if let account = deleting { store.remove(account) }; deleting = nil }
                Button("Cancel", role: .cancel) { deleting = nil }
            } message: { Text("This removes the saved connection from AI Monitor and Keychain. Your subscription stays active.") }
    }
}
