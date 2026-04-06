import Foundation
import CoreData

/// Resolves effective progression rules for a given lesson by checking
/// lesson-level overrides first, then group-level settings, then defaults.
@MainActor
struct LessonProgressionRules {

    /// The resolved practice/confirmation requirements for a lesson.
    struct ResolvedRules: Sendable {
        let requiresPractice: Bool
        let requiresTeacherConfirmation: Bool
        let source: Source
    }

    /// Where the resolved rules came from.
    enum Source: Sendable {
        case groupDefault
        case lessonOverride
        /// No group settings exist; using built-in defaults.
        case builtInDefault
    }

    // MARK: - Resolution

    /// Resolve the effective progression rules for a lesson.
    ///
    /// Resolution order:
    /// 1. Lesson-level override ("yes" / "no") — wins immediately.
    /// 2. Group-level `CDLessonGroupSettings` for `subject + group`.
    /// 3. Built-in defaults: both gates on.
    static func resolve(
        for lesson: CDLesson,
        context: NSManagedObjectContext
    ) -> ResolvedRules {
        let practiceOverride = lesson.practiceOverride
        let confirmOverride = lesson.confirmationOverride

        // If both are explicit overrides, use them directly
        if practiceOverride != .inherit && confirmOverride != .inherit {
            return ResolvedRules(
                requiresPractice: practiceOverride == .yes,
                requiresTeacherConfirmation: confirmOverride == .yes,
                source: .lessonOverride
            )
        }

        // Look up group settings
        let groupSettings = CDLessonGroupSettings.find(
            subject: lesson.subject,
            group: lesson.group,
            context: context
        )

        let practice: Bool
        let confirmation: Bool
        var source: Source = .builtInDefault

        if practiceOverride != .inherit {
            practice = practiceOverride == .yes
            source = .lessonOverride
        } else if let gs = groupSettings {
            practice = gs.requiresPractice
            source = .groupDefault
        } else {
            practice = true
        }

        if confirmOverride != .inherit {
            confirmation = confirmOverride == .yes
            // If practice was also an override, keep lessonOverride; otherwise mixed
            if source != .lessonOverride { source = .lessonOverride }
        } else if let gs = groupSettings {
            confirmation = gs.requiresTeacherConfirmation
            if source == .builtInDefault { source = .groupDefault }
        } else {
            confirmation = true
        }

        return ResolvedRules(
            requiresPractice: practice,
            requiresTeacherConfirmation: confirmation,
            source: source
        )
    }
}
