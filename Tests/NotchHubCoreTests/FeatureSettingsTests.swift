import Foundation
import Testing
@testable import NotchHubCore

@Suite("FeatureSettings")
struct FeatureSettingsTests {

    @Test("defaults enable everything except weather")
    func defaultsExcludeWeather() {
        let s = FeatureSettings()
        for feature in Feature.allCases where feature != .weather {
            #expect(s.isEnabled(feature))
        }
        #expect(!s.isEnabled(Feature.weather))
    }

    @Test("setEnabled toggles membership")
    func setEnabledToggles() {
        var s = FeatureSettings()
        s.setEnabled(.music, enabled: false)
        #expect(!s.isEnabled(Feature.music))
        s.setEnabled(.music, enabled: true)
        #expect(s.isEnabled(Feature.music))
    }

    @Test("the enabled set round-trips through Codable")
    func codableRoundTrip() {
        var s = FeatureSettings()
        s.setEnabled(.music, enabled: false)
        s.setEnabled(.calendar, enabled: false)
        let data = try! JSONEncoder().encode(s)
        let decoded = try! JSONDecoder().decode(FeatureSettings.self, from: data)
        #expect(decoded == s)
        #expect(!decoded.isEnabled(Feature.music))
        #expect(!decoded.isEnabled(Feature.calendar))
        #expect(decoded.isEnabled(Feature.battery))
    }

    @Test("an empty enabled set disables every feature")
    func emptySetDisablesAll() {
        let s = FeatureSettings(enabled: [])
        for feature in Feature.allCases {
            #expect(!s.isEnabled(feature))
        }
    }
}
