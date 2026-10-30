import AVFoundation
import Foundation
import Observation

struct SetPosition: Equatable {
    var entry: Int
    var set: Int
}

/// Runs the active workout: tracks the current set, the rest timer, AirPods presses and announcements.
///
/// AirPods: 1× = set done / skip rest, 2× = repeat announcement, 3× = say the time.
/// Songs are never skipped with the AirPods, only in the app.
@Observable
final class WorkoutEngine {
    enum Phase: Equatable {
        case idle
        case lifting
        case resting(until: Date, total: Int)
        case complete
    }

    private(set) var phase: Phase = .idle
    private(set) var now = Date()

    let store: AppStore
    let music: MusicPlayer
    let blocker: AppBlocker
    private let audio: AudioController
    private let speaker: Speaker
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var warnedTenSeconds = false
    @ObservationIgnored private var lastCompleted: SetPosition?

    init(store: AppStore, music: MusicPlayer, blocker: AppBlocker, audio: AudioController, speaker: Speaker) {
        self.store = store
        self.music = music
        self.blocker = blocker
        self.audio = audio
        self.speaker = speaker

        audio.onPrimary = { [weak self] in self?.primaryAction() }
        audio.onNext = { [weak self] in self?.repeatAnnouncement() }
        audio.onPrevious = { [weak self] in self?.sayTime() }
        audio.onInterruptionEnded = { [weak music] in music?.resumeAfterInterruption() }
        music.onTrackChange = { [weak self] in self?.updateNowPlaying() }
        speaker.onSpeakingChanged = { [weak music] speaking in music?.setDucked(speaking) }

        if store.activeWorkout != nil {
            begin(announce: false)
        } else {
            // Clean up shields left over if the app was killed mid-workout and the workout is gone.
            blocker.unblock()
        }
    }

    private var phrases: Phrases { Phrases() }

    // MARK: State for the UI

    /// First set that isn't done, skipping skipped exercises.
    var currentPosition: SetPosition? {
        guard let workout = store.activeWorkout else { return nil }
        for (entryIndex, entry) in workout.entries.enumerated() where !entry.skipped {
            if let setIndex = entry.sets.firstIndex(where: { !$0.done }) {
                return SetPosition(entry: entryIndex, set: setIndex)
            }
        }
        return nil
    }

    var currentSetID: UUID? {
        guard let position = currentPosition else { return nil }
        return store.activeWorkout?.entries[position.entry].sets[position.set].id
    }

    var currentInfo: SetInfo? {
        currentPosition.flatMap { info($0) }
    }

    var elapsed: TimeInterval {
        guard let start = store.activeWorkout?.startedAt else { return 0 }
        return now.timeIntervalSince(start)
    }

    var progressText: String {
        let sets = store.activeWorkout?.entries.filter { !$0.skipped }.flatMap(\.sets) ?? []
        return "\(sets.filter(\.done).count)/\(sets.count) sets"
    }

    // MARK: Lifecycle

    func start(routine: Routine?) {
        store.startWorkout(from: routine)
        lastCompleted = nil
        begin(announce: true)
        // Continue the music where the last workout left it.
        music.resumeIfIdle()
    }

    private func begin(announce: Bool) {
        audio.start()
        blocker.block()
        startTimer()
        if let entries = store.activeWorkout?.entries {
            let sentences = phrases.allSentences(for: entries, store: store)
            Task { _ = await Self.prepareVoice(sentences) }
        }
        if let position = currentPosition, let info = info(position) {
            phase = .lifting
            if announce {
                say([phrases.started] + phrases.set(info, withName: true, withNote: true))
            }
        } else {
            phase = .complete
        }
        updateNowPlaying()
    }

    func finish(updateRoutine: Bool) -> Workout? {
        tearDown()
        return store.finishActiveWorkout(updateRoutine: updateRoutine)
    }

    func discard() {
        tearDown()
        store.activeWorkout = nil
        store.save()
    }

    private func tearDown() {
        timer?.invalidate()
        timer = nil
        speaker.stop()
        music.stop()
        audio.stop()
        blocker.unblock()
        phase = .idle
    }

    // MARK: Actions

    /// Single AirPods press or the big button: set done, or skip the rest.
    func primaryAction() {
        switch phase {
        case .idle:
            return
        case .lifting:
            completeCurrentSet()
        case .resting:
            endRest()
        case .complete:
            // Sets may have been added after everything was done.
            if let position = currentPosition, let info = info(position) {
                phase = .lifting
                say([phrases.go] + phrases.set(info, withName: true, withNote: true))
                updateNowPlaying()
            } else {
                say([phrases.complete])
            }
        }
    }

    func completeCurrentSet() {
        guard let position = currentPosition else { return }
        complete(position)
    }

    /// Check mark on a set that isn't the current one, e.g. an exercise done out of order because the machine
    /// was taken. Its exercise moves up to the current spot, so the rest timer starts and its next sets follow.
    /// Returns false if there's no running workout.
    @discardableResult
    func completeSet(id: UUID) -> Bool {
        guard phase != .idle, var workout = store.activeWorkout,
              var entryIndex = workout.entries.firstIndex(where: { entry in entry.sets.contains { $0.id == id } }) else { return false }
        if let current = currentPosition, entryIndex > current.entry {
            let entry = workout.entries.remove(at: entryIndex)
            workout.entries.insert(entry, at: current.entry)
            entryIndex = current.entry
        }
        workout.entries[entryIndex].skipped = false
        guard let setIndex = workout.entries[entryIndex].sets.firstIndex(where: { $0.id == id }) else { return false }
        store.activeWorkout = workout
        complete(SetPosition(entry: entryIndex, set: setIndex))
        return true
    }

    private func complete(_ position: SetPosition) {
        guard phase != .idle, var workout = store.activeWorkout else { return }
        workout.entries[position.entry].sets[position.set].done = true
        workout.entries[position.entry].sets[position.set].completedAt = Date()
        store.activeWorkout = workout
        lastCompleted = position
        let rest = workout.entries[position.entry].sets[position.set].rest

        guard let next = currentPosition, let nextInfo = info(next) else {
            phase = .complete
            say([phrases.complete])
            updateNowPlaying()
            return
        }

        // Say the name and setup note during the rest before a new exercise, so there's time to set up the machine.
        let newExercise = next.entry != position.entry
        if rest <= 0 {
            phase = .lifting
            say([phrases.go] + phrases.set(nextInfo, withName: newExercise, withNote: newExercise))
        } else {
            phase = .resting(until: Date().addingTimeInterval(TimeInterval(rest)), total: rest)
            warnedTenSeconds = rest <= 20
            say([phrases.rest(rest), phrases.next] + phrases.set(nextInfo, withName: newExercise, withNote: newExercise))
        }
        updateNowPlaying()
    }

    func skipExercise() {
        guard let position = currentPosition else { return }
        store.activeWorkout?.entries[position.entry].skipped = true
        lastCompleted = position
        if let next = currentPosition, let info = info(next) {
            phase = .lifting
            say([phrases.skipped] + phrases.set(info, withName: true, withNote: true))
        } else {
            phase = .complete
            say([phrases.complete])
        }
        updateNowPlaying()
    }

    /// "Es ist 12 Uhr 25." with the iPhone voice.
    func sayTime() {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: Date())
        let hour = parts.hour ?? 0, minute = parts.minute ?? 0
        let text = Prefs.language == "de"
            ? (minute == 0 ? "Es ist \(hour) Uhr." : "Es ist \(hour) Uhr \(minute).")
            : String(format: "It's %d:%02d.", hour, minute)
        speaker.speakWithIPhoneVoice(text, language: Prefs.language)
    }

    func repeatAnnouncement() {
        switch phase {
        case .idle:
            return
        case .resting(let until, _):
            // Rounded to 5 seconds so the voice can reuse cached audio.
            let seconds = max(5, Int((until.timeIntervalSinceNow / 5).rounded()) * 5)
            var parts = [phrases.remaining(seconds)]
            if let info = currentInfo {
                parts += [phrases.next] + phrases.set(info, withName: true, withNote: true)
            }
            say(parts)
        case .lifting:
            if let info = currentInfo {
                say(phrases.set(info, withName: true, withNote: true))
            }
        case .complete:
            say([phrases.complete])
        }
    }

    func adjustRest(by seconds: Int) {
        guard case .resting(let until, let total) = phase else { return }
        let newUntil = max(Date().addingTimeInterval(1), until.addingTimeInterval(TimeInterval(seconds)))
        phase = .resting(until: newUntil, total: max(1, total + seconds))
        if newUntil.timeIntervalSinceNow > 11 { warnedTenSeconds = false }
        updateNowPlaying()
    }

    /// Returns why the ElevenLabs voice wasn't used, or nil if it was.
    func testVoice() async -> String? {
        if phase == .idle {
            try? AVAudioSession.sharedInstance().setCategory(.playback)
            try? AVAudioSession.sharedInstance().setActive(true)
        }
        let sample = SetInfo(exercise: "Bulgarian Split Squat", note: "", number: 2, count: 3, weight: 17.5, reps: 10)
        return await speaker.say(
            [phrases.rest(90), phrases.next] + phrases.set(sample, withName: true, withNote: false),
            language: Prefs.language)
    }

    /// Generates the ElevenLabs audio for these sentences ahead of time (e.g. on Wi-Fi before the gym).
    /// Returns how many were generated and the first error.
    static func prepareVoice(_ sentences: [String]) async -> (generated: Int, error: String?) {
        guard VoiceConfig.isActive else { return (0, VoiceError.noKey.localizedDescription) }
        let config = VoiceConfig.current
        var generated = 0
        for sentence in sentences where !VoiceCache.shared.isCached(sentence, config: config) {
            do {
                _ = try await VoiceCache.shared.audio(for: sentence, config: config)
                generated += 1
            } catch {
                return (generated, error.localizedDescription)
            }
        }
        return (generated, nil)
    }

    private func endRest() {
        guard case .resting = phase else { return }
        if let position = currentPosition, let info = info(position) {
            phase = .lifting
            let newExercise = lastCompleted?.entry != position.entry
            say([phrases.go] + phrases.set(info, withName: newExercise, withNote: false))
        } else {
            phase = .complete
            say([phrases.complete])
        }
        updateNowPlaying()
    }

    // MARK: Timer

    private func startTimer() {
        timer?.invalidate()
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func tick() {
        now = Date()
        guard case .resting(let until, _) = phase else { return }
        let remaining = until.timeIntervalSince(now)
        if remaining <= 0 {
            endRest()
        } else if remaining <= 10.5 && !warnedTenSeconds {
            warnedTenSeconds = true
            say([phrases.tenSeconds])
        }
    }

    // MARK: Helpers

    private func info(_ position: SetPosition) -> SetInfo? {
        guard let workout = store.activeWorkout,
              let entry = workout.entries[safe: position.entry],
              let set = entry.sets[safe: position.set] else { return nil }
        let exercise = store.exercise(entry.exerciseID)
        return SetInfo(
            exercise: exercise?.name ?? "Exercise", note: exercise?.note ?? "",
            number: position.set + 1, count: entry.sets.count, weight: set.weight, reps: set.reps)
    }

    private func say(_ parts: [String]) {
        speaker.speak(parts, language: Prefs.language)
    }

    /// Lock screen shows the workout state; the current song goes in the album line.
    func updateNowPlaying() {
        guard store.activeWorkout != nil else { return }
        let song = music.currentSong.map { "♪ " + $0.title }
        switch phase {
        case .idle:
            return
        case .resting(let until, let total):
            let next = currentInfo.map { info in
                info.isUntracked ? "Next: \(info.exercise)" : "Next: \(info.exercise) · \(Fmt.load(weight: info.weight, reps: info.reps))"
            } ?? ""
            audio.setNowPlaying(
                title: "Rest", subtitle: next, album: song,
                duration: TimeInterval(total), elapsed: TimeInterval(total) - until.timeIntervalSinceNow)
        case .lifting:
            if let info = currentInfo {
                audio.setNowPlaying(
                    title: info.exercise,
                    subtitle: Fmt.position(info) ?? "Press once when done",
                    album: song)
            }
        case .complete:
            audio.setNowPlaying(title: "Workout complete", subtitle: "Finish it in the app", album: song)
        }
    }
}
