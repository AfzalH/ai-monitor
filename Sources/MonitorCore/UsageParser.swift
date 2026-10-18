import Foundation
import CoreFoundation

public enum UsageParser {
    static func object(_ data: Data) throws -> [String: Any] {
        guard let value = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw MonitorError.invalidPayload }
        return value
    }
    static func number(_ value: Any?) -> Double? {
        if let value = value as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID() {
            return value.doubleValue.isFinite ? value.doubleValue : nil
        }
        if let value = value as? String, let n = Double(value), n.isFinite { return n }
        return nil
    }
    static func date(_ value: Any?) -> Date? {
        if let raw = value as? String {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: raw) { return date }
            formatter.formatOptions = [.withInternetDateTime]
            return formatter.date(from: raw)
        }
        if let n = number(value), n > 0 { return Date(timeIntervalSince1970: n > 1e12 ? n / 1000 : n) }
        return nil
    }
    private static func window(_ label: String, value: Any?, percentKey: String, resetKey: String) -> QuotaWindow? {
        guard let row = value as? [String: Any], let used = number(row[percentKey]), used >= 0 else { return nil }
        return QuotaWindow(label, used: used, resetsAt: date(row[resetKey]))
    }
    public static func parse(_ data: Data, provider: Provider, now: Date = Date()) throws -> UsageSnapshot {
        let root = try object(data)
        var windows: [QuotaWindow] = []
        var plan = provider.title
        switch provider {
        case .claude:
            for (key, label) in [("five_hour", "5 hours"), ("seven_day", "Weekly"), ("seven_day_sonnet", "Sonnet · Weekly"), ("seven_day_opus", "Opus · Weekly"), ("seven_day_oauth_apps", "OAuth apps · Weekly")] {
                if let w = window(label, value: root[key], percentKey: "utilization", resetKey: "resets_at") { windows.append(w) }
            }
            for limit in root["limits"] as? [[String: Any]] ?? [] {
                let model = ((limit["scope"] as? [String: Any])?["model"] as? [String: Any])?["display_name"] as? String
                let kind = limit["kind"] as? String ?? ""
                let period: String
                switch kind.lowercased() {
                case "session", "five_hour": period = "5 hours"
                case "weekly_all", "weekly_scoped", "seven_day": period = "Weekly"
                default: period = kind.replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: "-", with: " ").capitalized
                }
                let scope = model?.trimmingCharacters(in: .whitespacesAndNewlines)
                let scopeLabel = scope?.isEmpty == false ? scope : kind.lowercased() == "weekly_scoped" ? "Scoped" : nil
                let label = [scopeLabel, period.isEmpty ? nil : period].compactMap { $0 }.joined(separator: " · ")
                guard !label.isEmpty, !windows.contains(where: { $0.label == label }),
                      let w = window(label, value: limit, percentKey: "percent", resetKey: "resets_at") else { continue }
                // Replace a matching legacy model-family row with its more
                // descriptive model name. Different quotas stay separate.
                let family = scope?.lowercased().replacingOccurrences(of: "claude ", with: "").split(separator: " ").first.map(String.init)
                if kind.lowercased() == "weekly_scoped", let family, ["sonnet", "opus"].contains(family),
                   let index = windows.firstIndex(where: { $0.label == family.capitalized + " · Weekly" && $0.used == w.used && $0.resetsAt == w.resetsAt }) {
                    windows[index] = w
                } else { windows.append(w) }
            }
        case .codex:
            plan = (root["plan_type"] as? String)?.replacingOccurrences(of: "_", with: " ").capitalized ?? "ChatGPT"
            func appendLimits(_ limits: [String: Any], prefix: String = "") {
                for key in ["primary_window", "secondary_window"] {
                    guard let row = limits[key] as? [String: Any] else { continue }
                    let seconds = number(row["limit_window_seconds"])
                    let label: String
                    switch seconds {
                    case 18000: label = "5 hours"
                    case 604800: label = "Weekly"
                    case 86400: label = "Daily"
                    case .some(let seconds): label = "\(Int(seconds / 3600)) hours"
                    default: label = key == "primary_window" ? "Primary limit" : "Secondary limit"
                    }
                    if let w = window(prefix + label, value: row, percentKey: "used_percent", resetKey: "reset_at") { windows.append(w) }
                }
            }
            if let limits = root["rate_limit"] as? [String: Any] { appendLimits(limits) }
            for extra in root["additional_rate_limits"] as? [[String: Any]] ?? [] {
                if let limits = extra["rate_limit"] as? [String: Any] { appendLimits(limits, prefix: (extra["limit_name"] as? String ?? "Model") + " · ") }
            }
        case .opencode:
            guard let usage = root["usage"] as? [String: Any] else { throw MonitorError.invalidPayload }
            plan = "Go"
            for (key, label) in [("rolling", "5 hours"), ("weekly", "Weekly"), ("monthly", "Monthly")] {
                guard let row = usage[key] as? [String: Any], let used = number(row["percent"]), used >= 0 else { continue }
                var reset = date(row["resetsAt"] ?? row["resetAt"] ?? row["reset_at"])
                if reset == nil, let seconds = number(row["resetInSec"]), seconds >= 0 { reset = now.addingTimeInterval(seconds) }
                windows.append(QuotaWindow(label, used: used, resetsAt: reset))
            }
        }
        guard !windows.isEmpty else { throw MonitorError.invalidPayload }
        return UsageSnapshot(plan: plan, windows: windows)
    }
    public static func resets(_ data: Data) throws -> ResetCredits {
        let root = try object(data)
        guard let count = number(root["available_count"]), count >= 0, count <= 10000, count.rounded() == count,
              let credits = root["credits"] as? [[String: Any]] else { throw MonitorError.invalidPayload }
        let dates = credits.filter { $0["status"] as? String == "available" }.compactMap { date($0["expires_at"]) }.sorted()
        return ResetCredits(available: Int(count), expirations: dates)
    }
    public static func console(_ data: Data) throws -> UsageSnapshot {
        let root = try object(data)
        guard let access = root["access"] as? [String: Any], let meters = access["meters"] as? [String: Any] else { throw MonitorError.invalidPayload }
        var windows: [QuotaWindow] = []
        for (key, label) in [("fiveHour", "5 hours"), ("week", "Weekly"), ("month", "Monthly")] {
            guard let row = meters[key] as? [String: Any], let used = number(row["usedMicroCents"]), used >= 0,
                  let limit = number(row["limitMicroCents"]), limit > 0 else { continue }
            let reset = date(row["resetsAt"]) ?? (key == "month" ? date(access["endsAt"]) : nil)
            windows.append(QuotaWindow(label, used: used / limit * 100, resetsAt: reset))
        }
        guard !windows.isEmpty else { throw MonitorError.invalidPayload }
        return UsageSnapshot(plan: "Go", windows: windows)
    }
}
