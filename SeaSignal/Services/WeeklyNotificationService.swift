import BackgroundTasks
import Foundation
import UserNotifications

enum WeeklyNotificationService {
    static let backgroundIdentifier = "com.seasignal.app.weekly-refresh"
    static let notificationIdentifier = "seasignal.weekly-recommendation"

    static func requestAuthorization() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    static func update(using launches: [BoatLaunch], defaults: UserDefaults = .standard) async {
        let enabled = defaults.bool(forKey: "weeklyNotificationsEnabled")
        guard enabled else {
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [notificationIdentifier])
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: backgroundIdentifier)
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "Best boating window this week"
        if let best = launches
            .filter({ $0.conditions != .loading })
            .max(by: { ($0.recommendationScore ?? -1) < ($1.recommendationScore ?? -1) }),
           best.conditions != .avoid {
            content.body = "\(best.name): launch \(best.launchTime), retrieve \(best.retrievalTime). \(best.summary)"
        } else {
            content.body = "No favorite launch has a safe window within your limits this week."
        }
        content.sound = .default

        let weekday = defaults.object(forKey: "notificationWeekday") == nil ? 5 : defaults.integer(forKey: "notificationWeekday")
        let hour = defaults.object(forKey: "notificationHour") == nil ? 18 : defaults.integer(forKey: "notificationHour")
        var components = DateComponents()
        components.calendar = Calendar.current
        components.weekday = min(7, max(1, weekday))
        components.hour = min(23, max(0, hour))
        components.minute = 0
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let request = UNNotificationRequest(identifier: notificationIdentifier, content: content, trigger: trigger)
        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            return
        }
        scheduleBackgroundRefresh()
    }

    static func scheduleBackgroundRefresh() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: backgroundIdentifier)
        let request = BGAppRefreshTaskRequest(identifier: backgroundIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 12 * 60 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }
}

enum BackgroundForecastRefresh {
    static func run() async {
        defer { WeeklyNotificationService.scheduleBackgroundRefresh() }
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: "weeklyNotificationsEnabled"),
              let data = defaults.data(forKey: "savedFavoriteLaunches"),
              var launches = try? JSONDecoder().decode([BoatLaunch].self, from: data) else { return }

        let service = MarineForecastService()
        let preferences = AppPreferences.load(from: defaults)
        await withTaskGroup(of: (String, MarineForecast?).self) { group in
            for launch in launches {
                group.addTask {
                    (launch.id, try? await service.forecast(for: launch, preferences: preferences))
                }
            }
            for await (id, forecast) in group {
                guard let forecast, let index = launches.firstIndex(where: { $0.id == id }) else { continue }
                launches[index].apply(forecast)
            }
        }
        if let updated = try? JSONEncoder().encode(launches) {
            defaults.set(updated, forKey: "savedFavoriteLaunches")
        }
        await WeeklyNotificationService.update(using: launches, defaults: defaults)
    }
}

extension BoatLaunch {
    mutating func apply(_ forecast: MarineForecast) {
        conditions = forecast.conditions
        launchTime = forecast.launchTime
        retrievalTime = forecast.retrievalTime
        highTide = forecast.highTide
        lowTide = forecast.lowTide
        tideSource = forecast.tideSource
        windSpeed = forecast.windSpeed
        gustSpeed = forecast.gustSpeed
        waveHeight = forecast.waveHeight
        wavePeriod = forecast.wavePeriod
        rainChance = forecast.rainChance
        recommendationScore = forecast.score
        rationale = forecast.rationale
        forecastIsStale = forecast.isStale
        summary = forecast.summary
        forecastUpdatedAt = forecast.updatedAt
    }
}

