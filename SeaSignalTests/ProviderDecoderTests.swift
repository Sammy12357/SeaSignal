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

    private func fixture(named name: String) throws -> Data {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: name, withExtension: "json"))
        return try Data(contentsOf: url)
    }
}

