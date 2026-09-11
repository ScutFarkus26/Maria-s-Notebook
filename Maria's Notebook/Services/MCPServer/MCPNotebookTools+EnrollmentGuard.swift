//
//  MCPNotebookTools+EnrollmentGuard.swift
//  Maria's Notebook
//
//  A child who has left the classroom cannot be put on a lesson.
//
//  Names resolve against every student on file, so "Naomi" still matches a
//  child who was withdrawn in June; without this the model can quietly plan a
//  lesson for her and the plan reads as real. The refusal is in the voice of
//  the regive guard: what was not done, who she is, when she left, and where
//  the current roster is.
//
//  Deliberately *not* guarded: `record_presentation`, which files history — a
//  lesson given before she left is real and belongs on her record — and
//  `update_presentation_roster`'s `remove_students`, which is how a roster is
//  cleaned up after a departure.
//

import CoreData
import Foundation

extension MCPNotebookTools {

    /// `schedule_presentation`'s form of the guard.
    static func requireEnrolledToSchedule(_ students: [CDStudent]) throws {
        try requireEnrolledForPresentation(
            students, tool: "schedule_presentation", action: "scheduled for a presentation"
        )
    }

    /// `update_presentation_roster`'s form, for the children being added.
    static func requireEnrolledToJoinRoster(_ students: [CDStudent]) throws {
        try requireEnrolledForPresentation(
            students, tool: "update_presentation_roster", action: "added to a presentation's group"
        )
    }

    /// Throws unless every named child is enrolled. Call it before any write,
    /// so a refusal leaves the notebook untouched.
    ///
    /// - Parameters:
    ///   - tool: the tool's own name, for the first words of the refusal.
    ///   - action: what she cannot be, e.g. "scheduled for a presentation".
    static func requireEnrolledForPresentation(
        _ students: [CDStudent], tool: String, action: String
    ) throws {
        let blocked = students.compactMap(Blocked.init)
        guard !blocked.isEmpty else { return }
        throw MCPToolError(
            "\(tool) refused — nothing has been changed. \(sentence(for: blocked, action: action)) "
                + "list_students shows the current roster."
        )
    }

    /// One child who has left, with the sentence pieces her status decides.
    private struct Blocked {
        let name: String
        let departedDay: String?
        let block: StudentEnrollmentBlock

        init?(_ student: CDStudent) {
            guard let block = StudentEnrollmentBlock.forStatus(
                student.enrollmentStatus, departedOn: student.dateDeparted
            ) else { return nil }
            self.name = student.fullName
            self.departedDay = student.dateDeparted.map { MCPNotebookTools.dayString($0) }
            self.block = block
        }
    }

    private static func sentence(for blocked: [Blocked], action: String) -> String {
        if let only = blocked.first, blocked.count == 1 {
            return only.block.refusal(name: only.name, action: action, departedDay: only.departedDay)
        }
        let detail: String = blocked
            .map { (child: Blocked) -> String in
                child.block.listEntry(name: child.name, departedDay: child.departedDay)
            }
            .joined(separator: ", ")
        let count: String = String(blocked.count)
        return count + " of these children have left the classroom and cannot be "
            + action + ": " + detail + "."
    }
}
