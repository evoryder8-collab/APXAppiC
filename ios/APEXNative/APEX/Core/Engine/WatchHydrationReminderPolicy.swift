import Foundation

enum WatchHydrationReminderPolicy {
    static func nextReminderDate(
        now: Date,
        liters: Double,
        lastDrinkAt: Date?,
        preferences: WatchHydrationPreferences,
        calendar: Calendar = .current
    ) -> Date? {
        guard preferences.remindersEnabled,
              liters.isFinite,
              liters >= 0,
              liters < preferences.targetLiters,
              preferences.quietHoursStartMinutes > preferences.quietHoursEndMinutes
        else { return nil }

        let dayStart = calendar.startOfDay(for: now)
        guard let activeStart = calendar.date(
            byAdding: .minute,
            value: preferences.quietHoursEndMinutes,
            to: dayStart
        ), let activeEnd = calendar.date(
            byAdding: .minute,
            value: preferences.quietHoursStartMinutes,
            to: dayStart
        ), now < activeEnd else { return nil }

        let activeMinutes = activeEnd.timeIntervalSince(activeStart) / 60
        guard activeMinutes > 0 else { return nil }

        let effectiveNow = max(now, activeStart)
        let baselineDrink = max(lastDrinkAt ?? activeStart, activeStart)
        let inactivityDate = calendar.date(
            byAdding: .minute,
            value: preferences.reminderIntervalMinutes,
            to: baselineDrink
        ) ?? baselineDrink
        let earliestVisibleDate = calendar.date(byAdding: .minute, value: 1, to: effectiveNow) ?? effectiveNow

        let paceFraction = min(1, max(0, (liters + 0.25) / preferences.targetLiters))
        let paceDate = activeStart.addingTimeInterval(activeMinutes * paceFraction * 60)
        let candidate = max(earliestVisibleDate, inactivityDate, paceDate)

        return candidate < activeEnd ? candidate : nil
    }
}
