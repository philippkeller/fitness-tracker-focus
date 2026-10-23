import SwiftUI
import UIKit

enum EditorMode {
    case routine
    case workout
}

/// Strong-style list of exercises with editable sets. Used for routines and the active workout.
struct EntriesEditor: View {
    @Environment(AppStore.self) private var store
    @Environment(WorkoutEngine.self) private var engine
    @Binding var entries: [ExerciseEntry]
    let mode: EditorMode
    /// "Previous" shows the last workout before this date.
    var previousBefore: Date = .distantFuture

    var body: some View {
        ForEach($entries) { $entry in
            EntrySection(
                entry: $entry,
                mode: mode,
                previous: store.previousSets(for: entry.exerciseID, before: previousBefore),
                currentSetID: mode == .workout ? engine.currentSetID : nil,
                onRemove: {
                    let id = entry.id
                    withAnimation { entries.removeAll { $0.id == id } }
                })
        }
    }
}

private struct EntrySection: View {
    @Environment(AppStore.self) private var store
    @Environment(WorkoutEngine.self) private var engine
    @Binding var entry: ExerciseEntry
    let mode: EditorMode
    let previous: [WorkSet]
    let currentSetID: UUID?
    let onRemove: () -> Void

    @State private var showHistory = false

    var body: some View {
        Section {
            NoteField(text: store.noteBinding(for: entry.exerciseID))
            SetHeaderRow(showCheck: mode == .workout)
            ForEach($entry.sets) { $set in
                let index = entry.sets.firstIndex { $0.id == set.id } ?? 0
                SetRow(
                    number: index + 1,
                    set: $set,
                    previous: previous[safe: index],
                    mode: mode,
                    isCurrent: set.id == currentSetID,
                    onCheck: { check(set.id) })
                .swipeActions {
                    Button(role: .destructive) {
                        let id = set.id
                        entry.sets.removeAll { $0.id == id }
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
            Button {
                let last = entry.sets.last
                entry.sets.append(WorkSet(weight: last?.weight ?? 0, reps: last?.reps ?? 10, rest: last?.rest ?? 90))
            } label: {
                Label("Add set", systemImage: "plus")
                    .frame(maxWidth: .infinity)
            }
        } header: {
            HStack {
                Text(store.exerciseName(entry.exerciseID))
                    .font(.headline)
                    .foregroundStyle(entry.skipped ? Color.secondary : Color.accentColor)
                    .strikethrough(entry.skipped)
                Spacer()
                Menu {
                    Button {
                        showHistory = true
                    } label: {
                        Label("History", systemImage: "clock.arrow.circlepath")
                    }
                    Menu("Rest for all sets") {
                        ForEach(Fmt.restOptions, id: \.self) { seconds in
                            Button(Fmt.rest(seconds)) {
                                for index in entry.sets.indices { entry.sets[index].rest = seconds }
                            }
                        }
                    }
                    if mode == .workout {
                        Button(entry.skipped ? "Don't skip" : "Skip exercise") { entry.skipped.toggle() }
                    }
                    Button("Remove exercise", role: .destructive, action: onRemove)
                } label: {
                    Image(systemName: "ellipsis.circle").font(.title3)
                }
            }
            .textCase(nil)
        }
        .sheet(isPresented: $showHistory) {
            ExerciseHistoryView(exerciseID: entry.exerciseID)
        }
    }

    private func check(_ setID: UUID) {
        if setID == currentSetID {
            // Same as an AirPods press: logs the set and starts the rest timer.
            engine.completeCurrentSet()
            return
        }
        guard let index = entry.sets.firstIndex(where: { $0.id == setID }) else { return }
        entry.sets[index].done.toggle()
        entry.sets[index].completedAt = entry.sets[index].done ? Date() : nil
    }
}

private struct NoteField: View {
    @Binding var text: String

    var body: some View {
        TextField("Note (machine settings, cues…)", text: $text, axis: .vertical)
            .font(.callout)
            .foregroundStyle(.yellow)
            .listRowBackground(Color.yellow.opacity(text.isEmpty ? 0.05 : 0.15))
    }
}

private struct SetHeaderRow: View {
    let showCheck: Bool

    var body: some View {
        HStack(spacing: 6) {
            Text("Set").frame(width: 28)
            Text("Previous").frame(maxWidth: .infinity)
            Text("kg").frame(width: 58)
            Text("Reps").frame(width: 44)
            Text("Rest").frame(width: 40)
            if showCheck {
                Image(systemName: "checkmark").frame(width: 34)
            }
        }
        .font(.caption.bold())
        .foregroundStyle(.secondary)
    }
}

private struct SetRow: View {
    let number: Int
    @Binding var set: WorkSet
    let previous: WorkSet?
    let mode: EditorMode
    let isCurrent: Bool
    let onCheck: () -> Void

    @FocusState private var weightFocused: Bool
    @FocusState private var repsFocused: Bool
    /// The reps field edits text, so the +/− buttons can change the number while it's being typed.
    @State private var repsText = ""
    /// Set when the reps field gets focus: the first key replaces the old number instead of adding to it.
    @State private var replaceReps = false

    var body: some View {
        HStack(spacing: 6) {
            Text("\(number)")
                .font(.callout.bold())
                .frame(width: 28, height: 30)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))

            Text(previous.map(Fmt.set) ?? "–")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity)

            TextField("kg", value: $set.weight, format: .number)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.center)
                .frame(width: 58, height: 30)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                .focused($weightFocused)
                .onChange(of: weightFocused) { _, focused in
                    // Select the whole number, so typing replaces it.
                    guard focused else { return }
                    DispatchQueue.main.async {
                        UIApplication.shared.sendAction(#selector(UIResponder.selectAll(_:)), to: nil, from: nil, for: nil)
                    }
                }

            TextField("reps", text: $repsText)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .frame(width: 44, height: 30)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                .focused($repsFocused)
                .overlay(alignment: .trailing) {
                    if repsFocused { repsStepper.keepsKeyboard().offset(x: 40) }
                }
                // Drawn above the rest column, which the buttons cover while editing.
                .zIndex(1)
                .onAppear { repsText = "\(set.reps)" }
                .onChange(of: repsText) { old, text in
                    if replaceReps, text != old {
                        replaceReps = false
                        repsText = Self.typed(old: old, new: text)
                        return
                    }
                    if let reps = Int(text), reps != set.reps { set.reps = reps }
                }
                .onChange(of: set.reps) { _, reps in
                    if Int(repsText) != reps {
                        replaceReps = false
                        repsText = "\(reps)"
                    }
                }
                .onChange(of: repsFocused) { _, focused in
                    guard focused else {
                        replaceReps = false
                        repsText = "\(set.reps)"
                        return
                    }
                    replaceReps = true
                    // Also highlight the number. Delayed, so it comes after the tap places the cursor.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        UIApplication.shared.sendAction(#selector(UIResponder.selectAll(_:)), to: nil, from: nil, for: nil)
                    }
                }

            Menu {
                ForEach(Fmt.restOptions, id: \.self) { seconds in
                    Button(Fmt.rest(seconds)) { set.rest = seconds }
                }
            } label: {
                Text(Fmt.rest(set.rest))
                    .font(.caption.monospacedDigit())
                    .frame(width: 40, height: 30)
            }

            if mode == .workout {
                Button(action: onCheck) {
                    Image(systemName: "checkmark")
                        .font(.callout.bold())
                        .frame(width: 34, height: 30)
                        .background(set.done ? Color.green : Color.secondary.opacity(0.25), in: RoundedRectangle(cornerRadius: 6))
                        .foregroundStyle(set.done ? Color.white : Color.primary)
                }
                .buttonStyle(.plain)
            }
        }
        .listRowBackground(set.done ? Color.green.opacity(0.15) : (isCurrent ? Color.accentColor.opacity(0.18) : nil))
    }

    /// What was typed into `old` to get `new`, wherever the cursor was.
    private static func typed(old: String, new: String) -> String {
        // Not longer: the highlighted number was replaced (or deleted), so `new` is what was typed.
        guard new.count > old.count else { return new }
        let prefix = zip(old, new).prefix { $0 == $1 }.count
        let maxSuffix = min(old.count, new.count) - prefix
        let suffix = zip(old.reversed(), new.reversed()).prefix { $0 == $1 }.count
        return String(new.dropFirst(prefix).dropLast(min(suffix, maxSuffix)))
    }

    /// + above, − below, to the right of the reps field. Only shown while the field is being edited.
    private var repsStepper: some View {
        VStack(spacing: 0) {
            Button {
                set.reps += 1
            } label: {
                Image(systemName: "plus")
                    .frame(width: 36, height: 20)
            }
            Divider()
            Button {
                set.reps = max(0, set.reps - 1)
            } label: {
                Image(systemName: "minus")
                    .frame(width: 36, height: 20)
            }
        }
        .font(.callout.bold())
        .buttonStyle(.borderless)
        .frame(width: 36)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
    }
}

struct ExercisePickerView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let onPick: (UUID) -> Void
    @State private var query = ""

    private var trimmed: String { query.trimmingCharacters(in: .whitespaces) }

    private var filtered: [Exercise] {
        let sorted = store.exercises.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return trimmed.isEmpty ? sorted : sorted.filter { $0.name.localizedCaseInsensitiveContains(trimmed) }
    }

    var body: some View {
        NavigationStack {
            List {
                if !trimmed.isEmpty,
                   !store.exercises.contains(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) {
                    Button {
                        let exercise = Exercise(name: trimmed)
                        store.exercises.append(exercise)
                        pick(exercise.id)
                    } label: {
                        Label("Create “\(trimmed)”", systemImage: "plus.circle.fill")
                    }
                }
                ForEach(filtered) { exercise in
                    Button {
                        pick(exercise.id)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(exercise.name).foregroundStyle(.primary)
                            let last = store.previousSets(for: exercise.id)
                            if !last.isEmpty {
                                Text("Last: " + last.map(Fmt.set).joined(separator: ", "))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search or create")
            .navigationTitle("Add exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func pick(_ id: UUID) {
        onPick(id)
        dismiss()
    }
}

struct ReorderView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Binding var entries: [ExerciseEntry]

    var body: some View {
        NavigationStack {
            List {
                ForEach(entries) { entry in
                    Text(store.exerciseName(entry.exerciseID))
                }
                .onMove { entries.move(fromOffsets: $0, toOffset: $1) }
                .onDelete { entries.remove(atOffsets: $0) }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Reorder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
