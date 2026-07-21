# Sea Signal

Sea Signal is a SwiftUI boating companion that discovers boat launches, evaluates seven days of weather/marine/tide data against the boater’s limits, and recommends the strongest safe trip window.

## Features

- Location-based ramp discovery with automatic nearest-three favorites
- Search by ramp, city, or address using Apple MapKit
- Custom map-pin launches for ramps that are not indexed
- Persistent favorites and optional NOAA tide-station override
- Seven-day wind, gust, rain, daylight, wave, swell, and tide timeline
- Ranked launch/retrieval windows with plain-language rationale
- High/low tide predictions and modeled fallback labels
- Cached provider responses and offline last-good forecasts
- Configurable weekly local outlook notifications
- Best-effort iOS background forecast refresh

## Data providers

- Apple MapKit: launch discovery and map search
- Open-Meteo Forecast API: wind, gusts, precipitation, and daylight
- Open-Meteo Marine API: waves, wave period, swell, and modeled water levels
- NOAA CO-OPS: official U.S. tide predictions from nearby stations

NOAA predictions are used only when a station is within 40 km, unless the user explicitly selects another nearby station. Modeled water levels are labeled and must not be used for navigation.

## Requirements

- Xcode 15 or newer
- iOS 17 or newer

Open `SeaSignal.xcodeproj`, select an iPhone Simulator, and run the `SeaSignal` scheme.

## Tests

Run the unit tests with `Command-U` in Xcode. Tests cover provider decoding, local-time parsing, null marine values, calm/windy recommendations, daylight rules, and inland ramps without wave/tide coverage.

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the live-data pipeline and safety behavior.

