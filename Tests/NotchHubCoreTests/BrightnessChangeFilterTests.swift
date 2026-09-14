import Foundation
import Testing
@testable import NotchHubCore

@Suite("BrightnessChangeFilter")
struct BrightnessChangeFilterTests {

    @Test("the first reading only seeds the baseline")
    func firstReadingIsSilent() {
        var filter = BrightnessChangeFilter()
        #expect(filter.accept(0.62) == nil)
    }

    @Test("auto-brightness drift is never announced")
    func driftIsIgnored() {
        var filter = BrightnessChangeFilter()
        var level = 0.50
        _ = filter.accept(level)
        for _ in 0..<200 {
            level += 0.004 // a slow ambient ramp: +80% over time, tiny per poll
            #expect(filter.accept(min(1, level)) == nil)
        }
    }

    @Test("a brightness key step is announced")
    func keyStepIsReported() {
        var filter = BrightnessChangeFilter()
        _ = filter.accept(0.5)
        #expect(filter.accept(0.5625) == 0.5625)
        #expect(filter.accept(0.5) == 0.5)
    }

    @Test("a step split across two polls is reported once it lands")
    func splitStep() {
        var filter = BrightnessChangeFilter()
        _ = filter.accept(0.5)
        #expect(filter.accept(0.51) == nil)
        #expect(filter.accept(0.5625) == 0.5625)
        #expect(filter.accept(0.5625) == nil)
    }
}

@Suite("Transient refocus")
struct TransientRefocusTests {

    @Test("a repeated transient of the same kind updates in place and restarts its lifetime")
    func repeatedTransientKeepsIdentity() {
        let queue = ActivityQueue()
        let first = Activity.brightness(0.5)
        queue.focusTemporarily(first)
        let later = Date().addingTimeInterval(1.0)
        queue.focusTemporarily(Activity(kind: .brightness, title: "Brightness", progress: 0.56, createdAt: later))
        #expect(queue.all.count == 1)
        #expect(queue.current?.id == first.id)
        #expect(queue.current?.progress == 0.56)
        // Still alive past the FIRST activity's lifetime, because it restarted.
        #expect(queue.tick(now: first.createdAt.addingTimeInterval(first.autoDismiss + 0.2)).isEmpty)
    }
}
