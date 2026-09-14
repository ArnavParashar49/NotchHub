import Testing
@testable import NotchHubCore

@Suite("AppStripLabel")
struct AppStripLabelTests {

    @Test("the app's own name is dropped from a window title")
    func dropsAppName() {
        #expect(AppStripLabel.windowTitle("Report.pdf — Preview", appName: "Preview") == "Report.pdf")
        #expect(AppStripLabel.windowTitle("Slack | general", appName: "Slack") == "general")
        #expect(AppStripLabel.windowTitle("NotchHub - Visual Studio Code", appName: "Visual Studio Code") == "NotchHub")
    }

    @Test("a web address becomes its site; a path becomes its file")
    func shortensAddresses() {
        #expect(AppStripLabel.windowTitle("https://www.youtube.com/watch?v=abc123&list=xyz", appName: "Some App") == "youtube.com")
        #expect(AppStripLabel.windowTitle("/Users/a/Documents/NotchHub/README.md", appName: "TextEdit") == "README.md")
    }

    @Test("nothing useful left means no label")
    func emptyOrJustTheApp() {
        #expect(AppStripLabel.windowTitle("   ", appName: "Finder") == nil)
        #expect(AppStripLabel.windowTitle("Finder", appName: "Finder") == nil)
    }
}
