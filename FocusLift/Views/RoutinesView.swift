import SwiftUI

struct RoutinesView: View {
    @Environment(AppStore.self) private var store
    @Environment(WorkoutEngine.self) private var engine
    @Binding var showWorkout: Bool
    @State private var path: [UUID] = []
    @State private var confirmCancel = false
    @State private var showGymVoice = false

    var body: some View {
        NavigationStack(path: $path) {
            List {
                if let active = store.activeWorkout {
                    Section {
                        Button {
                            showWorkout = true
                        } label: {
                            Label("Resume “\(active.name)”", systemImage: "play.circle.fill")
                                .font(.headline)
                        }
                        Button("Cancel workout", role: .destructive) { confirmCancel = true }
                    }
                }

                Section("Routines") {
                    let upNext = upNextRoutineID
                    ForEach(store.routines) { routine in
                        NavigationLink(value: routine.id) {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(routine.name).font(.headline)
                                    if routine.id == upNext {
                                        Text("Up next")
                                            .font(.caption2.bold())
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color.accentColor.opacity(0.2), in: Capsule())
                                            .foregroundStyle(Color.accentColor)
                                    }
                                    Spacer()
                                    Text(lastDoneText(store.lastDone(routine)))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Text(routine.entries.map { store.exerciseName($0.exerciseID) }.joined(separator: ", "))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }
                    }
                    .onDelete { store.routines.remove(atOffsets: $0) }
                    .onMove { store.routines.move(fromOffsets: $0, toOffset: $1) }
                }

                Section {
                    Button {
                        engine.start(routine: nil)
                        showWorkout = true
                    } label: {
                        Label("Start empty workout", systemImage: "plus.circle")
                    }
                    .disabled(store.activeWorkout != nil)
                }

                Section("Gym days") {
                    GymCalendar()
                }
            }
            .navigationTitle("Train")
            .confirmationDialog("Cancel this workout?", isPresented: $confirmCancel, titleVisibility: .visible) {
                Button("Cancel workout", role: .destructive) { engine.discard() }
                Button("Keep going", role: .cancel) {}
            } message: {
                Text("Stops the music and the voice. Nothing from this workout is saved.")
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { EditButton() }
                ToolbarItem(placement: .primaryAction) {
                    // Recording takes over the audio, so not while a workout plays music.
                    Button {
                        showGymVoice = true
                    } label: {
                        Image(systemName: "mic")
                    }
                    .disabled(store.activeWorkout != nil)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        let routine = Routine(name: "New routine")
                        store.routines.append(routine)
                        path.append(routine.id)
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showGymVoice) {
                GymVoiceSheet { path.append($0) }
            }
            .navigationDestination(for: UUID.self) { id in
                RoutineEditorView(routineID: id, showWorkout: $showWorkout)
            }
        }
    }

    /// The routine done longest ago (never done counts as oldest), when there are at least two.
    private var upNextRoutineID: UUID? {
        guard store.routines.count > 1 else { return nil }
        return store.routines.min { (store.lastDone($0) ?? .distantPast) < (store.lastDone($1) ?? .distantPast) }?.id
    }

    /// "Today", "Yesterday", "3 days ago · Tue", or "Never".
    private func lastDoneText(_ date: Date?) -> String {
        guard let date else { return "Never" }
        let calendar = Calendar.current
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: Date())).day ?? 0
        switch days {
        case ...0: return "Today"
        case 1: return "Yesterday"
        case 2..<7: return "\(days) days ago · \(date.formatted(.dateTime.weekday(.abbreviated)))"
        default: return "\(days) days ago · \(date.formatted(.dateTime.day().month(.abbreviated)))"
        }
    }
}

struct RoutineEditorView: View {
    @Environment(AppStore.self) private var store
    @Environment(WorkoutEngine.self) private var engine
    let routineID: UUID
    @Binding var showWorkout: Bool
    @State private var showPicker = false
    @State private var showReorder = false

    var body: some View {
        if let routine = store.routineBinding(routineID) {
            List {
                Section {
                    TextField("Routine name", text: routine.name)
                        .font(.title3.bold())
                }

                EntriesEditor(entries: routine.entries, mode: .routine)

                Section {
                    Button {
                        showPicker = true
                    } label: {
                        Label("Add exercise", systemImage: "plus.circle")
                    }
                    Button {
                        showReorder = true
                    } label: {
                        Label("Reorder exercises", systemImage: "arrow.up.arrow.down")
                    }
                    .disabled(routine.wrappedValue.entries.count < 2)
                }
            }
            .navigationTitle(routine.wrappedValue.name)
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
            .keyboardDoneButton()
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Start") {
                        engine.start(routine: routine.wrappedValue)
                        showWorkout = true
                    }
                    .bold()
                    .disabled(store.activeWorkout != nil || routine.wrappedValue.entries.isEmpty)
                }
            }
            .sheet(isPresented: $showPicker) {
                ExercisePickerView { exerciseID in
                    routine.wrappedValue.entries.append(
                        ExerciseEntry(exerciseID: exerciseID, sets: store.defaultSets(for: exerciseID)))
                }
            }
            .sheet(isPresented: $showReorder) {
                ReorderView(entries: routine.entries)
            }
        } else {
            ContentUnavailableView("Routine not found", systemImage: "questionmark.folder")
        }
    }
}
