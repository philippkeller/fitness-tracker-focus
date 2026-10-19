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
        let recordSetIDs = Set(records.flatMap(\.hits).map(\.setID))
        List {
            if records.isEmpty {
                Section("Records") {
                    Text("No new records this time.")
                        .foregroundStyle(.secondary)
                }
            }
            ForEach(records) { record in
                Section {
                    VStack(spacing: 12) {
                        RecordCard(record: record, workoutName: workout.name, date: workout.startedAt)
                        RecordShareButton(record: record, workoutName: workout.name, date: workout.startedAt)
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }
            }

            Section {
                LabeledContent("Date", value: workout.startedAt.formatted(date: .abbreviated, time: .shortened))
                LabeledContent("Duration", value: Fmt.clock(workout.duration))
                LabeledContent("Sets", value: "\(workout.doneSets.count)")
                LabeledContent("Volume", value: Fmt.kg(workout.volume))
            }

            ForEach(workout.entries) { entry in
                Section(store.exerciseName(entry.exerciseID)) {
                    ForEach(Array(entry.sets.enumerated()), id: \.element.id) { index, set in
                        HStack {
                            Text("\(index + 1)")
                                .foregroundStyle(.secondary)
                                .frame(width: 24)
                            Text(Fmt.set(set))
                            if recordSetIDs.contains(set.id) {
                                Spacer()
                                Image(systemName: "medal.fill")
                                    .foregroundStyle(RecordCard.gold)
                            }
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

/// All completed sessions for a single exercise, including imported workouts.
struct ExerciseHistoryView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let exerciseID: UUID

    private struct Session: Identifiable {
        let workout: Workout
        let sets: [WorkSet]
        var id: UUID { workout.id }
    }

    private var sessions: [Session] {
        store.history.sorted { $0.startedAt > $1.startedAt }.compactMap { workout in
            // An exercise can occur more than once in a workout; keep all its logged sets.
            let sets = workout.entries
                .filter { $0.exerciseID == exerciseID }
                .flatMap(\.sets)
                .filter(\.done)
            return sets.isEmpty ? nil : Session(workout: workout, sets: sets)
        }
    }

    var body: some View {
        let sessions = sessions
        NavigationStack {
            List {
                ForEach(sessions) { session in
                    Section {
                        ForEach(Array(session.sets.enumerated()), id: \.element.id) { index, set in
                            LabeledContent("Set \(index + 1)") {
                                Text("\(Fmt.kg(set.weight)) × \(set.reps) reps")
                                    .monospacedDigit()
                                    .foregroundStyle(.primary)
                            }
                        }
                    } header: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(session.workout.startedAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.headline)
                            Text(session.workout.name)
                                .font(.caption)
                        }
                        .textCase(nil)
                    }
                }
            }
            .overlay {
                if sessions.isEmpty {
                    ContentUnavailableView(
                        "No history yet", systemImage: "clock.arrow.circlepath",
                        description: Text("Completed sets for this exercise will appear here after you finish a workout. Strong imports are included too."))
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
