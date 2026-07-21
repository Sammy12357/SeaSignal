import MapKit
import SwiftUI

enum WindPalette {
    static let stops: [(Double, Color)] = [
        (0, Color(red: 0.29, green: 0.25, blue: 0.68)),
        (4, Color(red: 0.25, green: 0.48, blue: 0.82)),
        (8, Color(red: 0.23, green: 0.68, blue: 0.78)),
        (14, Color(red: 0.20, green: 0.66, blue: 0.35)),
        (20, Color(red: 0.58, green: 0.72, blue: 0.25)),
        (27, Color(red: 0.91, green: 0.70, blue: 0.20)),
        (35, Color(red: 0.90, green: 0.42, blue: 0.20)),
        (45, Color(red: 0.68, green: 0.16, blue: 0.42)),
        (55, Color(red: 0.45, green: 0.06, blue: 0.43))
    ]

    static var gradient: Gradient { Gradient(stops: stops.map { .init(color: $0.1, location: $0.0 / 55) }) }

    static func color(for speed: Double) -> Color {
        stops.last(where: { speed >= $0.0 })?.1 ?? stops[0].1
    }
}

struct WindColorOverlay: View {
    let field: WindField
    let proxy: MapProxy

    var body: some View {
        Canvas { context, _ in
            guard field.rows > 1, field.columns > 1 else { return }
            let subdivision = 3
            let displayRows = (field.rows - 1) * subdivision
            let displayColumns = (field.columns - 1) * subdivision
            for row in 0..<displayRows {
                for column in 0..<displayColumns {
                    func coordinate(row: Int, column: Int) -> CLLocationCoordinate2D {
                        CLLocationCoordinate2D(
                            latitude: field.minLatitude + (field.maxLatitude - field.minLatitude) * Double(row) / Double(displayRows),
                            longitude: field.minLongitude + (field.maxLongitude - field.minLongitude) * Double(column) / Double(displayColumns)
                        )
                    }
                    let coordinates = [
                        coordinate(row: row, column: column),
                        coordinate(row: row, column: column + 1),
                        coordinate(row: row + 1, column: column + 1),
                        coordinate(row: row + 1, column: column)
                    ]
                    let points = coordinates.compactMap { proxy.convert($0, to: .local) }
                    guard points.count == 4 else { continue }
                    var path = Path()
                    path.move(to: points[0])
                    points.dropFirst().forEach { path.addLine(to: $0) }
                    path.closeSubpath()
                    let center = coordinate(row: row, column: column)
                    let mean = field.sample(at: center)?.speed ?? 0
                    context.fill(path, with: .color(WindPalette.color(for: mean).opacity(0.46)))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
