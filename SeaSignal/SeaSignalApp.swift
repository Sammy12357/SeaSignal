import SwiftUI

@main
struct SeaSignalApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .tint(.oceanBlue)
        }
        .backgroundTask(.appRefresh(WeeklyNotificationService.backgroundIdentifier)) {
            await BackgroundForecastRefresh.run()
        }
    }
}
