import AppKit
import SwiftUI
import MonitorCore

/// Keep provider-wide limits first; scoped/model limits stay behind Show more.
enum CompactLimits {
    static func primaryIndices(_ windows: [QuotaWindow]) -> [Int] {
        let primary = ["5 hours", "Weekly"].compactMap { label in
            windows.firstIndex { $0.label == label }
        }
        // Providers with only another period still need a useful default row.
        return primary.isEmpty ? Array(windows.indices.prefix(1)) : primary
    }
}
