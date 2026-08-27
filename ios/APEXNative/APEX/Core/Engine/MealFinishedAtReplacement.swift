import Foundation

enum MealFinishedAtReplacement {
    static func retime(_ draft: MealComposerDraft, to finishedAt: Date) -> MealComposerDraft {
        var replacement = draft
        replacement.finishedAt = finishedAt
        replacement.replaceMealID = draft.id
        return replacement
    }
}
