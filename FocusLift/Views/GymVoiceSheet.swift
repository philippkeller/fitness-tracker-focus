import SwiftUI

/// New gym: say which machines it has, check the list, get a routine built from your exercises.
struct GymVoiceSheet: View {
    private enum Phase {
        case recording
        case processing
        case review
        case failed(String)
    }

    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    /// Called with the new routine's id.
    let onCreate: (UUID) -> Void

    @State private var phase: Phase = .recording
    @State private var transcripts: [String] = []
    @State private var routineName = "New gym"
    @State private var suggestions: [GymVoice.Suggestion] = []
    @State private var recorder = VoiceRecorder()

    private var includedCount: Int { suggestions.filter(\.isIncluded).count }

    private var isReviewing: Bool {
        if case .review = phase { return true }
        return false
    }

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .recording:
                    recordingView
                case .processing:
                    VStack(spacing: 16) {
                        ProgressView()
                            .controlSize(.large)
                        Text("Matching with your exercises…")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .review:
                    reviewView
                case .failed(let message):
                    ContentUnavailableView {
                        Label("That didn't work", systemImage: "exclamationmark.bubble")
                    } description: {
                        Text(message)
                    } actions: {
                        Button("Try again") { Task { await startRecording() } }
                            .buttonStyle(.borderedProminent)
                        if !suggestions.isEmpty {
                            Button("Back to the list") { phase = .review }
                        }
                    }
                }
            }
            .navigationTitle("New gym")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        recorder.cancel()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isReviewing {
                        Button("Create") { create() }
                            .disabled(includedCount == 0)
                    }
                }
            }
        }
        .task { await startRecording() }
        .onDisappear { recorder.cancel() }
    }

    private var recordingView: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "waveform")
                .font(.system(size: 64))
                .foregroundStyle(Color.accentColor)
                .symbolEffect(.variableColor.iterative, options: .repeating)
            Text("Listening…")
                .font(.title3.weight(.semibold))
            Text("e.g. “Es hat eine Beinpresse, einen Latzug, Leg Curl sitzend und Kabelzüge.”")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Spacer()
            Button {
                Task { await finishRecording() }
            } label: {
                Label("Done", systemImage: "stop.fill")
                    .font(.title3.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .padding()
        }
    }

    private var reviewView: some View {
        List {
            Section("Routine name") {
                TextField("Routine name", text: $routineName)
            }
            Section {
                ForEach(transcripts, id: \.self) { transcript in
                    Text("“\(transcript)”")
                        .italic()
                        .foregroundStyle(.secondary)
                }
            }
            if suggestions.isEmpty {
                Section {
                    Text("No machines recognized.")
                }
            } else {
                Section {
                    ForEach($suggestions) { $suggestion in
                        suggestionRow($suggestion)
                    }
                } footer: {
                    Text("Tap to leave one out. Every exercise here becomes a separate copy, so changing it never changes your other routines. Notes start empty. New exercises start at 0 kg.")
                }
            }
            Section {
                Button {
                    Task { await startRecording() }
                } label: {
                    Label("Add more machines", systemImage: "mic.fill")
                }
            }
        }
    }

    private func suggestionRow(_ suggestion: Binding<GymVoice.Suggestion>) -> some View {
        let s = suggestion.wrappedValue
        return HStack(spacing: 12) {
            Image(systemName: s.isIncluded ? "checkmark.circle.fill" : "circle")
                .font(.title2)
                .foregroundStyle(s.isIncluded ? Color.accentColor : Color(.tertiaryLabel))
            VStack(alignment: .leading, spacing: 2) {
                Text(s.name)
                    .fontWeight(.semibold)
                Text(detail(for: s))
                    .font(.caption)
                    .foregroundStyle(s.existingID == nil ? Color.orange : Color.secondary)
            }
            Spacer()
        }
        .contentShape(Rectangle())
        .onTapGesture { suggestion.wrappedValue.isIncluded.toggle() }
    }

    private func detail(for suggestion: GymVoice.Suggestion) -> String {
        if let id = suggestion.existingID {
            return "copy of your exercise · \(setsText(store.defaultSets(for: id)))"
        }
        if let id = suggestion.similarID {
            return "new · sets like \(store.exerciseName(id))"
        }
        return "new · 3 × 10"
    }

    private func setsText(_ sets: [WorkSet]) -> String {
        guard let first = sets.first else { return "no sets" }
        return "\(sets.count) × \(Fmt.set(first))"
    }

    private func startRecording() async {
        phase = .recording
        do {
            try await recorder.start()
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    private func finishRecording() async {
        guard let audio = recorder.stop(), audio.count > 1000 else {
            phase = .failed("Nothing recorded.")
            return
        }
        phase = .processing
        do {
            let result = try await GymVoice.suggestions(forAudio: audio, exercises: store.exercises)
            if !result.transcript.isEmpty { transcripts.append(result.transcript) }
            if let name = result.routineName, routineName == "New gym" { routineName = name }
            let known = Set(suggestions.map { $0.name.lowercased() })
            suggestions += result.suggestions.filter { !known.contains($0.name.lowercased()) }
            phase = .review
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    /// Every exercise in the new routine is a new exercise of its own, so changing it here never
    /// changes the exercises of your other routines. The note starts empty: the old gym's machine
    /// settings don't fit the new machines.
    private func create() {
        var entries: [ExerciseEntry] = []
        for suggestion in suggestions where suggestion.isIncluded {
            let exercise = Exercise(name: suggestion.name)
            store.exercises.append(exercise)
            let sets: [WorkSet]
            if let original = suggestion.existingID {
                // Copy of your exercise: same sets, reps, weights and rest as last time.
                sets = store.defaultSets(for: original)
            } else if let similar = suggestion.similarID {
                // Same number of sets, reps and rest as the similar exercise; the weight is unknown on a new machine.
                sets = store.defaultSets(for: similar).map { WorkSet(weight: 0, reps: $0.reps, rest: $0.rest) }
            } else {
                sets = store.defaultSets(for: exercise.id)
            }
            entries.append(ExerciseEntry(exerciseID: exercise.id, sets: sets))
        }
        let name = routineName.trimmingCharacters(in: .whitespacesAndNewlines)
        let routine = Routine(name: name.isEmpty ? "New gym" : name, entries: entries)
        store.routines.append(routine)
        dismiss()
        onCreate(routine.id)
    }
}
