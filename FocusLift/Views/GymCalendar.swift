import SwiftUI

/// GitHub-style grid of gym days: one column per week (Monday on top), newest week on the right.
/// Darker green means more sets that day. Scrolls back up to a year.
struct GymCalendar: View {
    @Environment(AppStore.self) private var store
    var weeks = 53

    private let cell: CGFloat = 14
    private let gap: CGFloat = 3

    private static var calendar: Calendar {
        var calendar = Calendar.current
        calendar.firstWeekday = 2
        return calendar
    }

    var body: some View {
        let calendar = Self.calendar
        let today = calendar.startOfDay(for: Date())
        let sets = setsPerDay()
        let thisWeek = calendar.dateInterval(of: .weekOfYear, for: today)?.start ?? today
        let firstWeek = calendar.date(byAdding: .weekOfYear, value: -(weeks - 1), to: thisWeek) ?? thisWeek

        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(lastWorkoutText(sets: sets, today: today))
                Spacer()
                let streak = weekStreak(sets: sets, thisWeek: thisWeek)
                if streak > 1 {
                    Label("\(streak) weeks in a row", systemImage: "flame.fill")
                        .foregroundStyle(.orange)
                }
            }
            .font(.subheadline.weight(.semibold))

            HStack(alignment: .top, spacing: gap) {
                VStack(spacing: gap) {
                    Color.clear.frame(width: 12, height: 12)
                    ForEach(0..<7, id: \.self) { day in
                        Text(day % 2 == 0 ? weekdayLetter(day) : "")
                            .frame(width: 12, height: cell)
                    }
                }
                .font(.system(size: 9))
                .foregroundStyle(.secondary)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: gap) {
                        ForEach(0..<weeks, id: \.self) { week in
                            let weekStart = calendar.date(byAdding: .weekOfYear, value: week, to: firstWeek) ?? firstWeek
                            VStack(spacing: gap) {
                                Text(monthLabel(weekStart, isFirst: week == 0))
                                    .font(.system(size: 9))
                                    .foregroundStyle(.secondary)
                                    .fixedSize()
                                    .frame(width: cell, height: 12, alignment: .leading)
                                ForEach(0..<7, id: \.self) { offset in
                                    let day = calendar.date(byAdding: .day, value: offset, to: weekStart) ?? weekStart
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(color(sets: sets[day] ?? 0, future: day > today))
                                        .frame(width: cell, height: cell)
                                        .overlay {
                                            if day == today {
                                                RoundedRectangle(cornerRadius: 3).stroke(Color.primary.opacity(0.6), lineWidth: 1)
                                            }
                                        }
                                }
                            }
                        }
                    }
                }
                .defaultScrollAnchor(.trailing)
            }

            HStack(spacing: gap) {
                Spacer()
                Text("Less")
                ForEach([0, 1, 10, 20], id: \.self) { count in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(color(sets: count, future: false))
                        .frame(width: 10, height: 10)
                }
                Text("More")
            }
            .font(.system(size: 9))
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
    }

    /// Done sets per day. A finished workout counts as at least one, so warm-up-only days still show.
    private func setsPerDay() -> [Date: Int] {
        var result: [Date: Int] = [:]
        for workout in store.history {
            result[Self.calendar.startOfDay(for: workout.startedAt), default: 0] += max(1, workout.doneSets.count)
        }
        return result
    }

    private func color(sets: Int, future: Bool) -> Color {
        if future { return .clear }
        switch sets {
        case 0: return Color.secondary.opacity(0.15)
        case 1..<10: return Color.green.opacity(0.4)
        case 10..<20: return Color.green.opacity(0.7)
        default: return Color.green
        }
    }

    private func lastWorkoutText(sets: [Date: Int], today: Date) -> String {
        guard let last = sets.keys.max() else { return "No workouts yet" }
        let days = Self.calendar.dateComponents([.day], from: last, to: today).day ?? 0
        switch days {
        case ...0: return "Last workout: today"
        case 1: return "Last workout: yesterday"
        default: return "Last workout: \(days) days ago"
        }
    }

    /// Weeks in a row with at least one workout, ending this week (or last week, if this one is still empty).
    private func weekStreak(sets: [Date: Int], thisWeek: Date) -> Int {
        let calendar = Self.calendar
        let trainedWeeks = Set(sets.keys.compactMap { calendar.dateInterval(of: .weekOfYear, for: $0)?.start })
        var week = trainedWeeks.contains(thisWeek) ? thisWeek : (calendar.date(byAdding: .weekOfYear, value: -1, to: thisWeek) ?? thisWeek)
        var streak = 0
        while trainedWeeks.contains(week) {
            streak += 1
            guard let previous = calendar.date(byAdding: .weekOfYear, value: -1, to: week) else { break }
            week = previous
        }
        return streak
    }

    /// Month name above the first column of each month.
    private func monthLabel(_ weekStart: Date, isFirst: Bool) -> String {
        let calendar = Self.calendar
        guard let previous = calendar.date(byAdding: .weekOfYear, value: -1, to: weekStart) else { return "" }
        let isNewMonth = calendar.component(.month, from: previous) != calendar.component(.month, from: weekStart)
        return isFirst || isNewMonth ? weekStart.formatted(.dateTime.month(.abbreviated)) : ""
    }

    /// "M", "W", "F", "S" for rows 0, 2, 4, 6 (Monday first).
    private func weekdayLetter(_ row: Int) -> String {
        let symbols = Self.calendar.veryShortWeekdaySymbols
        return symbols[(row + 1) % 7]
    }
}
