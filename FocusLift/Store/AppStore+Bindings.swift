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

    func noteBinding(for exerciseID: UUID) -> Binding<String> {
        Binding(
            get: { self.exercise(exerciseID)?.note ?? "" },
            set: { value in
                if let index = self.exercises.firstIndex(where: { $0.id == exerciseID }) {
                    self.exercises[index].note = value
                }
            })
    }
}
