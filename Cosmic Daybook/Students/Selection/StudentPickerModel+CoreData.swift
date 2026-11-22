//
//  StudentPickerModel+CoreData.swift
//  Cosmic Daybook
//
//  The one place the picker's value types meet the store.
//
//  Managed objects are read here and nowhere else in the picker, so the rules
//  in `StudentPickerModel` stay testable without Core Data and a row costs a
//  dictionary lookup rather than a fault.
//

import CoreData
import Foundation

nonisolated extension StudentPickerCandidate {
    /// A candidate from a student record. `nil` when the record has no id —
    /// a picker cannot select what it cannot identify.
    init?(_ student: CDStudent) {
        guard let id = student.id else { return nil }
        self.init(
            id: id,
            firstName: student.firstName,
            lastName: student.lastName,
            birthday: student.birthday,
            level: student.level,
            status: student.enrollmentStatus,
            departedOn: student.dateDeparted
        )
    }
}

nonisolated extension StudentPickerModel {
    /// Candidates for a roster, in the order it was given.
    static func candidates(_ students: [CDStudent]) -> [StudentPickerCandidate] {
        students.compactMap(StudentPickerCandidate.init)
    }

    /// What the record holds for one lesson, re-keyed by student id so a row
    /// costs one hash lookup. The index itself is still built once per
    /// appearance, never per row.
    static func records(
        from index: PresentationRecordIndex, lesson lessonID: UUID
    ) -> [UUID: PresentationRecordIndex.Given] {
        var byStudent: [UUID: PresentationRecordIndex.Given] = [:]
        for (studentID, given) in index.givenByLesson[lessonID.uuidString] ?? [:] {
            guard let id = UUID(uuidString: studentID) else { continue }
            byStudent[id] = given
        }
        return byStudent
    }
}

extension StudentPickerModel {
    /// What each of `studentIDs` is still practicing from earlier in
    /// `lessonID`'s sequence: "Practicing The Distributive Law"
    /// (`WorkToShowFirst`). A child with nothing open is absent. One read.
    static func practicing(
        for lessonID: UUID,
        among studentIDs: Set<UUID>,
        lessons: [CDLesson],
        in context: NSManagedObjectContext
    ) -> [UUID: String] {
        guard !studentIDs.isEmpty, !lessons.isEmpty else { return [:] }
        let found = WorkToShowFirst.find(
            lessonID: lessonID.uuidString,
            studentIDs: studentIDs,
            sequences: WorkToShowFirst.Sequences(lessons: lessons),
            in: context
        )
        return found.compactMapValues(WorkToShowFirst.practicingLine)
    }
}
