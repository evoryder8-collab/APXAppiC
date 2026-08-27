import XCTest
@testable import APEX

final class AuthoredExerciseGuidanceTests: XCTestCase {
    func testEveryOfferedLanguageHasItsOwnExerciseCoachingCue() {
        let movement = "Romanian Deadlift"
        let english = ExerciseGuidance.executionCue(movement, language: .english)

        for language in AppLanguage.allCases where language != .english {
            XCTAssertNotEqual(
                ExerciseGuidance.executionCue(movement, language: language),
                english,
                "\(language.rawValue) is still falling back to English coaching copy"
            )
        }
    }

    func testEveryOfferedLanguageHasItsOwnFallbackGuidance() {
        let movement = "Uncatalogued movement"
        let english = ExerciseGuidance.executionCue(movement, language: .english)

        for language in AppLanguage.allCases where language != .english {
            XCTAssertNotEqual(
                ExerciseGuidance.executionCue(movement, language: language),
                english,
                "\(language.rawValue) is still falling back to English general guidance"
            )
        }
    }
}
