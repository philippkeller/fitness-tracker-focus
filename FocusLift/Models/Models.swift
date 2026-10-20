import Foundation

struct Exercise: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    /// Pinned setup note (machine settings, cues). Read out before the first set.
    var note: String = ""
}

struct WorkSet: Identifiable, Codable, Hashable {
    var id = UUID()
    var weight: Double
    var reps: Int
    /// Rest after this set, in seconds.
    var rest: Int = 90
    var done = false
    var completedAt: Date?
}

/// One exercise inside a routine or a workout, with its sets in order.
struct ExerciseEntry: Identifiable, Codable, Hashable {
    var id = UUID()
    var exerciseID: UUID
    var sets: [WorkSet]
    var skipped = false
}

struct Routine: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var entries: [ExerciseEntry] = []
}

struct Workout: Identifiable, Codable, Hashable {
    var id = UUID()
    var routineID: UUID?
    var name: String
    var startedAt: Date
    var endedAt: Date?
    var entries: [ExerciseEntry] = []

    var doneSets: [WorkSet] { entries.flatMap(\.sets).filter(\.done) }
    var volume: Double { doneSets.reduce(0) { $0 + $1.weight * Double($1.reps) } }
    var duration: TimeInterval { (endedAt ?? Date()).timeIntervalSince(startedAt) }
}

struct Database: Codable {
    var exercises: [Exercise] = []
    var routines: [Routine] = []
    var history: [Workout] = []
    var activeWorkout: Workout?
}

// MARK: - Records

struct Bests {
    var weight = 0.0
    var reps = 0
    var volume = 0.0
    var volumeSet: WorkSet?

    mutating func add(_ set: WorkSet) {
        weight = max(weight, set.weight)
        reps = max(reps, set.reps)
        let setVolume = set.weight * Double(set.reps)
        if setVolume > volume {
            volume = setVolume
            volumeSet = set
        }
    }
}

enum RecordKind {
    case weight, reps, volume

    var title: String {
        switch self {
        case .weight: "Heaviest weight"
        case .reps: "Most reps"
        case .volume: "Best set (kg × reps)"
        }
    }
}

struct RecordHit: Identifiable {
    let exercise: String
    let kind: RecordKind
    let value: String
    let previous: String
    /// "+2.5 kg", "+3 reps".
    let gain: String
    /// Where it happened: "Set 3 · 60 kg × 8".
    let detail: String

    /// Stable across recomputes, so the cards keep their state.
    var id: String { "\(exercise)|\(kind)" }
}
