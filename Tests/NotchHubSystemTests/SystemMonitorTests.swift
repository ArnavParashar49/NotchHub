import Testing
import NotchHubCore
@testable import NotchHubSystem

@Suite("SystemMonitor")
struct SystemMonitorTests {

    @Test("a settings change touches only the listeners it affects")
    func incrementalUpdate() {
        let monitor = SystemMonitor.defaultMonitor(settings: FeatureSettings())
        let before = monitor.listenerNames

        var noCalendar = FeatureSettings()
        noCalendar.setEnabled(.calendar, enabled: false)
        let changes = monitor.update(settings: noCalendar)
        #expect(changes == SystemMonitor.Changes(added: 0, removed: 1))
        #expect(!monitor.listenerNames.contains("CalendarListener"))
        #expect(monitor.listenerNames.count == before.count - 1)

        // Unchanged settings do nothing at all.
        #expect(monitor.update(settings: noCalendar) == SystemMonitor.Changes(added: 0, removed: 0))

        // Coding Agent is part of the app-details listener's configuration.
        var noAgents = noCalendar
        noAgents.setEnabled(.codingAgent, enabled: false)
        #expect(monitor.update(settings: noAgents) == SystemMonitor.Changes(added: 1, removed: 2))
    }

    @Test("the default monitor's listeners follow the spec order")
    func stableOrder() {
        let names = SystemMonitor.defaultMonitor(settings: FeatureSettings()).listenerNames
        #expect(names.first == "SystemEventListener")
        #expect(names.last == "FrontmostApp")
    }
}
