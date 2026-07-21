import Foundation

struct RecommendationEngine: Sendable {
    func recommendations(
        for timeline: ForecastTimeline,
        preferences: AppPreferences,
        now: Date = Date()
    ) -> [Recommendation] {
        let future = timeline.hours.filter { $0.time >= now.addingTimeInterval(-30 * 60) }
        let length = max(2, preferences.tripLengthHours)
        guard future.count >= length else { return [] }

        var results: [Recommendation] = []
        for startIndex in 0...(future.count - length) {
            let slice = Array(future[startIndex..<(startIndex + length)])
            guard isContiguous(slice), slice.allSatisfy({ passesHardLimits($0, preferences: preferences) }) else { continue }

            let start = slice[0].time
            let end = slice.last!.time.addingTimeInterval(60 * 60)
            let tideScore = tideAlignmentScore(
                start: start,
                end: end,
                events: timeline.tideEvents,
                windowMinutes: preferences.highTideWindowMinutes
            )
            if preferences.requireHighTide, !timeline.tideEvents.isEmpty, tideScore < 0.5 { continue }

            let hourlyScores = slice.map { score($0, preferences: preferences) }
            let base = hourlyScores.reduce(0, +) / Double(hourlyScores.count)
            let weakest = hourlyScores.min() ?? 0
            let tideWeight = timeline.tideEvents.isEmpty ? 0 : 0.15
            let overall = min(1, max(0, base * (1 - tideWeight) + tideScore * tideWeight - (1 - weakest) * 0.08))

            results.append(Recommendation(
                id: UUID(),
                start: start,
                end: end,
                score: overall,
                rationale: rationale(for: slice, timeline: timeline, preferences: preferences, tideScore: tideScore),
                weakestCondition: weakestReason(for: slice, preferences: preferences)
            ))
        }

        return results
            .sorted {
                if abs($0.score - $1.score) > 0.001 { return $0.score > $1.score }
                return $0.start < $1.start
            }
            .prefix(10)
            .map { $0 }
    }

    private func passesHardLimits(_ hour: HourlyConditions, preferences: AppPreferences) -> Bool {
        guard let wind = hour.windSpeedKPH, let gust = hour.windGustKPH else { return false }
        if wind > preferences.maxWindKPH || gust > preferences.maxGustKPH { return false }
        if let wave = hour.waveHeightM, wave > preferences.maxWaveM { return false }
        if let rain = hour.precipitationProbability, rain > preferences.maxRainProbability { return false }
        if preferences.requireDaylight, hour.isDaylight == false { return false }
        return true
    }

    private func score(_ hour: HourlyConditions, preferences: AppPreferences) -> Double {
        var factors: [Double] = []
        if let wind = hour.windSpeedKPH { factors.append(limitScore(wind, limit: preferences.maxWindKPH)) }
        if let gust = hour.windGustKPH { factors.append(limitScore(gust, limit: preferences.maxGustKPH)) }
        if let wave = hour.waveHeightM { factors.append(limitScore(wave, limit: preferences.maxWaveM)) }
        if let rain = hour.precipitationProbability { factors.append(max(0, 1 - rain / 100)) }
        if let daylight = hour.isDaylight { factors.append(daylight ? 1 : 0.25) }
        guard !factors.isEmpty else { return 0 }
        return factors.reduce(0, +) / Double(factors.count)
    }

    private func limitScore(_ value: Double, limit: Double) -> Double {
        guard limit > 0 else { return 0 }
        return min(1, max(0, 1 - (value / limit) * 0.72))
    }

    private func tideAlignmentScore(start: Date, end: Date, events: [TideEvent], windowMinutes: Double) -> Double {
        let highs = events.filter { $0.kind == .high }
        guard !highs.isEmpty else { return 0 }
        let allowed = max(30 * 60, windowMinutes * 60)
        func proximity(to date: Date) -> Double {
            let difference = highs.map { abs($0.time.timeIntervalSince(date)) }.min() ?? .infinity
            return max(0, 1 - difference / (allowed * 2))
        }
        return (proximity(to: start) + proximity(to: end)) / 2
    }

    private func isContiguous(_ hours: [HourlyConditions]) -> Bool {
        zip(hours, hours.dropFirst()).allSatisfy { next, following in
            abs(following.time.timeIntervalSince(next.time) - 60 * 60) < 5 * 60
        }
    }

    private func rationale(
        for hours: [HourlyConditions],
        timeline: ForecastTimeline,
        preferences: AppPreferences,
        tideScore: Double
    ) -> [String] {
        var reasons: [String] = []
        let winds = hours.compactMap(\.windSpeedKPH)
        let gusts = hours.compactMap(\.windGustKPH)
        let waves = hours.compactMap(\.waveHeightM)
        let rain = hours.compactMap(\.precipitationProbability)
        if let low = winds.min(), let high = winds.max() {
            reasons.append("Winds \(Int(low.rounded()))–\(Int(high.rounded())) km/h, below your \(Int(preferences.maxWindKPH)) km/h limit")
        }
        if let high = gusts.max() {
            reasons.append("Peak gusts near \(Int(high.rounded())) km/h")
        }
        if let high = waves.max() {
            reasons.append(String(format: "Waves up to %.1f m", high))
        } else {
            reasons.append("Wave data unavailable; the score uses weather and daylight")
        }
        if let high = rain.max() {
            reasons.append("Rain chance stays at or below \(Int(high.rounded()))%")
        }
        if !timeline.tideEvents.isEmpty {
            reasons.append(tideScore >= 0.5 ? "Launch or retrieval aligns well with high tide" : "Tide timing is acceptable but not ideal")
        }
        return reasons
    }

    private func weakestReason(for hours: [HourlyConditions], preferences: AppPreferences) -> String? {
        let maxWindRatio = hours.compactMap(\.windSpeedKPH).map { $0 / preferences.maxWindKPH }.max() ?? 0
        let maxGustRatio = hours.compactMap(\.windGustKPH).map { $0 / preferences.maxGustKPH }.max() ?? 0
        let maxWaveRatio = hours.compactMap(\.waveHeightM).map { $0 / preferences.maxWaveM }.max() ?? 0
        let values = [(maxWindRatio, "Wind is closest to your limit"), (maxGustRatio, "Gusts are closest to your limit"), (maxWaveRatio, "Waves are closest to your limit")]
        return values.max(by: { $0.0 < $1.0 })?.1
    }
}

