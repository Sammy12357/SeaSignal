import Foundation

enum ForecastTimelineBuilder {
    static func build(weather: WeatherDataset, marine: MarineDataset?, tides: TideDataset?) -> ForecastTimeline {
        let calendar = Calendar(identifier: .gregorian)
        var hours = weather.hours.map { hour -> HourlyConditions in
            var merged = hour
            let key = calendar.dateInterval(of: .hour, for: hour.time)?.start ?? hour.time
            if let marineValue = marine?.valuesByTime[key] {
                merged.waveHeightM = marineValue.waveHeightM
                merged.wavePeriodSeconds = marineValue.wavePeriodSeconds
                merged.swellHeightM = marineValue.swellHeightM
                if tides == nil { merged.tideHeightM = marineValue.modeledSeaLevelM }
            }
            if let tideHeight = tides?.hourlyHeights[key] {
                merged.tideHeightM = tideHeight
            }
            return merged
        }

        let now = Date().addingTimeInterval(-60 * 60)
        hours = hours.filter { $0.time >= now }.sorted { $0.time < $1.time }
        let source = tides.map { "NOAA station: \($0.station.name)" }
            ?? (marine == nil ? "Tides unavailable" : "Modeled water level — not for navigation")
        return ForecastTimeline(
            timezoneIdentifier: weather.timezoneIdentifier,
            hours: hours,
            tideEvents: tides?.events ?? [],
            tideSource: source,
            fetchedAt: min(weather.fetchedAt, marine?.fetchedAt ?? weather.fetchedAt),
            isStale: weather.isStale || (marine?.isStale ?? false)
        )
    }
}

