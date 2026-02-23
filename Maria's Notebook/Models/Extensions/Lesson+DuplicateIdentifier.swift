import Foundation
import SwiftData

extension Lesson {
    /// A computed property that returns a normalized identifier string
    /// used to detect duplicates in imports and elsewhere.
    var duplicateIdentifier: String {
        let normalizedName = StringNormalization.normalizeComponent(name)
        let normalizedSubject = StringNormalization.normalizeComponent(subject)
        let normalizedGroup = StringNormalization.normalizeComponent(group)
        return [normalizedName, normalizedSubject, normalizedGroup].joined(separator: "|")
    }
}
