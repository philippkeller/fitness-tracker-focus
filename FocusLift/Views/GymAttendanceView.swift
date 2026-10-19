import SwiftUI

struct GymAttendanceView: View {
    @Environment(AppStore.self) private var store
    @State private var selectedDay: Date?
    private let cellSize: CGFloat = 16
    private let cellSpacing: CGFloat = 4

    var body: some View {
        // Refresh the day boundary if the home screen remains open overnight.
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let attendance = GymAttendance(history: store.history, now: context.date)
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(attendance.visibleGymDays) gym days")
                        .font(.headline)
                    Spacer()
                    Text("\(attendance.daysThisWeek) this week")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                HStack(alignment: .top, spacing: 6) {
                    VStack(spacing: cellSpacing) {
                        Color.clear.frame(height: 16)
                        ForEach(0..<7) { day in
                            Text(["Mon", "", "Wed", "", "Fri", "", "Sun"][day])
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                                .frame(width: 26, height: cellSize)
                                .accessibilityHidden(true)
                        }
                    }
                    ScrollView(.horizontal) {
                        HStack(alignment: .top, spacing: cellSpacing) {
                            ForEach(attendance.weeks, id: \.first) { week in
                                VStack(spacing: cellSpacing) {
                                    monthLabel(for: week[0], attendance: attendance)
                                    ForEach(week, id: \.self) { day in
                                        dayCell(day, attendance: attendance)
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .defaultScrollAnchor(.trailing)
                    .scrollIndicators(.hidden)
                }
                HStack {
                    Text("Last 52 weeks · swipe for earlier weeks")
                    Spacer(minLength: 4)
                    RoundedRectangle(cornerRadius: 3).fill(Color.green)
                        .frame(width: 10, height: 10)
                    Text("Gym day")
                }
                .font(.caption2)
                .foregroundStyle(.secondary)

                if let selectedDay {
                    let workouts = attendance.workouts(on: selectedDay)
                    Text(selectedDay.formatted(date: .abbreviated, time: .omitted))
                        .font(.subheadline.bold())
                    if workouts.isEmpty {
                        Text("No completed workouts on this day.")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        ForEach(workouts) { workout in
                            NavigationLink {
                                WorkoutSummaryView(workout: workout)
                            } label: {
                                Text(workout.name).font(.subheadline)
                            }
                        }
                    }
                } else if let last = attendance.lastVisit {
                    Text("Last gym visit: \(last.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("Finish your first workout to light up a day. Imported workouts count too.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func monthLabel(for monday: Date, attendance: GymAttendance) -> some View {
        let show = attendance.calendar.component(.day, from: monday) <= 7 || monday == attendance.weeks.first?.first
        return Text(show ? monday.formatted(.dateTime.month(.abbreviated)) : "")
            .font(.system(size: 9))
            .foregroundStyle(.secondary)
            .fixedSize()
            .frame(width: cellSize, height: 16, alignment: .leading)
            .accessibilityHidden(true)
    }

    private func dayCell(_ day: Date, attendance: GymAttendance) -> some View {
        let count = attendance.workouts(on: day).count
        let future = day > attendance.today
        return Button {
            selectedDay = day
        } label: {
            RoundedRectangle(cornerRadius: 3)
                .fill(count == 0 ? Color.secondary.opacity(0.16) : Color.green.opacity(count == 1 ? 0.65 : 1))
                .overlay {
                    if day == selectedDay || day == attendance.today {
                        RoundedRectangle(cornerRadius: 3)
                            .strokeBorder(day == selectedDay ? Color.primary : Color.secondary, lineWidth: 1)
                    }
                }
                .frame(width: cellSize, height: cellSize)
                .opacity(future ? 0 : 1)
        }
        .buttonStyle(.plain)
        .disabled(future)
        .accessibilityHidden(future)
        .accessibilityLabel("\(day.formatted(date: .complete, time: .omitted)), \(count) completed workouts")
        .accessibilityHint("Show workouts for this day")
    }
}
