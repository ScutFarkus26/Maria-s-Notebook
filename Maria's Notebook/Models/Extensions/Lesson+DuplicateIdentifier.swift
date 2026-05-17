import Foundation
import CoreData

extension CDLesson {
    /// A computed property that returns a normalized identifier string
    /// used to detect duplicates in imports and elsewhere.
    var duplicateIdentifier: String {
        let normalizedName = StringNormalization.normalizeComponent(name)
        let normalizedArea = StringNormalization.normalizeComponent(area)
        let normalizedSequence = StringNormalization.normalizeComponent(sequence)
        return [normalizedName, normalizedArea, normalizedSequence].joined(separator: "|")
    }
}
