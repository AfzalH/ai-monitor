import AppKit
import SwiftUI
import MonitorCore

/// Keep provider-wide limits first and show up to three bars by default; additional limits stay behind Show more.
enum CompactLimits {
    static let defaultVisibleCount = 3

    static func primaryIndices(_ windows: [QuotaWindow]) -> [Int] {
        var indices: [Int] = []
        for label in ["5 hours", "Weekly", "Monthly"] {
            if let index = windows.firstIndex(where: { $0.label == label }), !indices.contains(index) {
                indices.append(index)
                if indices.count == defaultVisibleCount { return indices }
            }
        }
        for index in windows.indices where !indices.contains(index) {
            indices.append(index)
            if indices.count == defaultVisibleCount { break }
        }
        return indices
    }
}
