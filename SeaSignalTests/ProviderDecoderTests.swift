import XCTest
@testable import SeaSignal

final class ProviderDecoderTests: XCTestCase {
    func testWeatherFixtureDecodesParallelHourlyArrays() throws {
        let data = try fixture(named: "open_meteo_weather")
        let response = try JSONDecoder().decode(OpenMeteoWeatherResponse.self, from: data)
        XCTAssertEqual(response.timezone, "America/New_York")
        XCTAssertEqual(response.hourly.time.count, 3)
        XCTAssertEqual(response.hourly.wind_speed_10m[1], 12.4)
        XCTAssertEqual(response.hourly.precipitation_probability[2], 45)
        XCTAssertEqual(response.hourly.is_day, [1, 1, 0])
    }

    func testMarineFixturePreservesNullWaveValues() throws {
        let data = try fixture(named: "open_meteo_marine")
        let response = try JSONDecoder().decode(OpenMeteoMarineResponse.self, from: data)
        XCTAssertEqual(response.hourly.time.count, 3)
        XCTAssertNil(response.hourly.wave_height[1])
        XCTAssertEqual(response.hourly.wave_period[0], 4.5)
    }

    func testRampLocalTimeParsingUsesNamedTimezone() {
        let parsed = LocalForecastDateParser.parse(["2026-07-21T08:00"], timezoneIdentifier: "America/New_York")
        XCTAssertNotNil(parsed[0])
    }

    func testForecastUnitConversionsPreserveMissingMeasurements() {
        XCTAssertEqual(ForecastUnits.knots(fromKPH: 18.52), 10)
        XCTAssertEqual(ForecastUnits.fahrenheit(fromCelsius: 0), 32)
        XCTAssertEqual(ForecastUnits.inchesOfMercury(fromHectopascals: 1013.25)!, 29.92, accuracy: 0.01)
        XCTAssertEqual(ForecastUnits.feet(fromMetres: 1)!, 3.28, accuracy: 0.01)
        XCTAssertEqual(ForecastUnits.inches(fromMillimetres: 25.4)!, 1, accuracy: 0.001)
        XCTAssertNil(ForecastUnits.knots(fromKPH: nil))
        XCTAssertNil(ForecastUnits.fahrenheit(fromCelsius: nil))
        XCTAssertNil(ForecastUnits.inchesOfMercury(fromHectopascals: nil))
        XCTAssertNil(ForecastUnits.feet(fromMetres: nil))
        XCTAssertNil(ForecastUnits.inches(fromMillimetres: nil))
    }

    func testThreeHourSamplingKeepsEntireSevenDayForecast() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let hours = (0..<168).map { hour in
            hourlyConditions(at: start.addingTimeInterval(Double(hour) * 3600))
        }

        let sampled = ForecastPresentation.sampledHours(hours)

        XCTAssertEqual(sampled.count, 56)
        XCTAssertEqual(sampled.first?.time, start)
        XCTAssertEqual(sampled.last?.time, start.addingTimeInterval(165 * 3600))
    }

    func testNextTideUsesChronologicalEventWhenInputIsUnsorted() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let later = TideEvent(time: now.addingTimeInterval(7200), heightM: 1.1, kind: .high)
        let sooner = TideEvent(time: now.addingTimeInterval(3600), heightM: 0.2, kind: .low)

        XCTAssertEqual(ForecastPresentation.nextTide(after: now, events: [later, sooner]), sooner)
    }

    func testForecastFormattingUsesLaunchTimezone() throws {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let newYork = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        let losAngeles = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))

        XCTAssertNotEqual(
            ForecastPresentation.string(from: date, timeZone: newYork, format: "yyyy-MM-dd HH:mm z"),
            ForecastPresentation.string(from: date, timeZone: losAngeles, format: "yyyy-MM-dd HH:mm z")
        )
    }

    func testSavedFavoriteDecodesWhenMeasurementAndForecastFieldsAreAbsent() throws {
        let launch = BoatLaunch(
            id: "legacy-launch",
            name: "Legacy Launch",
            location: "Tampa, FL",
            latitude: 27.95,
            longitude: -82.46
        )
        let encoded = try JSONEncoder().encode(launch)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        for key in [
            "distanceMetres", "windSpeed", "gustSpeed", "waveHeight", "wavePeriod",
            "rainChance", "recommendationScore", "rationale", "forecastIsStale",
            "forecastUpdatedAt", "forecastTimezoneIdentifier", "forecastHours", "tideEvents"
        ] {
            object.removeValue(forKey: key)
        }

        let decoded = try JSONDecoder().decode(
            BoatLaunch.self,
            from: JSONSerialization.data(withJSONObject: object)
        )

        XCTAssertNil(decoded.distanceMetres)
        XCTAssertNil(decoded.windSpeed)
        XCTAssertNil(decoded.gustSpeed)
        XCTAssertNil(decoded.forecastHours)
        XCTAssertEqual(decoded.distance, "Distance unavailable")
    }

    private func hourlyConditions(at time: Date) -> HourlyConditions {
        HourlyConditions(
            time: time,
            windSpeedKPH: 18.52,
            windGustKPH: 22,
            windDirectionDegrees: 90,
            precipitationProbability: 10,
            precipitationMM: 0,
            waveHeightM: 0.5,
            wavePeriodSeconds: 5,
            swellHeightM: 0.4,
            tideHeightM: 0.2,
            isDaylight: true,
            airTemperatureC: 25,
            surfacePressureHPa: 1013.25,
            weatherCode: 0,
            waveDirectionDegrees: 180
        )
    }

    private func fixture(named name: String) throws -> Data {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: name, withExtension: "json"))
        return try Data(contentsOf: url)
    }
}
