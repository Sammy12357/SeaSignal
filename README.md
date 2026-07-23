# Sea Signal

Sea Signal is an iOS boating companion that recommends safe trip windows using marine weather, waves, and tide timing.

## Current app

- Favorite boat launches and condition status
- Recommended launch and retrieval windows
- High-tide timing and trip rationale
- Interactive MapKit launch map and searchable list
- Live wind speed, gust, and direction from Open-Meteo
- Animated launch arrows and a flowing wind-particle layer
- Hourly forecast timeline with wind, wave, and current layer controls
- Offline sample fallback and short-lived forecast caching
- Persistent wind, gust, wave, tide, and trip-length preferences

Sea Signal falls back to deterministic sample wind data when the live provider is unavailable. Wave and
current controls are present, while their regional animated fields remain dependent on provider coverage.

Forecast data is provided by [Open-Meteo](https://open-meteo.com/). Review its current licensing and
attribution requirements before commercial distribution.

## Requirements

- Xcode 15 or newer
- iOS 17 or newer

Open `SeaSignal.xcodeproj` in Xcode and run the `SeaSignal` scheme.

From a macOS terminal:

```bash
xcodebuild \
  -project SeaSignal.xcodeproj \
  -scheme SeaSignal \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  clean build
```

The animated layer respects Reduce Motion, lowers particle density in Low Power Mode, and pauses movement
when the app is inactive.

