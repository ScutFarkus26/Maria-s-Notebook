import Foundation
import SwiftData

// MARK: - Find Students Service

/// Finds candidate students to add to a presentation, filtered by lesson receipt
/// status and sorted by age proximity to existing students.
enum FindStudentsService {

    struct CandidateStudent: Identifiable {
        let student: Student
        /// Minimum absolute birthday difference (in seconds) to any existing student.
        let ageDifference: TimeInterval
        let ageString: String

        var id: UUID { student.id }
    }

    struct CandidateResult {
        let neverReceived: [CandidateStudent]
        let redundantlyScheduled: [CandidateStudent]
    }

    /// Finds students who are candidates for a presentation.
    ///
    /// - "Never Received": students with no presented `LessonAssignment` for this lesson
    /// - "Redundantly Scheduled": students who have a presented record AND also have a
    ///   non-presented (draft/scheduled) `LessonAssignment` for this lesson
    ///
    /// Both lists are sorted by minimum birthday distance to any existing student.
    static func findCandidates(
        lessonID: UUID,
        existingStudentIDs: Set<UUID>,
        allStudents: [Student],
        allLessonAssignments: [LessonAssignment]
    ) -> CandidateResult {
        let lessonIDString = lessonID.uuidString

        // Filter assignments for this lesson
        let assignmentsForLesson = allLessonAssignments.filter { $0.lessonID == lessonIDString }

        // Resolve existing student birthdays for age proximity
        let existingBirthdays = allStudents
            .filter { existingStudentIDs.contains($0.id) }
            .map(\.birthday)

        // Candidates are students NOT already in the presentation
        let candidates = allStudents.filter { !existingStudentIDs.contains($0.id) }

        var neverReceived: [CandidateStudent] = []
        var redundantlyScheduled: [CandidateStudent] = []

        for student in candidates {
            let studentIDString = student.id.uuidString

            // Find all assignments for this lesson that include this student
            let studentAssignments = assignmentsForLesson.filter { la in
                la.studentIDs.contains(studentIDString)
            }

            let hasPresented = studentAssignments.contains { $0.isPresented }
            let hasNonPresented = studentAssignments.contains { !$0.isPresented }

            let ageDiff = minAgeDifference(birthday: student.birthday, existingBirthdays: existingBirthdays)
            let ageStr = AgeUtils.conciseAgeString(for: student.birthday)
            let candidate = CandidateStudent(student: student, ageDifference: ageDiff, ageString: ageStr)

            if !hasPresented {
                neverReceived.append(candidate)
            } else if hasPresented && hasNonPresented {
                redundantlyScheduled.append(candidate)
            }
            // If hasPresented && !hasNonPresented → already received, no redundant schedule → skip
        }

        // Sort both lists by age proximity (ascending)
        neverReceived.sort { $0.ageDifference < $1.ageDifference }
        redundantlyScheduled.sort { $0.ageDifference < $1.ageDifference }

        return CandidateResult(neverReceived: neverReceived, redundantlyScheduled: redundantlyScheduled)
    }

    /// Returns the minimum absolute birthday difference between a candidate and any existing student.
    /// If there are no existing birthdays, returns `.greatestFiniteMagnitude`.
    private static func minAgeDifference(birthday: Date, existingBirthdays: [Date]) -> TimeInterval {
        guard !existingBirthdays.isEmpty else { return .greatestFiniteMagnitude }
        return existingBirthdays
            .map { abs(birthday.timeIntervalSince($0)) }
            .min() ?? .greatestFiniteMagnitude
    }
}
