import Foundation
import Observation

/// All app data, persisted as one JSON file in Documents (visible in the Files app).
@Observable
final class AppStore {
    var exercises: [Exercise] = []
    var routines: [Routine] = []
    /// Finished workouts, newest first.
    var history: [Workout] = []
    /// The running workout. Persisted so a crash or relaunch doesn't lose it.
    var activeWorkout: Workout?

    let fileURL: URL
    @ObservationIgnored private var pendingSave: DispatchWorkItem?

    init() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        fileURL = documents.appendingPathComponent("focuslift.json")
        load()
        observeChanges()
    }

    // MARK: Persistence

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else {
            seedExample()
            save()
            return
        }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let db = try decoder.decode(Database.self, from: data)
            exercises = db.exercises
            routines = db.routines
            history = db.history.sorted { $0.startedAt > $1.startedAt }
            activeWorkout = db.activeWorkout
        } catch {
            // Keep the unreadable file so nothing gets lost when we save next time.
            let backup = fileURL.deletingPathExtension()
                .appendingPathExtension("unreadable-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.copyItem(at: fileURL, to: backup)
            print("Could not read database: \(error)")
        }
    }

    func save() {
        pendingSave?.cancel()
        pendingSave = nil
        let db = Database(exercises: exercises, routines: routines, history: history, activeWorkout: activeWorkout)
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(db)
            // Sets get logged while the phone is locked, so the file must stay writable then.
            try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch {
            print("Save failed: \(error)")
        }
    }

    private func scheduleSave() {
        pendingSave?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.save() }
        pendingSave = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: item)
    }

    /// Saves (debounced) after any change to the stored properties.
    private func observeChanges() {
        withObservationTracking {
            _ = exercises
            _ = routines
            _ = history
            _ = activeWorkout
        } onChange: { [weak self] in
            DispatchQueue.main.async {
                self?.scheduleSave()
                self?.observeChanges()
            }
        }
    }

    private func seedExample() {
        let squat = Exercise(name: "Bulgarian Split Squat", note: "Sitzen. Wo Fersen sind = vorderer Fuss")
        let curl = Exercise(
            name: "Seated Leg Curl (Machine)",
            note: "B3 L 1 lehne 6 nach unten. Langsam. Unten durchdrücken. Zehen nach hinten")
        exercises = [squat, curl]
        routines = [
            Routine(name: "Example", entries: [
                ExerciseEntry(exerciseID: squat.id, sets: [
                    WorkSet(weight: 15, reps: 10), WorkSet(weight: 17.5, reps: 10), WorkSet(weight: 20, reps: 15),
                ]),
                ExerciseEntry(exerciseID: curl.id, sets: [
                    WorkSet(weight: 65, reps: 12), WorkSet(weight: 65, reps: 11),
                ]),
            ])
        ]
    }

    // MARK: Lookups

    func exercise(_ id: UUID) -> Exercise? {
        exercises.first { $0.id == id }
    }

    func exerciseName(_ id: UUID) -> String {
        exercise(id)?.name ?? "Unknown exercise"
    }

    /// Completed sets from the most recent finished workout (started before `date`) that contains the exercise.
    func previousSets(for exerciseID: UUID, before date: Date = .distantFuture) -> [WorkSet] {
        for workout in history where workout.startedAt < date {
            let sets = workout.entries
                .filter { $0.exerciseID == exerciseID }
                .flatMap(\.sets)
                .filter(\.done)
            if !sets.isEmpty { return sets }
        }
        return []
    }

    /// When the routine was last done. Strong imports have no routine link, so a matching name counts too.
    func lastDone(_ routine: Routine) -> Date? {
        history.first { $0.routineID == routine.id || $0.name == routine.name }?.startedAt
    }

    /// Every finished workout that has completed sets of the exercise, newest first, with those sets.
    func sessions(for exerciseID: UUID) -> [(workout: Workout, sets: [WorkSet])] {
        history.compactMap { workout in
            let sets = workout.entries
                .filter { $0.exerciseID == exerciseID }
                .flatMap(\.sets)
                .filter(\.done)
            return sets.isEmpty ? nil : (workout, sets)
        }
    }

    /// Sets for an exercise newly added to a routine or workout: last time's values, or 3 empty sets.
    func defaultSets(for exerciseID: UUID) -> [WorkSet] {
        let previous = previousSets(for: exerciseID)
        if !previous.isEmpty {
            return previous.map { WorkSet(weight: $0.weight, reps: $0.reps, rest: $0.rest) }
        }
        return (0..<3).map { _ in WorkSet(weight: 0, reps: 10) }
    }

    // MARK: Records

    /// Best values across all finished workouts started before `date`, or nil if never done.
    func bests(for exerciseID: UUID, before date: Date) -> Bests? {
        var result: Bests?
        for workout in history where workout.startedAt < date {
            for entry in workout.entries where entry.exerciseID == exerciseID {
                for set in entry.sets where set.done && set.reps > 0 {
                    if result == nil { result = Bests() }
                    result?.add(set)
                }
            }
        }
        return result
    }

    /// New records set in `workout` compared to everything before it. First-time exercises don't count.
    func records(in workout: Workout) -> [RecordHit] {
        var hits: [RecordHit] = []
        var seen = Set<UUID>()
        for entry in workout.entries where seen.insert(entry.exerciseID).inserted {
            // Numbered like the editor shows them, so the card can say which set it was.
            let allSets = workout.entries
                .filter { $0.exerciseID == entry.exerciseID }
                .flatMap(\.sets)
            let sets = allSets.filter { $0.done && $0.reps > 0 }
            guard !sets.isEmpty, let old = bests(for: entry.exerciseID, before: workout.startedAt) else { continue }
            var today = Bests()
            sets.forEach { today.add($0) }
            let name = exerciseName(entry.exerciseID)
            func detail(_ set: WorkSet?) -> String {
                guard let set, let index = allSets.firstIndex(where: { $0.id == set.id }) else { return "" }
                return "Set \(index + 1) · \(Fmt.set(set))"
            }

            if today.weight > old.weight {
                hits.append(RecordHit(
                    exercise: name, kind: .weight, value: Fmt.kg(today.weight), previous: Fmt.kg(old.weight),
                    gain: "+" + Fmt.kg(today.weight - old.weight),
                    detail: detail(sets.first { $0.weight == today.weight })))
            }
            if today.reps > old.reps {
                hits.append(RecordHit(
                    exercise: name, kind: .reps, value: "\(today.reps) reps", previous: "\(old.reps) reps",
                    gain: "+\(today.reps - old.reps) reps",
                    detail: detail(sets.first { $0.reps == today.reps })))
            }
            if today.volume > old.volume, let set = today.volumeSet {
                hits.append(RecordHit(
                    exercise: name, kind: .volume, value: Fmt.kg(today.volume), previous: Fmt.kg(old.volume),
                    gain: "+" + Fmt.kg(today.volume - old.volume),
                    detail: detail(set)))
            }
        }
        return hits
    }

    // MARK: Workout lifecycle

    func startWorkout(from routine: Routine?) {
        let entries = (routine?.entries ?? []).map { entry in
            ExerciseEntry(
                exerciseID: entry.exerciseID,
                sets: entry.sets.map { WorkSet(weight: $0.weight, reps: $0.reps, rest: $0.rest) })
        }
        activeWorkout = Workout(routineID: routine?.id, name: routine?.name ?? "Workout", startedAt: Date(), entries: entries)
    }

    /// Moves the active workout into history. With `updateRoutine`, the routine takes over today's
    /// exercises, order and values (like Strong's "update template").
    @discardableResult
    func finishActiveWorkout(updateRoutine: Bool) -> Workout? {
        guard let active = activeWorkout else { return nil }

        if updateRoutine, let routineID = active.routineID,
           let index = routines.firstIndex(where: { $0.id == routineID }) {
            routines[index].entries = active.entries.map { entry in
                ExerciseEntry(
                    exerciseID: entry.exerciseID,
                    sets: entry.sets.map { WorkSet(weight: $0.weight, reps: $0.reps, rest: $0.rest) })
            }
        }

        var finished = active
        finished.endedAt = Date()
        finished.entries = active.entries.compactMap { entry in
            var entry = entry
            entry.sets = entry.sets.filter(\.done)
            return entry.sets.isEmpty ? nil : entry
        }
        history.insert(finished, at: 0)
        activeWorkout = nil
        save()
        return finished
    }
}
