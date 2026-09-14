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
    case dictation
    case fileSharing
    case privacy
    case codingAgent
    /// Details about the frontmost app: browser tabs, agent sessions, window titles.
    case appDetails
}

/// Which features are currently enabled, persisted to `UserDefaults`.
public struct FeatureSettings: Codable, Equatable {

    public private(set) var enabled: Set<Feature>

    public init(enabled: Set<Feature> = FeatureSettings.defaultEnabled) {
        self.enabled = enabled
    }

    /// Everything on except weather, which needs a configured city and network.
    public static var defaultEnabled: Set<Feature> {
        Set(Feature.allCases).subtracting([.weather])
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
    static let originalFeatures: Set<Feature> = Set(Feature.allCases).subtracting([.appDetails])

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        var enabled = try container.decode(Set<Feature>.self, forKey: .enabled)
        let known = try container.decodeIfPresent(Set<Feature>.self, forKey: .known) ?? Self.originalFeatures
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
