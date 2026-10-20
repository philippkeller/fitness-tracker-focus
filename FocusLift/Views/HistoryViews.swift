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

    /// All record cards in one picture, for "Share all".
    @State private var allImage: Image?

    var body: some View {
        let records = store.records(in: workout)
        List {
            if !records.isEmpty {
                Section {
                    ForEach(records) { record in
                        RecordRow(record: record, date: workout.startedAt)
                            .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                            .listRowBackground(Color.clear)
                    }
                } header: {
                    HStack {
                        Text(records.count == 1 ? "New record" : "\(records.count) new records")
                        Spacer()
                        if records.count > 1, let allImage {
                            ShareLink(item: allImage, preview: SharePreview("\(workout.name) records", image: allImage)) {
                                Label("Share all", systemImage: "square.and.arrow.up")
                            }
                            .font(.caption.bold())
                        }
                    }
                }
            }

            Section {
                LabeledContent("Date", value: workout.startedAt.formatted(date: .abbreviated, time: .shortened))
                LabeledContent("Duration", value: Fmt.clock(workout.duration))
                LabeledContent("Sets", value: "\(workout.doneSets.count)")
                LabeledContent("Volume", value: Fmt.kg(workout.volume))
                if records.isEmpty {
                    LabeledContent("Records", value: "None this time")
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
        .onAppear {
            if records.count > 1, allImage == nil {
                allImage = RecordCard.shareImage(records, date: workout.startedAt)
            }
        }
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
