import SwiftUI

/// GitHub-style grid of gym days: one column per week (Monday on top), newest week on the right.
/// Darker green means more sets that day. Scrolls back up to a year.
/// Tap a day to see its workouts below the grid (the last workout day is shown until then).
struct GymCalendar: View {
    @Environment(AppStore.self) private var store
    var weeks = 53

    private let cell: CGFloat = 14
    private let gap: CGFloat = 3

    @State private var selectedDay: Date?
    @State private var summary: Workout?

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
                                            if day == shownDay(sets) {
                                                RoundedRectangle(cornerRadius: 3).stroke(Color.accentColor, lineWidth: 2)
                                            } else if day == today {
                                                RoundedRectangle(cornerRadius: 3).stroke(Color.primary.opacity(0.6), lineWidth: 1)
                                            }
                                        }
                                        .contentShape(Rectangle())
                                        .onTapGesture {
                                            if sets[day] != nil { selectedDay = day }
                                        }
                                }
                            }
                        }
                    }
                }
                .defaultScrollAnchor(.trailing)
            }

            if let day = shownDay(sets) {
                dayDetails(day)
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
        .sheet(item: $summary) { workout in
            NavigationStack {
                WorkoutSummaryView(workout: workout, isSheet: true)
            }
            .environment(store)
        }
    }

    /// The tapped day, or the last workout day.
    private func shownDay(_ sets: [Date: Int]) -> Date? {
        selectedDay ?? sets.keys.max()
    }

    /// The date and each workout of that day: routine name and its exercises. Tapping one opens its summary.
    private func dayDetails(_ day: Date) -> some View {
        let workouts = store.history.filter { Self.calendar.startOfDay(for: $0.startedAt) == day }
        return VStack(alignment: .leading, spacing: 6) {
            Text(day.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            ForEach(workouts) { workout in
                Button {
                    summary = workout
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(workout.name)
                                .font(.subheadline.bold())
                                .foregroundStyle(.primary)
                            Text(exerciseNames(workout))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                        }
                        Spacer()
                        Text("\(workout.doneSets.count) sets")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Image(systemName: "chevron.right")
                            .font(.caption.bold())
                            .foregroundStyle(.tertiary)
                    }
                    .padding(10)
                    .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.borderless)
            }
        }
    }

    /// Exercises with at least one done set, or all of them if none were ticked off.
    private func exerciseNames(_ workout: Workout) -> String {
        let done = workout.entries.filter { $0.sets.contains(where: \.done) }
        return (done.isEmpty ? workout.entries : done)
            .map { store.exerciseName($0.exerciseID) }
            .joined(separator: ", ")
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
