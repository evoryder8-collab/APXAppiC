import Foundation

enum TrainingAdjustmentEngine {
    static func isDeload(on date: String, marks: [DeloadMark]) -> Bool {
        marks.contains { $0.date == date }
    }

    static func adjustedExercises(_ exercises: [Exercise], isDeload: Bool) -> [Exercise] {
        guard isDeload else { return exercises }
        return exercises.map { source in
            var exercise = source
            exercise.sets = max(1, source.sets - 1)
            return exercise
        }
    }
}
