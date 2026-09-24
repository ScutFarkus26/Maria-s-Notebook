import Foundation
import CoreData

// Kept apart from the views that use it: an extension has no dependency fingerprint, so a
// signature edit anywhere in a file that extends CDLesson recompiles every file that uses
// CDLesson. See CLAUDE.md, Build-setting rules.

// MARK: - Step Protocol

/// Protocol for unifying CDLesson steps and CDWorkStep types
protocol StepProtocol {
    var stepID: String { get }
}

// Extend CDLesson to conform to StepProtocol
nonisolated extension CDLesson: StepProtocol {
    var stepID: String { id?.uuidString ?? "" }
}

// Extend CDWorkStep to conform to StepProtocol
nonisolated extension CDWorkStep: StepProtocol {
    var stepID: String { id?.uuidString ?? "" }
}

// Extend CDTrackStep to conform to StepProtocol
nonisolated extension CDTrackStep: StepProtocol {
    var stepID: String { id?.uuidString ?? "" }
}
