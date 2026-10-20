import SwiftUI

struct HistoryView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        NavigationStack {
            List {
                ForEach(store.history) { workout in
                    NavigationLink {
                        WorkoutSummaryView(workout: workout)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(workout.name).font(.headline)
                            Text("\(workout.startedAt.formatted(date: .abbreviated, time: .shortened)) · \(Fmt.clock(workout.duration)) · \(workout.doneSets.count) sets")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(workout.entries.map { store.exerciseName($0.exerciseID) }.joined(separator: ", "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                }
                .onDelete { store.history.remove(atOffsets: $0) }
            }
            .overlay {
                if store.history.isEmpty {
                    ContentUnavailableView(
                        "No workouts yet", systemImage: "clock",
                        description: Text("Finished workouts and Strong imports show up here."))
                }
            }
            .navigationTitle("History")
        }
    }
}

/// Shown after finishing a workout and for workouts in the history. Records compare against everything before it.
struct WorkoutSummaryView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let workout: Workout
    var isSheet = false

    var body: some View {
        let records = store.records(in: workout)
        List {
            Section {
                LabeledContent("Date", value: workout.startedAt.formatted(date: .abbreviated, time: .shortened))
                LabeledContent("Duration", value: Fmt.clock(workout.duration))
                LabeledContent("Sets", value: "\(workout.doneSets.count)")
                LabeledContent("Volume", value: Fmt.kg(workout.volume))
            }

            Section("Records") {
                if records.isEmpty {
                    Text("No new records this time.")
                        .foregroundStyle(.secondary)
                }
                ForEach(records) { record in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "trophy.fill")
                            .foregroundStyle(.yellow)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(record.exercise).font(.headline)
                            Text("\(record.kind.title): \(record.value)")
                            Text("Before: \(record.previous)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            ForEach(workout.entries) { entry in
                Section(store.exerciseName(entry.exerciseID)) {
                    ForEach(Array(entry.sets.enumerated()), id: \.element.id) { index, set in
                        HStack {
                            Text("\(index + 1)")
                                .foregroundStyle(.secondary)
                                .frame(width: 24)
                            Text(Fmt.set(set))
                        }
                    }
                }
            }
        }
        .navigationTitle(workout.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                if isSheet {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

/// Every past session of one exercise, newest first: date and the sets done that day.
struct ExerciseHistoryView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let exerciseID: UUID

    var body: some View {
        let sessions = store.sessions(for: exerciseID)
        NavigationStack {
            List {
                ForEach(sessions, id: \.workout.id) { session in
                    Section {
                        ForEach(Array(session.sets.enumerated()), id: \.element.id) { index, set in
                            HStack {
                                Text("\(index + 1)")
                                    .foregroundStyle(.secondary)
                                    .frame(width: 24)
                                Text(Fmt.set(set))
                            }
                        }
                    } header: {
                        HStack {
                            Text(session.workout.startedAt.formatted(date: .abbreviated, time: .omitted))
                            Spacer()
                            Text(session.workout.name)
                        }
                    }
                }
            }
            .overlay {
                if sessions.isEmpty {
                    ContentUnavailableView(
                        "No history yet", systemImage: "clock",
                        description: Text("Finished workouts with this exercise show up here."))
                }
            }
            .navigationTitle(store.exerciseName(exerciseID))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
