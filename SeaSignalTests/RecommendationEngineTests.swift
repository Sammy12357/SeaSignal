import XCTest
@testable import SeaSignal

final class RecommendationEngineTests: XCTestCase {
    private let engine = RecommendationEngine()

    func testCalmDayProducesRecommendation() {
        let timeline = makeTimeline(wind: 8, gust: 12, wave: 0.2, rain: 10, tideEvents: true)
        let results = engine.recommendations(for: timeline, preferences: .defaults, now: timeline.hours[0].time)
        XCTAssertFalse(results.isEmpty)
        XCTAssertGreaterThan(results[0].score, 0.5)
        XCTAssertEqual(results[0].rationale.isEmpty, false)
    }

    func testWindAboveLimitProducesNoRecommendation() {
        let timeline = makeTimeline(wind: 40, gust: 55, wave: 0.2, rain: 10, tideEvents: true)
        let results = engine.recommendations(for: timeline, preferences: .defaults, now: timeline.hours[0].time)
        XCTAssertTrue(results.isEmpty)
    }

    func testInlandTimelineWithoutWavesOrTidesStillProducesRecommendation() {
        let timeline = makeTimeline(wind: 7, gust: 10, wave: nil, rain: 5, tideEvents: false)
        let results = engine.recommendations(for: timeline, preferences: .defaults, now: timeline.hours[0].time)
        XCTAssertFalse(results.isEmpty)
        XCTAssertTrue(results[0].rationale.contains(where: { $0.contains("Wave data unavailable") }))
    }

    func testDaylightRequirementRejectsNightWindow() {
        var preferences = AppPreferences.defaults
        preferences.tripLengthHours = 3
        let timeline = makeTimeline(wind: 5, gust: 8, wave: 0.1, rain: 0, tideEvents: false, daylight: false)
        XCTAssertTrue(engine.recommendations(for: timeline, preferences: preferences, now: timeline.hours[0].time).isEmpty)
    }

    private func makeTimeline(
        wind: Double,
        gust: Double,
        wave: Double?,
        rain: Double,
        tideEvents: Bool,
        daylight: Bool = true
    ) -> ForecastTimeline {
        let start = Calendar(identifier: .gregorian).dateInterval(of: .hour, for: Date())!.start.addingTimeInterval(60)
        let hours = (0..<24).map { offset in
            HourlyConditions(
                time: start.addingTimeInterval(Double(offset) * 3600),
                windSpeedKPH: wind,
                windGustKPH: gust,
                windDirectionDegrees: 90,
                precipitationProbability: rain,
                precipitationMM: 0,
                waveHeightM: wave,
                wavePeriodSeconds: wave == nil ? nil : 5,
                swellHeightM: nil,
                tideHeightM: tideEvents ? sin(Double(offset) / 2) : nil,
                isDaylight: daylight
            )
        }
        let events = tideEvents ? [
            TideEvent(time: start.addingTimeInterval(2 * 3600), heightM: 0.8, kind: .high),
            TideEvent(time: start.addingTimeInterval(8 * 3600), heightM: 0.1, kind: .low)
        ] : []
        return ForecastTimeline(
            timezoneIdentifier: "America/New_York",
            hours: hours,
            tideEvents: events,
            tideSource: tideEvents ? "NOAA test station" : "Tides unavailable",
            fetchedAt: Date(),
            isStale: false
        )
    }
}

