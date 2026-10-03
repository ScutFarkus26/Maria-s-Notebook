//
//  ChecklistCellDescription.swift
//  Cosmic Daybook
//
//  The words for a checklist cell: its hover text, its VoiceOver value and hint.
//  The blocking reason left the cell as a badge and lives here now, naming the
//  lesson before ("Not yet: Subtraction: Dynamic not presented").
//

import Foundation

enum ChecklistCellDescription {

    /// "Maya S · Division: Dynamic — Ready", "… — Not yet: Subtraction: Dynamic not presented".
    static func helpText(
        studentName: String,
        lessonName: String,
        state: StudentChecklistRowState?,
        precedingLessonName: String?
    ) -> String {
        "\(studentName) · \(lessonName) — \(summary(state: state, precedingLessonName: precedingLessonName))"
    }

    /// The state, then why it's blocked and whether it needs a check-in.
    static func summary(state: StudentChecklistRowState?, precedingLessonName: String?) -> String {
        let status = state?.displayStatus ?? .ready
        let reason = state.flatMap { reasonText($0.blockingReason, precedingLessonName: precedingLessonName) }
        var text: String
        switch (status, reason) {
        case (.notReady, let reason?): text = "Not yet: \(reason)"
        case (_, let reason?): text = "\(status.label): \(reason)"
        case (_, nil): text = status.label
        }
        if state?.needsCheckIn == true { text += " · needs a check-in" }
        return text
    }

    /// VoiceOver's value: the state, the reason and the check-in, comma-separated.
    static func accessibilityValue(state: StudentChecklistRowState?, precedingLessonName: String?) -> String {
        var parts = [(state?.displayStatus ?? .ready).label]
        if let state, let reason = reasonText(state.blockingReason, precedingLessonName: precedingLessonName) {
            parts.append(reason)
        }
        if state?.needsCheckIn == true { parts.append("needs a check-in") }
        return parts.joined(separator: ", ")
    }

    /// What a click does: opens the cell's card, or in the iPhone's Select mode adds the cell
    /// to the selection.
    static func accessibilityHint(isSelectionMode: Bool) -> String {
        isSelectionMode
            ? "Adds to the selection"
            : "Opens the card for this child and lesson"
    }

    /// Why the lesson is blocked, naming the lesson before it when known. Nil when nothing blocks it.
    static func reasonText(_ reason: BlockingReason, precedingLessonName: String?) -> String? {
        guard reason != .none else { return nil }
        guard let name = precedingLessonName?.trimmed(), !name.isEmpty else { return reason.label }
        switch reason {
        case .none: return nil
        case .prerequisiteNotPresented: return "\(name) not presented"
        case .practiceRequired: return "practice on \(name) not finished"
        case .confirmationRequired: return "\(name) not confirmed"
        case .practiceAndConfirmation: return "practice on \(name) not finished, and not confirmed"
        }
    }
}
