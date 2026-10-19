import Foundation

/// Calendar-day attendance derived from saved workouts; no separate habit log to maintain.
struct GymAttendance {
    let today: Date
    let weeks: [[Date]]
    let workoutsByDay: [Date: [Workout]]
    let calendar: Calendar

    init(history: [Workout], now: Date = Date(), calendar: Calendar = .current, weekCount: Int = 52) {
        self.calendar = calendar
        today = calendar.startOfDay(for: now)
        // Monday at the top, Sunday at the bottom, regardless of the device's week preference.
        let daysSinceMonday = (calendar.component(.weekday, from: today) + 5) % 7
        let monday = calendar.date(byAdding: .day, value: -daysSinceMonday, to: today)!
        let count = max(1, weekCount)
        let start = calendar.date(byAdding: .day, value: -7 * (count - 1), to: monday)!
        weeks = (0..<count).map { week in
            (0..<7).map { day in calendar.date(byAdding: .day, value: week * 7 + day, to: start)! }
        }
        let completed = history.filter {
            $0.endedAt != nil && !$0.doneSets.isEmpty && $0.startedAt <= now
        }
        workoutsByDay = Dictionary(grouping: completed, by: { calendar.startOfDay(for: $0.startedAt) })
    }

    var lastVisit: Date? { workoutsByDay.keys.max() }
    var visibleGymDays: Int {
        weeks.flatMap { $0 }.filter { workoutsByDay[$0] != nil }.count
    }
    var daysThisWeek: Int {
        (weeks.last ?? []).filter { workoutsByDay[$0] != nil }.count
    }

    func workouts(on day: Date) -> [Workout] {
        (workoutsByDay[calendar.startOfDay(for: day)] ?? []).sorted { $0.startedAt > $1.startedAt }
    }
}
