# SeaSignal Animated Weather Effects — Codex Implementation Plan

## Objective

Add a production-quality marine map to the iOS 17 SwiftUI app with:

1. Live wind and marine conditions.
2. Directional animated arrows at boat launches.
3. A Windy-style moving particle layer showing wind flow.
4. Time selection, loading/error states, accessibility, caching, and tests.

The implementation should remain usable when animation is disabled or live data is unavailable.

## Important constraints

- The current project contains only sample launch data and list-based screens.
- It has no map, geographic coordinates, wind direction, network layer, or animation renderer.
- Use native SwiftUI, MapKit, URLSession, and Canvas first. Do not add a third-party map SDK.
- Target iOS 17+ and Xcode 15+.
- Keep API code behind protocols so the provider can be replaced later.
- Do not commit API secrets. Open-Meteo can be used for the initial provider because its basic endpoint does not require an API key; confirm licensing before commercial release.
- This Windows checkout can be edited and statically inspected, but building and launching the iOS app requires macOS with Xcode.

## Target architecture

```text
LaunchMapView
├── SwiftUI Map (base map, launch markers, camera)
├── WeatherEffectsOverlay
│   ├── WindArrowLayer (launch-level direction/speed)
│   └── WindParticleCanvas (regional vector field)
├── ForecastTimeControl
└── MapLegend / loading / error controls

WeatherViewModel (@MainActor)
├── WeatherService protocol
│   └── OpenMeteoWeatherService
├── MarineService protocol
│   └── OpenMeteoMarineService
├── ForecastCache
└── WindFieldBuilder
```

## Phase 1 — Project baseline and model corrections

### Tasks

- Build the untouched project in Xcode and record the baseline result.
- Add coordinates to `BoatLaunch` using `CLLocationCoordinate2D` or stored latitude/longitude values.
- Replace the generated `UUID()` identity with stable IDs so map annotations do not reset on every render.
- Correct the visible mojibake strings (`â€™`, `Â·`, `â€“`, and `â€”`) and ensure all Swift files are UTF-8.
- Introduce:
  - `WindSample`: coordinate, timestamp, speed, direction, gust.
  - `MarineSample`: wave height/direction/period and current velocity/direction when available.
  - `ForecastPoint`: combined data used by the UI.
  - `WindVector`: `u` and `v` components plus coordinate.
- Add unit conversion helpers for degrees, knots, km/h, and meters/second.

### Suggested files

- `SeaSignal/Models/BoatLaunch.swift`
- `SeaSignal/Models/ForecastModels.swift`
- `SeaSignal/Utilities/UnitConversions.swift`

### Acceptance criteria

- Existing screens still render.
- Each sample launch appears at a stable, valid coordinate.
- Direction conversion tests cover 0°, 90°, 180°, 270°, and wraparound.
- No corrupt punctuation remains in the UI.

## Phase 2 — Add the real map screen

### Tasks

- Change `LaunchesView` into a map-first screen, with a list/map segmented control if retaining the list is desirable.
- Use SwiftUI `Map` with `MapCameraPosition`.
- Initially frame the Greater Toronto/Lake Ontario sample area.
- Render tappable launch annotations colored by `BoatLaunch.Conditions`.
- Selecting an annotation opens the existing `LaunchDetailView`.
- Add user-location support only after adding the appropriate Info.plist usage description and permission handling. The map must work when permission is denied.
- Expose the visible map region/camera changes to the effects layer.

### Suggested files

- `SeaSignal/Views/LaunchesView.swift`
- `SeaSignal/Views/LaunchMapView.swift`
- `SeaSignal/Components/LaunchMapMarker.swift`

### Acceptance criteria

- All sample launches are visible and tappable.
- Map pan, zoom, rotation, and selection work without animation.
- The screen remains functional offline with sample data.

## Phase 3 — Networking and live forecast data

### Initial provider

Use Open-Meteo behind protocols:

- Forecast API for `wind_speed_10m`, `wind_direction_10m`, and `wind_gusts_10m`.
- Marine API for wave height/direction/period and ocean-current fields where coverage exists.
- Request multiple coordinate points in batches when supported.

Do not treat a launch-level response as a regional vector field. For the flowing overlay, sample a bounded grid covering the visible map region. Start with a coarse grid and cap requests.

### Tasks

- Implement an `APIClient` around `URLSession`.
- Define typed `Decodable` response DTOs separate from domain models.
- Add `WeatherService` and `MarineService` protocols.
- Add request cancellation when the camera or selected time changes.
- Debounce map camera changes before requesting a new grid.
- Add an actor-based memory/disk cache keyed by rounded coordinate, forecast hour, and variable set.
- Add explicit loading, stale-data, partial-data, rate-limit, decoding, network, and offline states.
- Retain bundled sample JSON fixtures for previews, tests, and offline fallback.
- Display provider attribution in the map UI.

### Suggested files

- `SeaSignal/Services/APIClient.swift`
- `SeaSignal/Services/WeatherService.swift`
- `SeaSignal/Services/OpenMeteoWeatherService.swift`
- `SeaSignal/Services/MarineService.swift`
- `SeaSignal/Services/OpenMeteoMarineService.swift`
- `SeaSignal/Services/ForecastCache.swift`
- `SeaSignal/ViewModels/WeatherMapViewModel.swift`
- `SeaSignal/Resources/Fixtures/*.json`

### Acceptance criteria

- A launch displays current wind speed, direction, and timestamp from the provider.
- Decoding is covered by fixture-based tests.
- Repeated requests use the cache.
- Moving the camera rapidly cancels/debounces obsolete work.
- Network failure leaves a usable map and clearly labels stale/sample data.

## Phase 4 — Animated launch arrows (first shippable effect)

### Tasks

- Add an arrow glyph above each launch annotation.
- Rotate it from forecast direction using a documented convention:
  - Meteorological wind direction means where wind comes from.
  - The visual flow arrow should point where wind travels, so add 180°.
- Encode speed through a restrained combination of color, arrow length/scale, and animation rate.
- Use `TimelineView(.animation)` or a lightweight repeating SwiftUI animation for pulse/travel effects.
- Interpolate between forecast hours so arrows do not jump when the time slider changes.
- Disable nonessential motion when `accessibilityReduceMotion` is enabled; retain static directional arrows.
- Pause animation while the app is inactive.

### Suggested files

- `SeaSignal/Components/WindArrowView.swift`
- `SeaSignal/Components/WindArrowLayer.swift`
- `SeaSignal/Utilities/ForecastInterpolation.swift`

### Acceptance criteria

- Direction is visually correct for cardinal test values.
- Animation changes with wind speed without becoming distracting.
- No arrow recreation/flicker occurs during ordinary SwiftUI updates.
- Reduced Motion produces static arrows.
- The app remains responsive during map interaction.

## Phase 5 — Wind particle field

### Rendering approach

Use a SwiftUI `Canvas` placed over the map. Drive it with `TimelineView(.animation)` and maintain particle state outside the view body. Do not start with Metal; move to Metal only if profiling proves Canvas cannot meet the target.

Each particle should contain:

- Geographic or normalized map position.
- Previous screen position for drawing a short trail.
- Age and maximum lifetime.
- Seed value for deterministic respawning.

For each animation frame:

1. Project the particle position into the sampled weather grid.
2. Bilinearly interpolate the four surrounding `u/v` vectors.
3. Advance the particle using elapsed time, not a fixed frame increment.
4. Reproject it to screen coordinates.
5. Draw a short fading line/arrowhead.
6. Respawn particles that leave the viewport or exceed their lifetime.

### Performance safeguards

- Begin with 250–500 particles and dynamically reduce the count on low-power mode.
- Cap frame delta after interruptions.
- Do not fetch data every frame.
- Rebuild screen projections only when the map camera changes.
- Pause during backgrounding and optionally while the user is actively dragging.
- Avoid allocating arrays or formatters inside the frame loop.
- Use Instruments on a physical device before raising particle count.

### Suggested files

- `SeaSignal/Effects/WindField.swift`
- `SeaSignal/Effects/WindFieldBuilder.swift`
- `SeaSignal/Effects/WindParticle.swift`
- `SeaSignal/Effects/WindParticleEngine.swift`
- `SeaSignal/Effects/WindParticleCanvas.swift`
- `SeaSignal/Effects/MapProjection.swift`

### Acceptance criteria

- Particles follow a synthetic uniform field in unit tests and previews.
- A known eastward field moves particles east regardless of frame rate.
- Panning/zooming does not permanently detach particles from the map.
- Animation stops in the background and respects Reduced Motion.
- Target a smooth 60 fps on a representative physical device; accept 30 fps under low-power mode.

## Phase 6 — Forecast timeline and effect controls

### Tasks

- Add an hourly time slider/playback control.
- Animate forecast-time playback independently from particle-frame animation.
- Interpolate vector fields between adjacent forecast hours.
- Add layers: Wind, Waves, and Currents.
- Add a legend showing units, color scale, selected time, and data freshness.
- Persist the selected layer and animation preference with `AppStorage`.
- Provide a static-effects toggle in Preferences.

### Acceptance criteria

- Playback advances forecast hours at a readable rate.
- The selected timestamp is always visible.
- Layer and time changes never display mismatched old data.
- Missing current/wave coverage is explicitly communicated.

## Phase 7 — Tests, accessibility, and release validation

### Unit tests

- API decoding and missing-field behavior.
- Wind direction to `u/v` conversion.
- `u/v` back to visual direction.
- Bilinear interpolation.
- Forecast-hour interpolation across north/360° wraparound.
- Cache keys, expiration, and stale fallback.
- Particle advancement and respawning.

### UI/manual tests

- Launch map loads from a clean install.
- Permission denied and offline scenarios.
- Rapid pan/zoom/time changes.
- Background/foreground transitions.
- Dark Mode, Dynamic Type, VoiceOver, Reduced Motion, and Low Power Mode.
- At least one older supported iPhone and one current device.

### Build gate

Run on macOS:

```bash
xcodebuild \
  -project SeaSignal.xcodeproj \
  -scheme SeaSignal \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  clean test
```

If that exact simulator is unavailable, list installed destinations with:

```bash
xcodebuild -project SeaSignal.xcodeproj -scheme SeaSignal -showdestinations
```

Then launch from Xcode and profile the map with Instruments using the Core Animation and Time Profiler templates.

## Recommended Codex execution sequence

Codex should implement this as small, independently buildable commits:

1. `Model coordinates and repair text encoding`
2. `Add MapKit launch map`
3. `Add typed weather and marine services with fixtures`
4. `Connect live launch forecasts and cache`
5. `Add accessible animated wind arrows`
6. `Add vector grid builder and interpolation tests`
7. `Add Canvas particle renderer`
8. `Add timeline, legends, and layer controls`
9. `Optimize, test, document attribution, and verify release build`

After each commit, Codex should:

- Review `git diff --check`.
- Run all tests available in the current environment.
- On macOS, run the Xcode build/test command.
- Stop and fix regressions before beginning the next phase.

## Definition of done

- The Launches tab contains a working MapKit map.
- Launch markers show live condition status.
- Animated arrows show correct wind travel direction and relative speed.
- A regional particle overlay moves according to an interpolated vector field.
- The user can select forecast time and weather layer.
- Offline, stale, loading, error, attribution, Reduced Motion, and low-power behavior are handled.
- Unit/UI tests pass and the app is verified in an iOS Simulator and on a physical device.
- README documents data sources, limitations, build steps, and attribution.
