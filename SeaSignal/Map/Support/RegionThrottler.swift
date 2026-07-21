import MapKit

@MainActor
final class RegionThrottler {
    private var task: Task<Void, Never>?
    private var lastRegion: MKCoordinateRegion?

    func submit(_ region: MKCoordinateRegion, action: @escaping @MainActor (MKCoordinateRegion) -> Void) {
        task?.cancel()
        task = Task {
            try? await Task.sleep(for: .milliseconds(550))
            guard !Task.isCancelled else { return }
            if let lastRegion, !movedEnough(from: lastRegion, to: region) { return }
            self.lastRegion = region
            action(region)
        }
    }

    private func movedEnough(from previous: MKCoordinateRegion, to current: MKCoordinateRegion) -> Bool {
        let centerDistance = GeoMath.distance(previous.center, current.center)
        let visibleMeters = max(1, current.span.latitudeDelta * 111_000)
        let priorSpan = max(previous.span.latitudeDelta, 0.0001)
        let zoomChange = abs(previous.span.latitudeDelta - current.span.latitudeDelta) / priorSpan
        return centerDistance > visibleMeters * 0.18 || zoomChange > 0.18
    }
}
