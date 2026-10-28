import SwiftUI

extension AppStore {
    func routineBinding(_ id: UUID) -> Binding<Routine>? {
        guard routines.contains(where: { $0.id == id }) else { return nil }
        return Binding(
            get: { self.routines.first { $0.id == id } ?? Routine(name: "") },
            set: { value in
                if let index = self.routines.firstIndex(where: { $0.id == id }) {
                    self.routines[index] = value
                }
            })
    }

    var activeWorkoutBinding: Binding<Workout>? {
        guard let workout = activeWorkout else { return nil }
        return Binding(
            get: { self.activeWorkout ?? workout },
            set: { value in
                // A late text-field commit after finishing must not resurrect the workout.
                if self.activeWorkout?.id == value.id {
                    self.activeWorkout = value
                }
            })
    }

    /// Edits the routine's own note if the entry has one, else the exercise's note.
    func noteBinding(for entry: Binding<ExerciseEntry>) -> Binding<String> {
        Binding(
            get: { self.note(for: entry.wrappedValue) },
            set: { value in
                if entry.wrappedValue.note != nil {
                    entry.wrappedValue.note = value
                } else if let index = self.exercises.firstIndex(where: { $0.id == entry.wrappedValue.exerciseID }) {
                    self.exercises[index].note = value
                }
            })
    }
}
