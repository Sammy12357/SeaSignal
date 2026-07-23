# Sea Signal

Sea Signal is a SwiftUI boating companion that discovers boat launches, evaluates seven days of weather/marine/tide data against the boater’s limits, and recommends the strongest safe trip window.

## Features

- Location-based ramp discovery with automatic nearest-three favorites
- Search by ramp, city, or address using Apple MapKit
- Full-screen wind map with speed colors, switchable particle/arrows animation, clusters, filters, and a 3-hour forecast timeline
- Expanded boat-access discovery from OpenStreetMap boat ramps, leisure/service slipways, and water access points
- Fishing-pier discovery and one-tap favorite tracking
- Live airport METAR observations from the Aviation Weather Center
- NOAA/NDBC marine weather stations, including nearby offshore stations
- Curated weather-interest pins, beginning with Gandy Bridge in Old Tampa Bay
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
- OpenStreetMap Overpass API: mapped boat ramps and fishing piers, with MapKit fallback
- Aviation Weather Center Data API: current airport METAR observations
- NOAA/NDBC: current marine and buoy wind observations
- Open-Meteo Forecast API: wind, gusts, precipitation, and daylight
- Open-Meteo Marine API: waves, wave period, swell, and modeled water levels
- NOAA CO-OPS: official U.S. tide predictions from nearby stations

NOAA predictions are used only when a station is within 40 km, unless the user explicitly selects another nearby station. Modeled water levels are labeled and must not be used for navigation.

Airport reports are land-based observations and may not represent conditions on the water. Curated weather-interest pins, including Gandy Bridge, identify useful locations but do not claim that a sensor exists at the pin. OpenStreetMap coverage varies by area and should be verified before relying on a launch location.

## Requirements

- Xcode 15 or newer
- iOS 17 or newer

Open `SeaSignal.xcodeproj`, select an iPhone Simulator, and run the `SeaSignal` scheme.

## Tests

Run the unit tests with `Command-U` in Xcode. Tests cover airport METAR and NOAA decoding, expanded boat-access tags, curated weather spots, wind-grid interpolation, map deduplication, favorite priority, local-time parsing, null marine values, calm/windy recommendations, daylight rules, and inland ramps without wave/tide coverage.

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the live-data pipeline and safety behavior.
