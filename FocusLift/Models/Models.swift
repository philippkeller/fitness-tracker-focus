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
    /// Archived routines are listed apart and never "Up next".
    var archived = false
}

// Custom decoding so routines saved before `archived` existed still load.
extension Routine {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        entries = try c.decode([ExerciseEntry].self, forKey: .entries)
        archived = try c.decodeIfPresent(Bool.self, forKey: .archived) ?? false
    }
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

/// Best values over some sets. Same record types as Hevy.
struct Bests {
    var weight = 0.0
    var reps = 0
    var oneRM = 0.0
    var oneRMSet: WorkSet?
    var volume = 0.0
    var volumeSet: WorkSet?
    /// Most kg × reps added up over one workout.
    var sessionVolume = 0.0

    /// Estimated one-rep max (Epley): the most you could lift once, judging by this set.
    static func oneRM(_ set: WorkSet) -> Double {
        set.reps == 1 ? set.weight : set.weight * (1 + Double(set.reps) / 30)
    }

    /// Adds the sets of one workout.
    mutating func add(session sets: [WorkSet]) {
        sessionVolume = max(sessionVolume, sets.reduce(0) { $0 + $1.weight * Double($1.reps) })
        for set in sets {
            weight = max(weight, set.weight)
            reps = max(reps, set.reps)
            if Bests.oneRM(set) > oneRM {
                oneRM = Bests.oneRM(set)
                oneRMSet = set
            }
            let setVolume = set.weight * Double(set.reps)
            if setVolume > volume {
                volume = setVolume
                volumeSet = set
            }
        }
    }
}

enum RecordKind {
    case weight, oneRM, volume, sessionVolume, reps

    var title: String {
        switch self {
        case .weight: "Heaviest weight"
        case .oneRM: "Best 1-rep max (estimated)"
        case .volume: "Best set (kg × reps)"
        case .sessionVolume: "Best workout (kg × reps, all sets)"
        case .reps: "Most reps"
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
