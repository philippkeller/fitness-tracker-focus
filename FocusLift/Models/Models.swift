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
    /// The first set that reached each best, so a record can point at the set where it happened.
    var weightSet: WorkSet?
    var repsSet: WorkSet?
    var volumeSet: WorkSet?

    mutating func add(_ set: WorkSet) {
        if set.weight > weight {
            weight = set.weight
            weightSet = set
        }
        if set.reps > reps {
            reps = set.reps
            repsSet = set
        }
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

    /// Label next to the set that earned the record.
    var badge: String {
        switch self {
        case .weight: "Heaviest"
        case .reps: "Most reps"
        case .volume: "Best set"
        }
    }
}

struct RecordHit: Identifiable {
    let id = UUID()
    let kind: RecordKind
    let value: String
    let previous: String
    /// Improvement over the previous best, e.g. "+2.5 kg".
    let gain: String
    /// The set in which the record happened.
    let setID: UUID
}

/// All records one exercise set in a workout, with that exercise's completed sets for context.
struct ExerciseRecord: Identifiable {
    let exerciseID: UUID
    let exercise: String
    let sets: [WorkSet]
    let hits: [RecordHit]
    var id: UUID { exerciseID }

    func hits(for set: WorkSet) -> [RecordHit] {
        hits.filter { $0.setID == set.id }
    }
}
