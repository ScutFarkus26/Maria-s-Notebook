//
//  ChecklistCellCardText.swift
//  Cosmic Daybook
//
//  What the cell card says and offers, kept apart from the view so it is tested:
//  the status line ("Ready." / "Not yet." / "Presented." with its date), the five
//  ladder steps a click can move the child up to, and the Present button's label
//  ("Present with 4 others ready…").
//

import Foundation

/// The open card's dates: when the child was last given the lesson and when her plan
/// is for. Read from her assignments when the card opens.
struct ChecklistCardRecord: Equatable {
    var presentedOn: Date?
    var plannedFor: Date?
}

/// The card's five steps, lowest first. A step moves the child up to its rung; a rung
/// she has already reached is shown done and does nothing (Clear takes her back).
enum ChecklistLadderStep: CaseIterable, Identifiable {
    case planned
    case presented
    case practicing
    case reviewing
    case mastered

    var id: Self { self }

    var status: ChecklistDisplayStatus {
        switch self {
        case .planned: return .planned
        case .presented: return .presented
        case .practicing: return .practicing
        case .reviewing: return .reviewing
        case .mastered: return .mastered
        }
    }

    var label: String { status.label }

    var action: ChecklistCellAction {
        switch self {
        case .planned: return .toggleScheduled
        case .presented: return .markPresented
        case .practicing: return .markPracticing
        case .reviewing: return .markReviewing
        case .mastered: return .markComplete
        }
    }

    /// True when `current` is this rung or above it.
    func isReached(by current: ChecklistDisplayStatus) -> Bool {
        Self.rank(current) >= Self.rank(status)
    }

    private static func rank(_ status: ChecklistDisplayStatus) -> Int {
        ChecklistDisplayStatus.allCases.firstIndex(of: status) ?? 0
    }
}

enum ChecklistCellCardText {

    /// The bold first word of the status line and the sentence after it.
    struct Status: Equatable {
        let title: String
        let detail: String
    }

    static func status(
        state: StudentChecklistRowState?,
        record: ChecklistCardRecord,
        precedingLessonName: String?,
        dateText: @MainActor (Date) -> String = Self.shortDate
    ) -> Status {
        let status = state?.displayStatus ?? .ready
        let presented = record.presentedOn.map { "Presented \(dateText($0))." } ?? "Presented, no date recorded."
        var detail: String
        switch status {
        case .notReady:
            let reason = state.flatMap {
                ChecklistCellDescription.reasonText($0.blockingReason, precedingLessonName: precedingLessonName)
            }
            detail = reason.map { $0.prefix(1).uppercased() + $0.dropFirst() + "." } ?? "Not ready for this one yet."
        case .ready:
            detail = "Nothing holds it back; not presented or planned yet."
        case .planned:
            detail = record.plannedFor.map { "Planned for \(dateText($0))." } ?? "In the Inbox."
        case .presented:
            // The title already says "Presented.", so the line only adds the date.
            detail = record.presentedOn.map { "On \(dateText($0))." } ?? "No date recorded."
        case .practicing:
            detail = "\(presented) Practice work is open."
        case .reviewing:
            detail = "\(presented) Work is in review, or closed without a mastery mark."
        case .mastered:
            detail = record.presentedOn.map { "Marked mastered. Presented \(dateText($0))." } ?? "Marked mastered."
        }
        if state?.needsCheckIn == true { detail += " Needs a check-in." }
        let title = status == .notReady ? "Not yet." : "\(status.label)."
        return Status(title: title, detail: detail)
    }

    /// "Present…", "Present with 1 other ready…", "Present with 4 others ready…".
    static func presentLabel(othersReady: Int) -> String {
        switch othersReady {
        case ...0: return "Present…"
        case 1: return "Present with 1 other ready…"
        default: return "Present with \(othersReady) others ready…"
        }
    }

    /// "Maya S · Stamp Game · age 9": the child, where the lesson sits, her age.
    static func subtitle(studentName: String, section: String, sequence: String, ageYears: Int?) -> String {
        var parts = [studentName]
        let place = section.trimmed().isEmpty ? sequence.trimmed() : section.trimmed()
        if !place.isEmpty { parts.append(place) }
        if let ageYears, ageYears > 0 { parts.append("age \(ageYears)") }
        return parts.joined(separator: " · ")
    }

    /// "Oct 2", or "Oct 2, 2025" outside this year.
    static func shortDate(_ date: Date) -> String {
        let calendar = AppCalendar.shared
        let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: Date())
        return sameYear
            ? date.formatted(.dateTime.month(.abbreviated).day())
            : date.formatted(.dateTime.month(.abbreviated).day().year())
    }
}
