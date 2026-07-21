import Foundation

struct BoatLaunch: Identifiable, Hashable {
    enum Conditions: String {
        case ideal = "Ideal"
        case caution = "Caution"
        case avoid = "Avoid"
    }

    let id = UUID()
    let name: String
    let location: String
    let distance: String
    let conditions: Conditions
    let launchTime: String
    let retrievalTime: String
    let highTide: String
    let windSpeed: Int
    let gustSpeed: Int
    let waveHeight: Double
    let summary: String
    let isFavorite: Bool

    static let samples: [BoatLaunch] = [
        BoatLaunch(
            name: "Harbourfront Launch", location: "Toronto, ON", distance: "4.2 km",
            conditions: .ideal, launchTime: "7:15 AM", retrievalTime: "2:30 PM",
            highTide: "7:48 AM", windSpeed: 9, gustSpeed: 14, waveHeight: 0.3,
            summary: "Calm water and light winds through early afternoon.", isFavorite: true
        ),
        BoatLaunch(
            name: "Frenchman's Bay", location: "Pickering, ON", distance: "34 km",
            conditions: .ideal, launchTime: "6:50 AM", retrievalTime: "1:45 PM",
            highTide: "7:22 AM", windSpeed: 11, gustSpeed: 17, waveHeight: 0.4,
            summary: "A clear morning window before winds build after 3 PM.", isFavorite: true
        ),
        BoatLaunch(
            name: "Bronte Harbour", location: "Oakville, ON", distance: "39 km",
            conditions: .caution, launchTime: "8:10 AM", retrievalTime: "12:30 PM",
            highTide: "8:36 AM", windSpeed: 18, gustSpeed: 25, waveHeight: 0.7,
            summary: "Shorter window recommended as afternoon gusts approach your limit.", isFavorite: true
        ),
        BoatLaunch(
            name: "Port Credit Marina", location: "Mississauga, ON", distance: "25 km",
            conditions: .avoid, launchTime: "—", retrievalTime: "—",
            highTide: "9:04 AM", windSpeed: 27, gustSpeed: 38, waveHeight: 1.2,
            summary: "Wind and waves exceed your selected safety limits.", isFavorite: false
        )
    ]
}

