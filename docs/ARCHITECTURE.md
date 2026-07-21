# Sea Signal architecture

## Forecast pipeline

1. A launch resolves to a name and coordinate through MapKit search or a user-placed map pin.
2. Weather, marine, and NOAA tide providers fetch concurrently.
3. `CachedHTTPClient` caches raw responses on disk and returns stale data when the network fails.
4. Provider results are parsed using the ramp’s named time zone and merged into absolute hourly `Date` values.
5. `ForecastTimelineBuilder` creates one provider-neutral seven-day timeline.
6. `RecommendationEngine` applies hard safety limits, finds contiguous windows of the chosen trip length, scores the passing windows, and ranks them.
7. `MarineForecastService` adapts the best result for the current SwiftUI screens.

## Map pipeline

1. `MapTabView` reports its visible MapKit region through a 550 ms region throttler.
2. `OverpassProvider` discovers OpenStreetMap slipways and piers; Apple local search supplies a resilient fallback when an Overpass instance is unavailable.
3. Saved favorites win coordinate-level deduplication, and zoomed-out results are grouped into lightweight display clusters.
4. `WindGridProvider` samples an Open-Meteo 7×7 grid at the selected forecast hour and converts speed/direction into vector components.
5. `WindColorOverlay` draws the interpolated speed wash while `WindOverlay` animates deterministic streamlines. Particle count and frame rate drop automatically in Low Power Mode.
6. Ramp and wind results are cached on disk for 20 minutes, with stale wind data available when the network is offline.

Map requests are cancelled or coalesced as the viewport and timeline change. The animated layer pauses when the app is inactive.

## Safety behavior

- Missing wind or gust data prevents a recommendation.
- Wave and tide data are optional for inland ramps; missing values are excluded instead of treated as safe zeroes.
- Wind, gust, wave, rain, and daylight preferences are hard limits.
- Tide alignment improves a score. When “Require high tide” is enabled and NOAA events exist, poorly aligned windows are rejected.
- Forecast timestamps and stale/offline status are shown in the UI.
- Recommendations are guidance and do not replace official marine warnings, charts, navigation data, or operator judgment.

## Background outlook

The app schedules one repeating weekly local notification. Its content is refreshed whenever the app enters the foreground and during best-effort `BGAppRefreshTask` executions. iOS controls background execution timing, so the refresh itself is not guaranteed to run at an exact time.

## Tests

`SeaSignalTests` contains deterministic recommendation-engine tests plus stored Open-Meteo response fixtures. Networking is intentionally kept outside the pure engine so forecast rules can be validated without an internet connection.
