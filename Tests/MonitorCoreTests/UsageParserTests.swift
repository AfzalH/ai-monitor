import Testing
import Foundation
@testable import MonitorCore

private func data(_ text: String) -> Data { Data(text.utf8) }
@Test func goPercentIsNotAFraction() throws {
    let usage = try UsageParser.parse(data(#"{"usage":{"rolling":{"percent":0.5,"resetInSec":600},"weekly":{"percent":1},"monthly":{"percent":80}}}"#), provider: .opencode, now: Date(timeIntervalSince1970: 1000))
    #expect(usage.windows.map(\.used) == [0.5, 1, 80])
    #expect(usage.windows[0].resetsAt == Date(timeIntervalSince1970: 1600))
    #expect(usage.windows[1].resetsAt == nil)
}
@Test func codexUsesActualWindowDuration() throws {
    let usage = try UsageParser.parse(data(#"{"plan_type":"pro","rate_limit":{"primary_window":{"used_percent":12,"reset_at":1900000000,"limit_window_seconds":604800}},"additional_rate_limits":[{"limit_name":"Spark","rate_limit":{"primary_window":{"used_percent":42,"limit_window_seconds":18000}}}]}"#), provider: .codex)
    #expect(usage.windows.map(\.label) == ["Weekly", "Spark · 5 hours"])
    #expect(usage.windows.map(\.used) == [12, 42])
    #expect(usage.plan == "Pro")
}
@Test func claudePreservesMissingWindowsAndScopedLimits() throws {
    let usage = try UsageParser.parse(data(#"{"five_hour":{"utilization":28,"resets_at":"2026-10-18T18:00:00Z"},"seven_day":null,"limits":[{"kind":"weekly","percent":61,"scope":{"model":{"display_name":"Sonnet"}}}]}"#), provider: .claude)
    #expect(usage.windows.count == 2)
    #expect(usage.windows[0].remaining == 72)
    #expect(usage.windows[1].used == 61)
}
@Test func malformedUsageNeverBecomesZero() {
    for provider in Provider.allCases {
        #expect(throws: (any Error).self) { try UsageParser.parse(data(#"{"error":"unauthorized"}"#), provider: provider) }
    }
}
@Test func resetCountAndExpiryAreSeparateFromUsage() throws {
    let resets = try UsageParser.resets(data(#"{"available_count":2,"credits":[{"status":"available","expires_at":"2026-11-01T00:00:00Z"},{"status":"redeemed","expires_at":"2026-10-20T00:00:00Z"},{"status":"available","expires_at":null}]}"#))
    #expect(resets.available == 2)
    #expect(resets.expirations.count == 1)
}
@Test func consoleMicrocentsAndMonthlyResetFallback() throws {
    let usage = try UsageParser.console(data(#"{"access":{"endsAt":"2026-11-01T00:00:00Z","meters":{"fiveHour":{"usedMicroCents":"250","limitMicroCents":"1000"},"month":{"usedMicroCents":"500","limitMicroCents":"2000","resetsAt":null}}}}"#))
    #expect(usage.windows.map(\.used) == [25,25])
    #expect(usage.windows[0].resetsAt == nil)
    #expect(usage.windows[1].resetsAt != nil)
}

@Test func claudeHumanizesKindsAndMergesLegacyDuplicates() throws {
    let json = #"{"five_hour":{"utilization":6},"seven_day":{"utilization":1},"limits":[{"kind":"session","percent":6},{"kind":"weekly_all","percent":1},{"kind":"weekly_scoped","percent":0,"scope":{"model":{"display_name":"Fable"}}},{"kind":"monthly_extra","percent":2}]}"#
    let snapshot = try UsageParser.parse(Data(json.utf8), provider: .claude)
    #expect(snapshot.windows.map(\.label) == ["5 hours", "Weekly", "Fable · Weekly", "Monthly Extra"])
    let modern = try UsageParser.parse(Data(#"{"limits":[{"kind":"session","percent":6},{"kind":"weekly_all","percent":1}]}"#.utf8), provider: .claude)
    #expect(modern.windows.map(\.label) == ["5 hours", "Weekly"])
}

@Test func claudeScopedRowsCannotReplaceAccountWideWeekly() throws {
    let data = Data(#"{"seven_day_opus":{"utilization":4},"limits":[{"kind":"weekly_scoped","percent":30},{"kind":"weekly_all","percent":8},{"kind":"weekly_scoped","percent":4,"scope":{"model":{"display_name":"Claude Opus 4"}}}]}"#.utf8)
    let windows = try UsageParser.parse(data, provider: .claude).windows
    #expect(windows.first(where: { $0.label == "Weekly" })?.used == 8)
    #expect(windows.first(where: { $0.label == "Scoped · Weekly" })?.used == 30)
    #expect(windows.filter { $0.label.contains("Opus") }.map(\.label) == ["Claude Opus 4 · Weekly"])
}
