import Testing
import MonitorCore
@testable import AIMonitor

@Test func compactLimitsPreferAccountWideFiveHourAndWeek() {
    let windows = [QuotaWindow("Sonnet · Weekly", used: 9), QuotaWindow("Monthly", used: 10), QuotaWindow("Weekly", used: 2), QuotaWindow("5 hours", used: 3)]
    #expect(CompactLimits.primaryIndices(windows) == [3, 2])
    #expect(CompactLimits.primaryIndices([QuotaWindow("Weekly", used: 2), QuotaWindow("Monthly", used: 4)]) == [0])
    #expect(CompactLimits.primaryIndices([QuotaWindow("Monthly", used: 4)]) == [0])
    #expect(CompactLimits.primaryIndices([]).isEmpty)
}


import AppKit

@Test func popoutCentersAndClampsToEitherScreenEdge() {
    let screen = NSRect(x: 100, y: 50, width: 1200, height: 800)
    let size = NSSize(width: 520, height: 300)
    func frame(_ x: CGFloat) -> NSRect {
        PopoutPlacement.frame(size: size, anchor: NSRect(x: x, y: 850, width: 60, height: 24), screen: screen)
    }
    #expect(frame(600).midX == 630)
    #expect(frame(1250).maxX == screen.maxX)
    #expect(frame(100).minX == screen.minX)
    #expect(frame(600).maxY == screen.maxY)
}
