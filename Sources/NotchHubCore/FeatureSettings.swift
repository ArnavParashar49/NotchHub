import Foundation

/// A single toggleable capability of NotchHub.
///
/// Every feature in the spec maps to a toggle. A disabled feature must not
/// create a listener or any background work — the monitor consults these
/// settings before registering anything.
public enum Feature: String, CaseIterable, Codable {
    case music
    case volume
    case brightness
    case battery
    case airpods
    case bluetooth
    case timers
    case downloads
    case notifications
    case calendar
    case meetings
    case focus
    case weather
    case clipboard
    case fileSharing
    case privacy
    case codingAgent
    /// Details about the frontmost app: browser tabs, agent sessions, window titles.
    case appDetails
    /// A script that scrolls itself past the notch while you read.
    case teleprompter
    /// A live camera preview in the notch.
    case camera
    /// Hide the island from screen sharing and recordings.
    case ghostMode
    /// NEO, the voice assistant, living in the notch: its orb and what it
    /// hears and says, left of the notch while it is busy.
    case neo
}

/// Which features are currently enabled, persisted to `UserDefaults`.
public struct FeatureSettings: Codable, Equatable {

    public private(set) var enabled: Set<Feature>

    public init(enabled: Set<Feature> = FeatureSettings.defaultEnabled) {
        self.enabled = enabled
    }

    /// Everything on except weather, which needs a configured city and network,
    /// and Ghost Mode, which HIDES things — a feature that makes the island
    /// invisible has to be asked for, never arrive switched on.
    public static var defaultEnabled: Set<Feature> {
        Set(Feature.allCases).subtracting([.weather, .ghostMode])
    }

    public func isEnabled(_ feature: Feature) -> Bool {
        enabled.contains(feature)
    }

    public mutating func setEnabled(_ feature: Feature, enabled: Bool) {
        if enabled {
            self.enabled.insert(feature)
        } else {
            self.enabled.remove(feature)
        }
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case enabled
        case known
    }

    /// Features that existed before settings recorded which features they
    /// knew about. A feature added since is switched on by default for an
    /// existing install, instead of reading as "turned off".
    static let originalFeatures: Set<Feature> = Set(Feature.allCases)
        .subtracting([.appDetails, .teleprompter, .camera, .ghostMode, .neo])

    /// Decoded through RAW STRINGS, dropping any name this build no longer has.
    ///
    /// Decoding straight into `Set<Feature>` throws on the first unrecognised
    /// name, and `load()` answers a throw by falling back to the defaults — so
    /// removing a single feature from the app would silently reset every
    /// setting the user had ever chosen, on their next launch, with no way to
    /// get them back. A name this build does not know is simply not a feature
    /// any more; it is dropped and everything else is kept.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let storedEnabled = try container.decode(Set<String>.self, forKey: .enabled)
        var enabled = Set(storedEnabled.compactMap(Feature.init(rawValue:)))

        let storedKnown = try container.decodeIfPresent(Set<String>.self, forKey: .known)
        let known = storedKnown.map { Set($0.compactMap(Feature.init(rawValue:))) } ?? Self.originalFeatures

        // A feature added since these settings were written is switched on by
        // default rather than reading as "turned off".
        for feature in Feature.allCases where !known.contains(feature) && Self.defaultEnabled.contains(feature) {
            enabled.insert(feature)
        }
        self.enabled = enabled
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(enabled, forKey: .enabled)
        try container.encode(Set(Feature.allCases), forKey: .known)
    }

    // MARK: - Persistence

    private static let defaultsKey = "NotchHub.featureSettings"

    /// Loads settings from `UserDefaults`, falling back to the defaults when
    /// nothing is stored or the stored value cannot be decoded.
    public static func load() -> FeatureSettings {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey) else {
            return FeatureSettings()
        }
        return (try? JSONDecoder().decode(FeatureSettings.self, from: data)) ?? FeatureSettings()
    }

    /// Persists the current settings to `UserDefaults`.
    public func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: Self.defaultsKey)
    }
}
