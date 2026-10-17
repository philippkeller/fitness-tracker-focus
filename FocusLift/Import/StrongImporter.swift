import Foundation

enum StrongImportError: LocalizedError {
    case empty
    case unrecognizedHeader

    var errorDescription: String? {
        switch self {
        case .empty: "The file is empty."
        case .unrecognizedHeader: "This doesn't look like a Strong export (Date, Exercise Name and Reps columns are missing)."
        }
    }
}

/// Imports the CSV from Strong → Settings → Export Strong Data.
/// Handles comma- and semicolon-separated exports, kg and lbs.
enum StrongImporter {
    struct Summary {
        var workouts = 0
        var duplicates = 0
        var exercises = 0
        var routines = 0
    }

    static func importCSV(_ raw: String, into store: AppStore, createRoutines: Bool) throws -> Summary {
        var text = raw
        if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
        guard let firstLine = text.split(whereSeparator: \.isNewline).first else { throw StrongImportError.empty }
        let delimiter: Character = firstLine.filter { $0 == ";" }.count > firstLine.filter { $0 == "," }.count ? ";" : ","
        let rows = parse(text, delimiter: delimiter)
        guard let header = rows.first?.map({ $0.trimmingCharacters(in: .whitespaces).lowercased() }) else {
            throw StrongImportError.empty
        }

        func column(_ matches: (String) -> Bool) -> Int? { header.firstIndex(where: matches) }
        guard let dateColumn = column({ $0 == "date" }),
              let exerciseColumn = column({ $0.hasPrefix("exercise") }),
              let repsColumn = column({ $0 == "reps" }) else {
            throw StrongImportError.unrecognizedHeader
        }
        let nameColumn = column { $0.hasPrefix("workout name") }
        let weightColumn = column { $0.hasPrefix("weight") && !$0.contains("unit") }
        let unitColumn = column { $0.contains("weight unit") }
        let orderColumn = column { $0.hasPrefix("set order") }
        let durationColumn = column { $0.hasPrefix("duration") }
        let headerInPounds = weightColumn.map { header[$0].contains("lb") } ?? false

        var exerciseIDs: [String: UUID] = [:]
        for exercise in store.exercises { exerciseIDs[exercise.name.lowercased()] = exercise.id }
        var newExercises: [Exercise] = []
        var workouts: [String: Workout] = [:]
        var workoutOrder: [String] = []

        for row in rows.dropFirst() {
            func value(_ column: Int?) -> String {
                guard let column, column < row.count else { return "" }
                return row[column].trimmingCharacters(in: .whitespaces)
            }
            let setOrder = value(orderColumn).lowercased()
            if setOrder.contains("rest") || setOrder.contains("note") { continue }

            let exerciseName = value(exerciseColumn)
            guard !exerciseName.isEmpty, let date = parseDate(value(dateColumn)) else { continue }
            let reps = Int(number(value(repsColumn)) ?? 0)
            var weight = number(value(weightColumn)) ?? 0
            if headerInPounds || value(unitColumn).lowercased().hasPrefix("lb") {
                weight = (weight * 0.45359237 * 4).rounded() / 4
            }
            guard reps > 0 || weight > 0 else { continue }

            let workoutName = value(nameColumn).isEmpty ? "Workout" : value(nameColumn)
            let workoutKey = value(dateColumn) + "|" + workoutName
            if workouts[workoutKey] == nil {
                var workout = Workout(name: workoutName, startedAt: date)
                workout.endedAt = date.addingTimeInterval(parseDuration(value(durationColumn)) ?? 3600)
                workouts[workoutKey] = workout
                workoutOrder.append(workoutKey)
            }

            let exerciseID: UUID
            if let id = exerciseIDs[exerciseName.lowercased()] {
                exerciseID = id
            } else {
                let exercise = Exercise(name: exerciseName)
                exerciseIDs[exerciseName.lowercased()] = exercise.id
                newExercises.append(exercise)
                exerciseID = exercise.id
            }

            let set = WorkSet(weight: weight, reps: reps, done: true, completedAt: date)
            var workout = workouts[workoutKey]!
            if workout.entries.last?.exerciseID == exerciseID {
                workout.entries[workout.entries.count - 1].sets.append(set)
            } else {
                workout.entries.append(ExerciseEntry(exerciseID: exerciseID, sets: [set]))
            }
            workouts[workoutKey] = workout
        }

        var summary = Summary()
        let existing = Set(store.history.map { key($0) })
        var imported: [Workout] = []
        for workoutKey in workoutOrder {
            guard let workout = workouts[workoutKey] else { continue }
            if existing.contains(key(workout)) {
                summary.duplicates += 1
            } else {
                imported.append(workout)
            }
        }

        store.exercises.append(contentsOf: newExercises)
        store.history.append(contentsOf: imported)
        store.history.sort { $0.startedAt > $1.startedAt }
        summary.workouts = imported.count
        summary.exercises = newExercises.count

        if createRoutines {
            // One routine per Strong workout name, based on the latest time it was done.
            var latest: [String: Workout] = [:]
            for workout in imported where (latest[workout.name]?.startedAt ?? .distantPast) < workout.startedAt {
                latest[workout.name] = workout
            }
            for (name, workout) in latest.sorted(by: { $0.key < $1.key })
            where !store.routines.contains(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
                let entries = workout.entries.map { entry in
                    ExerciseEntry(exerciseID: entry.exerciseID, sets: entry.sets.map { WorkSet(weight: $0.weight, reps: $0.reps) })
                }
                store.routines.append(Routine(name: name, entries: entries))
                summary.routines += 1
            }
        }
        return summary
    }

    // MARK: Parsing

    private static func key(_ workout: Workout) -> String {
        "\(Int(workout.startedAt.timeIntervalSince1970))|\(workout.name)"
    }

    /// RFC 4180-style CSV: quoted fields, doubled quotes, newlines inside quotes.
    static func parse(_ text: String, delimiter: Character) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        let characters = Array(text)
        var index = 0
        while index < characters.count {
            let character = characters[index]
            if inQuotes {
                if character == "\"" {
                    if index + 1 < characters.count && characters[index + 1] == "\"" {
                        field.append("\"")
                        index += 1
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(character)
                }
            } else if character == "\"" {
                inQuotes = true
            } else if character == delimiter {
                row.append(field)
                field = ""
            } else if character.isNewline {
                row.append(field)
                field = ""
                if row.contains(where: { !$0.isEmpty }) { rows.append(row) }
                row = []
            } else {
                field.append(character)
            }
            index += 1
        }
        if !field.isEmpty || !row.isEmpty {
            row.append(field)
            rows.append(row)
        }
        return rows
    }

    private static let dateFormatters: [DateFormatter] = [
        "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm", "yyyy-MM-dd'T'HH:mm:ss",
        "dd.MM.yyyy HH:mm:ss", "dd.MM.yyyy HH:mm", "MM/dd/yyyy HH:mm:ss", "MM/dd/yyyy HH:mm",
    ].map { format in
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = format
        return formatter
    }

    static func parseDate(_ string: String) -> Date? {
        for formatter in dateFormatters {
            if let date = formatter.date(from: string) { return date }
        }
        return ISO8601DateFormatter().date(from: string)
    }

    static func number(_ string: String) -> Double? {
        Double(string.replacingOccurrences(of: ",", with: "."))
    }

    /// Seconds, or Strong's "1h 5m" style.
    static func parseDuration(_ string: String) -> TimeInterval? {
        if let seconds = Double(string) { return seconds > 0 ? seconds : nil }
        var total = 0.0
        var digits = ""
        for character in string {
            if character.isNumber {
                digits.append(character)
            } else if let value = Double(digits) {
                switch character {
                case "h": total += value * 3600
                case "m": total += value * 60
                case "s": total += value
                default: break
                }
                digits = ""
            }
        }
        return total > 0 ? total : nil
    }
}
