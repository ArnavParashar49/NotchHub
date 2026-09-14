import Foundation
import NotchHubCore

/// Fetches current conditions for the configured city.
///
/// Uses Open-Meteo, which needs no API key and no account — the right default
/// for a utility that must work on a fresh install. The listener is idle until
/// a city is configured: with no city there is nothing to fetch, so it does no
/// network work at all (exactly what the settings contract requires).
///
/// Refresh is deliberately slow (every 30 minutes). Weather changes on the
/// scale of hours, not seconds; polling harder would be background work with
/// nothing to show for it.
public final class WeatherListener: SystemListener {

    private let emit: (SystemEvent) -> Void
    private var timer: Timer?
    private var task: Task<Void, Never>?
    private let refreshInterval: TimeInterval

    public init(refreshInterval: TimeInterval = 30 * 60, emit: @escaping (SystemEvent) -> Void) {
        self.emit = emit
        self.refreshInterval = refreshInterval
    }

    public var name: String { "Weather" }

    public func start() {
        stop()
        // No city configured means the feature is off — no timer, no request.
        guard Self.configuredCity() != nil else { return }

        let timer = Timer(timeInterval: refreshInterval, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        refresh()
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
        task?.cancel()
        task = nil
    }

    // MARK: - Configuration

    /// The city the user configured, or nil when the feature is effectively off.
    public static func configuredCity() -> String? {
        let raw = UserDefaults.standard.string(forKey: "NotchHub.weatherCity") ?? ""
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    // MARK: - Fetch

    private func refresh() {
        guard let city = Self.configuredCity() else { return }
        task?.cancel()
        task = Task { [weak self] in
            guard let self else { return }
            guard let place = await Self.geocode(city) else { return }
            guard let reading = await Self.fetch(place) else { return }
            guard !Task.isCancelled else { return }
            self.emit(SystemEvent(source: .weather, payload: .weather(
                temperature: reading.temperature,
                condition: reading.condition,
                symbol: reading.symbol
            )))
        }
    }

    private struct Place {
        let name: String
        let latitude: Double
        let longitude: Double
    }

    private struct Reading {
        let temperature: Double
        let condition: String
        let symbol: String
    }

    /// Resolves a city name to coordinates via Open-Meteo's geocoder.
    private static func geocode(_ city: String) async -> Place? {
        var components = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")
        components?.queryItems = [
            URLQueryItem(name: "name", value: city),
            URLQueryItem(name: "count", value: "1"),
            URLQueryItem(name: "language", value: "en"),
            URLQueryItem(name: "format", value: "json"),
        ]
        guard let url = components?.url else { return nil }
        guard let data = await get(url) else { return nil }

        struct Response: Decodable {
            struct Result: Decodable {
                let name: String
                let latitude: Double
                let longitude: Double
            }
            let results: [Result]?
        }
        guard let decoded = try? JSONDecoder().decode(Response.self, from: data),
              let first = decoded.results?.first else { return nil }
        return Place(name: first.name, latitude: first.latitude, longitude: first.longitude)
    }

    /// Reads current conditions for a resolved place.
    private static func fetch(_ place: Place) async -> Reading? {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")
        components?.queryItems = [
            URLQueryItem(name: "latitude", value: String(place.latitude)),
            URLQueryItem(name: "longitude", value: String(place.longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,weather_code"),
            URLQueryItem(name: "temperature_unit", value: "celsius"),
        ]
        guard let url = components?.url else { return nil }
        guard let data = await get(url) else { return nil }

        struct Response: Decodable {
            struct Current: Decodable {
                let temperature_2m: Double
                let weather_code: Int
            }
            let current: Current
        }
        guard let decoded = try? JSONDecoder().decode(Response.self, from: data) else { return nil }
        let (condition, symbol) = Self.describe(code: decoded.current.weather_code)
        return Reading(temperature: decoded.current.temperature_2m, condition: condition, symbol: symbol)
    }

    /// A short-lived GET. Weather is a nicety; on any failure the listener
    /// simply emits nothing rather than surfacing an error on the island.
    private static func get(_ url: URL) async -> Data? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.cachePolicy = .reloadIgnoringLocalCacheData
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return nil
            }
            return data
        } catch {
            return nil
        }
    }

    /// Maps a WMO weather code to a human condition and an SF Symbol.
    static func describe(code: Int) -> (condition: String, symbol: String) {
        switch code {
        case 0:
            return ("Clear", "sun.max.fill")
        case 1:
            return ("Mostly Clear", "sun.max.fill")
        case 2:
            return ("Partly Cloudy", "cloud.sun.fill")
        case 3:
            return ("Overcast", "cloud.fill")
        case 45, 48:
            return ("Fog", "cloud.fog.fill")
        case 51, 53, 55, 56, 57:
            return ("Drizzle", "cloud.drizzle.fill")
        case 61, 63, 65, 66, 67:
            return ("Rain", "cloud.rain.fill")
        case 71, 73, 75, 77:
            return ("Snow", "cloud.snow.fill")
        case 80, 81, 82:
            return ("Showers", "cloud.heavyrain.fill")
        case 85, 86:
            return ("Snow Showers", "cloud.snow.fill")
        case 95, 96, 99:
            return ("Thunderstorm", "cloud.bolt.rain.fill")
        default:
            return ("—", "cloud.fill")
        }
    }
}
