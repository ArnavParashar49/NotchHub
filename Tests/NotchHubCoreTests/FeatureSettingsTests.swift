import Foundation
import Testing
@testable import NotchHubCore

@Suite("FeatureSettings")
struct FeatureSettingsTests {

    @Test("defaults enable everything except the two that must be asked for")
    func defaultsExcludeOptIns() {
        // Weather needs a city and a network before it can say anything, and
        // Ghost Mode HIDES the island — a feature that makes the app invisible
        // must never arrive switched on, or someone finds out it exists by
        // wondering where their notch went.
        let optIn: Set<Feature> = [.weather, .ghostMode]
        let s = FeatureSettings()
        for feature in Feature.allCases where !optIn.contains(feature) {
            #expect(s.isEnabled(feature), "\(feature) should be on by default")
        }
        for feature in optIn {
            #expect(!s.isEnabled(feature), "\(feature) should be off by default")
        }
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

extension FeatureSettingsTests {

    /// Settings as they are actually stored, so a decode can be tested against
    /// names this build may no longer have.
    private func stored(enabled: [String], known: [String]) throws -> FeatureSettings {
        let json = try JSONSerialization.data(withJSONObject: ["enabled": enabled, "known": known])
        return try JSONDecoder().decode(FeatureSettings.self, from: json)
    }

    @Test("settings written by a build with an EXTRA feature still load")
    func unknownFeatureNamesAreDropped() throws {
        // The hazard: remove one feature from the app and every install that
        // had it stored would fail to decode, fall back to the defaults, and
        // silently lose every choice the user had made. An unrecognised name is
        // just not a feature any more — drop it, keep the rest.
        let settings = try stored(
            enabled: ["music", "removedFeature", "clipboard", "somethingFromTheFuture"],
            known: Feature.allCases.map(\.rawValue) + ["removedFeature"]
        )
        #expect(settings.isEnabled(.music))
        #expect(settings.isEnabled(.clipboard))
        // And the user's OFF choices survive too — the point of the exercise.
        #expect(!settings.isEnabled(.battery))
        #expect(!settings.isEnabled(.weather))
    }

    @Test("a feature added since the settings were written arrives switched on")
    func newFeaturesDefaultOn() throws {
        // `known` is what the writing build understood. Anything missing from
        // it is new, so it takes its default rather than reading as "off".
        let settings = try stored(enabled: ["music"], known: ["music", "clipboard"])
        #expect(settings.isEnabled(.music))
        #expect(!settings.isEnabled(.clipboard), "a known feature left out of `enabled` stays off")
        #expect(settings.isEnabled(.timers), "a feature the writer never knew about should default on")
        // …unless its default is off.
        #expect(!settings.isEnabled(.ghostMode))
        #expect(!settings.isEnabled(.weather))
    }
}
