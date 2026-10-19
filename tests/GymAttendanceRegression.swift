import Foundation

@main
struct GymAttendanceRegression {
    static func main() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12) -> Date {
            calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
        }
        func workout(_ day: Date, done: Bool = true, finished: Bool = true) -> Workout {
            Workout(name: "Gym", startedAt: day, endedAt: finished ? day.addingTimeInterval(600) : nil,
                    entries: [ExerciseEntry(exerciseID: UUID(), sets: [WorkSet(weight: 24, reps: 10, done: done)])])
        }
        let now = date(2026, 3, 30)
        let sunday = date(2026, 3, 29)
        let history = [workout(sunday), workout(date(2026, 3, 29, 18)), workout(now),
                       workout(date(2026, 3, 28), done: false),
                       workout(date(2026, 3, 27), finished: false), workout(date(2026, 4, 1))]
        let grid = GymAttendance(history: history, now: now, calendar: calendar)
        precondition(grid.weeks.count == 52)
        precondition(grid.weeks.allSatisfy { $0.count == 7 })
        precondition(Set(grid.weeks.flatMap { $0 }).count == 364)
        precondition(grid.weeks.allSatisfy { calendar.component(.weekday, from: $0[0]) == 2 })
        precondition(grid.weeks.last![0] == calendar.startOfDay(for: now))
        precondition(grid.visibleGymDays == 2 && grid.daysThisWeek == 1)
        precondition(grid.workouts(on: sunday).count == 2)
        precondition(grid.lastVisit == calendar.startOfDay(for: now))
        // Spring daylight saving must not skip a day or shift squares away from midnight.
        precondition(grid.weeks.flatMap { $0 }.allSatisfy { calendar.component(.hour, from: $0) == 0 })
        let sundayGrid = GymAttendance(history: history, now: date(2026, 3, 29, 23), calendar: calendar)
        precondition(sundayGrid.weeks.last![6] == calendar.startOfDay(for: sunday))
        precondition(sundayGrid.visibleGymDays == 1 && sundayGrid.daysThisWeek == 1)
        let yearBoundary = GymAttendance(history: [], now: date(2027, 1, 1), calendar: calendar)
        precondition(yearBoundary.weeks.last![0] == calendar.startOfDay(for: date(2026, 12, 28)))
        precondition(yearBoundary.lastVisit == nil && yearBoundary.visibleGymDays == 0)
        let oldVisit = workout(date(2020, 1, 1))
        let old = GymAttendance(history: [oldVisit], now: now, calendar: calendar)
        precondition(old.visibleGymDays == 0 && old.lastVisit != nil)
        print("Gym attendance regression checks passed")
    }
}
