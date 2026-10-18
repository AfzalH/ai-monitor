import SwiftUI
import AppKit
import MonitorCore

extension Provider {
    var symbol: String { switch self { case .claude: "sun.max"; case .codex: "terminal"; case .opencode: "chevron.left.forwardslash.chevron.right" } }
    var color: Color { switch self { case .claude: Color(red: 0.73, green: 0.40, blue: 0.28); case .codex: Color(red: 0.17, green: 0.48, blue: 0.46); case .opencode: Color(red: 0.41, green: 0.43, blue: 0.67) } }
    var dashboardURL: URL {
        let value = switch self {
        case .claude: "https://claude.ai/settings/usage"
        case .codex: "https://chatgpt.com/codex/settings/usage"
        case .opencode: "https://opencode.ai/console"
        }
        return URL(string: value)!
    }
}

struct DashboardView: View {
    @EnvironmentObject var store: AccountStore
    @Environment(\.openSettings) private var openSettings
    @AppStorage("showRemaining") private var showRemaining = false
    @AppStorage("popoverHeightPercent") private var heightPercent = 40.0
    var screenHeight: CGFloat = NSScreen.main?.visibleFrame.height ?? 900
    var settingsAction: (() -> Void)?
    var heightChanged: ((CGFloat) -> Void)?
    @State private var contentHeight: CGFloat = 0
    private var popoverHeight: CGFloat {
        let maximum = max(160, screenHeight * min(90, max(30, heightPercent)) / 100)
        let desired: CGFloat = store.accounts.isEmpty ? 240 : contentHeight > 0 ? contentHeight + 37 : maximum
        return min(maximum, desired)
    }

    private var measuredHeight: CGFloat? { store.accounts.isEmpty || contentHeight > 0 ? popoverHeight : nil }
    var body: some View {
        VStack(spacing: 0) {
            if store.accounts.isEmpty {
                VStack(spacing: 14) {
                    Image(systemName: "chart.bar.xaxis").font(.system(size: 30)).foregroundStyle(.teal)
                    Text("Know what's left").font(.title3.weight(.semibold))
                    Text("Connect Claude, Codex or OpenCode.").foregroundStyle(.secondary)
                    Button("Add your first account") { showSettings() }.buttonStyle(.borderedProminent).tint(.teal)
                    Button("Preview with sample data") { store.showDemo() }.buttonStyle(.plain).font(.caption)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(store.accounts) { account in
                            AccountCard(account: account, snapshot: store.snapshots[account.id], error: store.errors[account.id], remaining: showRemaining)
                        }
                    }.padding(10).fixedSize(horizontal: false, vertical: true)
                        .background(GeometryReader { geometry in
                            Color.clear.onChange(of: geometry.size.height, initial: true) { _, height in contentHeight = height }
                        })
                }.frame(height: max(0, popoverHeight - 37))
            }
            Divider()
            HStack(spacing: 16) {
                if store.demo {
                    Text("Sample data").foregroundStyle(.orange)
                    Button("Exit demo") { store.leaveDemo() }.buttonStyle(.plain)
                } else if store.refreshing {
                    Text("Refreshing…").foregroundStyle(.secondary)
                }
                Spacer()
                Button { Task { await store.refresh() } } label: { HStack(spacing: 5) { Text("Refresh"); Image(systemName: "arrow.clockwise") } }
                    .help("Refresh all accounts").accessibilityLabel("Refresh all accounts")
                    .disabled(store.refreshing || store.demo)
                Button { showSettings() } label: { HStack(spacing: 5) { Text("Settings"); Image(systemName: "gearshape") } }
                    .help("Accounts and settings").accessibilityLabel("Accounts and settings")
            }.buttonStyle(.plain).font(.system(size: 12)).padding(.horizontal, 16).frame(height: 36)
        }
        .frame(width: 520, height: popoverHeight)
        .background(Color(nsColor: .windowBackgroundColor))
        .onChange(of: measuredHeight, initial: true) { _, height in
            if let height { heightChanged?(height) }
        }
    }
    private func showSettings() {
        if let settingsAction { settingsAction() }
        else { NSApp.activate(ignoringOtherApps: true); openSettings() }
    }
}

struct AccountCard: View {
    let account: Account
    let snapshot: UsageSnapshot?
    let error: String?
    let remaining: Bool
    @State private var expanded = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 5) {
                    Image(systemName: account.provider.symbol).foregroundStyle(account.provider.color)
                    Text(account.provider.title).foregroundStyle(.secondary)
                }.font(.system(size: 10))
                Text(account.name).font(.system(size: 12, weight: .semibold)).lineLimit(2).help(account.name)
                if let snapshot {
                    Text(snapshot.plan).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)

                }
                Button("Dashboard ↗") { NSWorkspace.shared.open(account.provider.dashboardURL) }
                    .buttonStyle(.plain).focusEffectDisabled().font(.system(size: 9)).foregroundStyle(.secondary)
                    .help("Open provider dashboard in your default browser")
            }.frame(width: 112, alignment: .leading)
            VStack(alignment: .leading, spacing: 9) {
                if let snapshot {
                    let primary = CompactLimits.primaryIndices(snapshot.windows)
                    let indices = expanded ? Array(snapshot.windows.indices) : primary
                    ForEach(indices, id: \.self) { index in
                        QuotaRow(window: snapshot.windows[index], remaining: remaining, tint: account.provider.color)
                    }
                    if snapshot.windows.count > primary.count {
                        Button(expanded ? "Show less" : "Show more (\(snapshot.windows.count - primary.count))") { expanded.toggle() }
                            .buttonStyle(.plain).font(.system(size: 10)).foregroundStyle(account.provider.color)
                    }
                    if let balance = snapshot.balance {
                        Text("Balance: " + balance.formatted(.currency(code: "USD"))).font(.system(size: 10))
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        if let resets = snapshot.resets {
                            Text("\(resets.available) banked \(resets.available == 1 ? "reset" : "resets")" + (resets.expirations.isEmpty ? "" : " · expires " + resets.expirations.map { $0.formatted(.dateTime.month(.abbreviated).day()) }.joined(separator: ", ")))
                                .font(.system(size: 9)).foregroundStyle(account.provider.color).fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                        updatedTime(snapshot).fixedSize(horizontal: true, vertical: false)
                    }
                    if let note = snapshot.note { Text(note).font(.system(size: 9)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
                } else if error == nil {
                    HStack { ProgressView().controlSize(.small); Text("Loading usage…").font(.caption).foregroundStyle(.secondary) }
                }
                if let error {
                    Label(error, systemImage: "exclamationmark.triangle").font(.system(size: 10)).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.07)))
    }
    private func updatedTime(_ snapshot: UsageSnapshot) -> some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let stale = error != nil || context.date.timeIntervalSince(snapshot.fetchedAt) > 600
            Text((stale ? "Stale · " : "") + (context.date.timeIntervalSince(snapshot.fetchedAt) < 60 ? "Just updated" : snapshot.fetchedAt.formatted(.relative(presentation: .numeric))))
                .font(.system(size: 9)).foregroundStyle(stale ? Color.orange : Color.secondary)
        }
    }
}
private struct QuotaRow: View {
    let window: QuotaWindow
    let remaining: Bool
    let tint: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            TimelineView(.periodic(from: .now, by: 60)) { context in
                Text(label + " - " + resetText(now: context.date))
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                    .lineLimit(1).minimumScaleFactor(0.85)
                    .help(window.resetsAt?.formatted(date: .complete, time: .shortened) ?? "Reset time unavailable")
            }
            HStack(spacing: 8) {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.primary.opacity(0.07))
                        Capsule().fill(window.used >= 90 ? Color.orange : tint)
                            .frame(width: geometry.size.width * min(100, max(0, remaining ? window.remaining : window.used)) / 100)
                    }
                }.frame(height: 6)
                Text((remaining ? window.remaining : window.used).formatted(.number.precision(.fractionLength(0...1))) + (remaining ? "% left" : "% used"))
                    .font(.system(size: 10, weight: .medium)).monospacedDigit().fixedSize().frame(width: 62, alignment: .trailing)
            }.accessibilityElement(children: .ignore)
                .accessibilityLabel("\(window.label), \(Int(remaining ? window.remaining : window.used)) percent \(remaining ? "remaining" : "used")")
        }
    }
    private var label: String { window.label == "5 hours" ? "5 Hours Limit" : window.label.lowercased().hasSuffix("limit") ? window.label : window.label + " Limit" }
    private func resetText(now: Date) -> String {
        guard let date = window.resetsAt else { return "reset time unavailable" }
        guard date > now else { return "reset due, refresh" }
        let minutes = max(1, Int(date.timeIntervalSince(now) / 60))
        if minutes >= 1440 { return "\(minutes / 1440)d \((minutes % 1440) / 60)h remaining" }
        if minutes >= 60 { return "\(minutes / 60)h \(minutes % 60)m remaining" }
        return "\(minutes) min remaining"
    }
}
