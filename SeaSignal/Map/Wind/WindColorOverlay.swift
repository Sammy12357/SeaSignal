import MapKit
import SwiftUI

enum WindPalette {
    struct Stop {
        let speed: Double
        let red: Double
        let green: Double
        let blue: Double

        var color: Color { Color(red: red, green: green, blue: blue) }
    }

    static let stops: [Stop] = [
        Stop(speed: 0, red: 0.29, green: 0.25, blue: 0.68),
        Stop(speed: 4, red: 0.25, green: 0.48, blue: 0.82),
        Stop(speed: 8, red: 0.23, green: 0.68, blue: 0.78),
        Stop(speed: 14, red: 0.20, green: 0.66, blue: 0.35),
        Stop(speed: 20, red: 0.58, green: 0.72, blue: 0.25),
        Stop(speed: 27, red: 0.91, green: 0.70, blue: 0.20),
        Stop(speed: 35, red: 0.90, green: 0.42, blue: 0.20),
        Stop(speed: 45, red: 0.68, green: 0.16, blue: 0.42),
        Stop(speed: 55, red: 0.45, green: 0.06, blue: 0.43)
    ]

    static var gradient: Gradient {
        Gradient(stops: stops.map { .init(color: $0.color, location: $0.speed / 55) })
    }

    static func color(for speed: Double) -> Color {
        guard let upperIndex = stops.firstIndex(where: { speed <= $0.speed }) else { return stops.last!.color }
        guard upperIndex > 0 else { return stops[0].color }
        let lower = stops[upperIndex - 1]
        let upper = stops[upperIndex]
        let fraction = (speed - lower.speed) / max(upper.speed - lower.speed, 0.001)
        return Color(
            red: lower.red + (upper.red - lower.red) * fraction,
            green: lower.green + (upper.green - lower.green) * fraction,
            blue: lower.blue + (upper.blue - lower.blue) * fraction
        )
    }
}

struct WindColorOverlay: View {
    let field: WindField
    let region: MKCoordinateRegion

    var body: some View {
        Canvas(rendersAsynchronously: true) { context, size in
            guard field.rows > 1, field.columns > 1 else { return }
            let displayColumns = 18
            let displayRows = max(18, Int(Double(displayColumns) * size.height / max(size.width, 1)))
            let cellWidth = size.width / CGFloat(displayColumns)
            let cellHeight = size.height / CGFloat(displayRows)
            let box = GeoMath.boundingBox(region)

            for row in 0..<displayRows {
                for column in 0..<displayColumns {
                    let xFraction = (Double(column) + 0.5) / Double(displayColumns)
                    let yFraction = (Double(row) + 0.5) / Double(displayRows)
                    let coordinate = CLLocationCoordinate2D(
                        latitude: box.north - region.span.latitudeDelta * yFraction,
                        longitude: box.west + region.span.longitudeDelta * xFraction
                    )
                    guard let sample = field.sampleClamped(to: coordinate) else { continue }
                    let rect = CGRect(
                        x: CGFloat(column) * cellWidth - 0.75,
                        y: CGFloat(row) * cellHeight - 0.75,
                        width: cellWidth + 1.5,
                        height: cellHeight + 1.5
                    )
                    context.fill(Path(rect), with: .color(WindPalette.color(for: sample.speed)))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .opacity(0.48)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
