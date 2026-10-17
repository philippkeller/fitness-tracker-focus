import SwiftUI

struct RoutinesView: View {
    @Environment(AppStore.self) private var store
    @Environment(WorkoutEngine.self) private var engine
    @Binding var showWorkout: Bool
    @State private var path: [UUID] = []

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
                    }
                }

                Section("Routines") {
                    ForEach(store.routines) { routine in
                        NavigationLink(value: routine.id) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(routine.name).font(.headline)
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
            }
            .navigationTitle("Train")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { EditButton() }
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
            .navigationDestination(for: UUID.self) { id in
                RoutineEditorView(routineID: id, showWorkout: $showWorkout)
            }
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
