import NotchHubCore
import SwiftUI

/// A weather snapshot for the island.
///
/// Plain value model — the app supplies the current reading and a short
/// forecast; this view only renders it.
struct Weather {
    let temp: Int
    let condition: String
    let symbol: String
    let forecast: [String]
    let city: String
}

/// The optional weather surface.
///
/// Compact: a single accent sun/condition glyph with the temperature. Expanded:
/// the current reading, its condition, and a short forecast list. Sharp corners,
/// accent reserved for the condition glyph so the surface stays quiet.
struct WeatherView: View {
    let weather: Weather
    let isExpanded: Bool

    init(weather: Weather, isExpanded: Bool) {
        self.weather = weather
        self.isExpanded = isExpanded
    }

    var body: some View {
        HStack(spacing: DesignTokens.space12) {
            Image(systemName: weather.symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(DesignTokens.accent)
                .frame(width: 34, height: 34)
                .background(DesignTokens.chipFill, in: RoundedRectangle(cornerRadius: DesignTokens.radiusChip, style: .continuous))

            VStack(alignment: .leading, spacing: DesignTokens.space2) {
                Text("\(weather.temp)°")
                    .font(DesignTokens.numericFont)
                    .foregroundStyle(DesignTokens.textPrimary)
                if isExpanded {
                    Text(weather.condition)
                        .font(DesignTokens.subtitleFont)
                        .foregroundStyle(DesignTokens.textSecondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if isExpanded {
                forecastList
            }
        }
        .padding(.horizontal, DesignTokens.contentInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var forecastList: some View {
        VStack(alignment: .trailing, spacing: DesignTokens.space2) {
            Text(weather.city)
                .font(DesignTokens.subtitleFont)
                .foregroundStyle(DesignTokens.textTertiary)
                .lineLimit(1)
            ForEach(weather.forecast, id: \.self) { line in
                Text(line)
                    .font(DesignTokens.subtitleFont)
                    .foregroundStyle(DesignTokens.textSecondary)
                    .lineLimit(1)
            }
        }
    }
}
