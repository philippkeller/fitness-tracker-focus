import SwiftUI

struct ActiveWorkoutView: View {
    @Environment(AppStore.self) private var store
    @Environment(WorkoutEngine.self) private var engine
    @Environment(\.dismiss) private var dismiss
    let onFinish: (Workout) -> Void

    @State private var showPicker = false
    @State private var showReorder = false
    @State private var confirmFinish = false
    @State private var confirmDiscard = false

    var body: some View {
        NavigationStack {
            Group {
                if let workout = store.activeWorkoutBinding {
                    List {
                        Section { StatusCard() }

                        if Prefs.subsonicClient != nil {
                            Section { MusicBar() }
                        }

                        EntriesEditor(entries: workout.entries, mode: .workout, previousBefore: workout.wrappedValue.startedAt)

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
                            .disabled(workout.wrappedValue.entries.count < 2)
                        }

                        Section {
                            Button("Discard workout", role: .destructive) { confirmDiscard = true }
                        }
                    }
                    .navigationTitle(workout.wrappedValue.name)
                    .scrollDismissesKeyboard(.interactively)
                    .sheet(isPresented: $showPicker) {
                        ExercisePickerView { exerciseID in
                            workout.wrappedValue.entries.append(
                                ExerciseEntry(exerciseID: exerciseID, sets: store.defaultSets(for: exerciseID)))
                        }
                    }
                    .sheet(isPresented: $showReorder) {
                        ReorderView(entries: workout.entries)
                    }
                } else {
                    ContentUnavailableView("No active workout", systemImage: "figure.strengthtraining.traditional")
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .keyboardDoneButton()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.down")
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Finish") { confirmFinish = true }
                        .bold()
                        .tint(.green)
                        .disabled(store.activeWorkout == nil)
                }
            }
            .confirmationDialog("Finish workout?", isPresented: $confirmFinish, titleVisibility: .visible) {
                if store.activeWorkout?.routineID != nil {
                    Button("Finish & update routine") { finish(updateRoutine: true) }
                    Button("Finish, keep routine as is") { finish(updateRoutine: false) }
                } else {
                    Button("Finish") { finish(updateRoutine: false) }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(finishMessage)
            }
            .confirmationDialog("Discard this workout?", isPresented: $confirmDiscard, titleVisibility: .visible) {
                Button("Discard", role: .destructive) {
                    engine.discard()
                    dismiss()
                }
            }
        }
    }

    private var finishMessage: String {
        let open = store.activeWorkout?.entries.filter { !$0.skipped }.flatMap(\.sets).filter { !$0.done }.count ?? 0
        let base = "Updating the routine saves today's weights, reps and exercise order for next time."
        return open > 0 ? "\(open) unfinished sets will be dropped. " + base : base
    }

    private func finish(updateRoutine: Bool) {
        guard let workout = engine.finish(updateRoutine: updateRoutine) else { return }
        dismiss()
        onFinish(workout)
    }
}

private struct StatusCard: View {
    @Environment(WorkoutEngine.self) private var engine

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Label(Fmt.clock(engine.elapsed), systemImage: "timer")
                Spacer()
                Text(engine.progressText)
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)

            switch engine.phase {
            case .resting(let until, let total):
                restingView(until: until, total: total)
            case .lifting, .idle:
                liftingView
            case .complete:
                completeView
            }

            Text(airPodsHint)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
    }

    private var airPodsHint: String {
        let double = Prefs.doublePressSkipsSong ? "next song / skip exercise" : "skip exercise"
        return "AirPods: 1× done / skip rest · 2× \(double) · 3× repeat"
    }

    @ViewBuilder
    private func restingView(until: Date, total: Int) -> some View {
        let remaining = max(0, until.timeIntervalSince(engine.now))
        Text("Rest")
            .font(.headline)
            .foregroundStyle(.secondary)
        Text(Fmt.clock(remaining))
            .font(.system(size: 64, weight: .bold, design: .rounded).monospacedDigit())
        ProgressView(value: min(Double(total), max(0, Double(total) - remaining)), total: Double(total))
        if let next = engine.currentInfo {
            Text("Next: \(next.exercise) · set \(next.number)/\(next.count) · \(Fmt.load(weight: next.weight, reps: next.reps))")
                .font(.subheadline)
                .multilineTextAlignment(.center)
        }
        HStack {
            Button("−15s") { engine.adjustRest(by: -15) }
                .buttonStyle(.bordered)
            Button("+15s") { engine.adjustRest(by: 15) }
                .buttonStyle(.bordered)
            Button {
                engine.primaryAction()
            } label: {
                Label("Skip rest", systemImage: "forward.fill")
            }
            .buttonStyle(.borderedProminent)
        }
        secondaryButtons
    }

    @ViewBuilder
    private var liftingView: some View {
        if let current = engine.currentInfo {
            Text(current.exercise)
                .font(.title2.bold())
                .multilineTextAlignment(.center)
            Text("Set \(current.number) of \(current.count) · \(Fmt.load(weight: current.weight, reps: current.reps))")
                .font(.headline)
                .foregroundStyle(.secondary)
            Button {
                engine.primaryAction()
            } label: {
                Label("Set done", systemImage: "checkmark")
                    .font(.title3.bold())
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            secondaryButtons
        } else {
            Text("Add an exercise to get started.")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var completeView: some View {
        Text("All sets done 💪")
            .font(.title2.bold())
        if engine.currentInfo != nil {
            Button("Continue with the new sets") { engine.primaryAction() }
                .buttonStyle(.borderedProminent)
        } else {
            Text("Tap Finish to save the workout.")
                .foregroundStyle(.secondary)
        }
    }

    private var secondaryButtons: some View {
        HStack {
            Button {
                engine.repeatAnnouncement()
            } label: {
                Label("Repeat", systemImage: "speaker.wave.2")
            }
            .buttonStyle(.bordered)
            Button {
                engine.skipExercise()
            } label: {
                Label("Skip exercise", systemImage: "forward.end")
            }
            .buttonStyle(.bordered)
        }
        .font(.callout)
    }
}

private struct MusicBar: View {
    @Environment(MusicPlayer.self) private var music
    @State private var showPicker = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 16) {
                Image(systemName: "music.note")
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(music.currentSong?.title ?? "No music playing")
                        .lineLimit(1)
                    if let artist = music.currentSong?.artist {
                        Text(artist)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer()
                Button {
                    music.togglePause()
                } label: {
                    Image(systemName: music.isPlaying ? "pause.fill" : "play.fill")
                }
                .buttonStyle(.borderless)
                .disabled(music.queue.isEmpty)
                Button {
                    music.next()
                } label: {
                    Image(systemName: "forward.fill")
                }
                .buttonStyle(.borderless)
                .disabled(music.queue.isEmpty)
                Button {
                    showPicker = true
                } label: {
                    Image(systemName: "music.note.list")
                }
                .buttonStyle(.borderless)
            }
            if let error = music.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .sheet(isPresented: $showPicker) {
            MusicPickerView()
        }
    }
}

private struct MusicPickerView: View {
    @Environment(MusicPlayer.self) private var music
    @Environment(\.dismiss) private var dismiss
    @AppStorage(Prefs.shuffleKey) private var shuffle = true
    @State private var loading = true

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle("Shuffle", isOn: $shuffle)
                    Button {
                        play(nil)
                    } label: {
                        Label("Random mix", systemImage: "shuffle")
                    }
                }
                Section("Playlists") {
                    if loading {
                        ProgressView()
                    } else if music.playlists.isEmpty {
                        Text("No playlists found.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(music.playlists) { playlist in
                        Button {
                            play(playlist.id)
                        } label: {
                            HStack {
                                Text(playlist.name).foregroundStyle(.primary)
                                Spacer()
                                if let count = playlist.songCount {
                                    Text("\(count)").foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                if let error = music.errorMessage {
                    Section {
                        Text(error).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Music")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .task {
                await music.loadPlaylists()
                loading = false
            }
        }
    }

    private func play(_ playlistID: String?) {
        let shuffle = shuffle
        Task { await music.play(playlistID: playlistID, shuffle: shuffle) }
        dismiss()
    }
}
