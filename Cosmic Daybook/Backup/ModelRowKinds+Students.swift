// ModelRowKinds+Students.swift
// The student's backup row, as the hand-written StudentDTO wrote and restored
// it until "Simplify round two", Phase 7 (see ModelRowKinds.swift).

import CoreData
import Foundation

public typealias StudentDTO = ModelRow<StudentBackupRow>

/// A child on the roster; a record with no `id` isn't backed up.
///
/// - `level` carries `levelRaw` ("Lower") as "lower", "upper" or
///   "adolescent", read through the typed level (an unknown raw goes out as
///   lower); a row holding any other word isn't read.
/// - `nextLessons` goes out as the ids that parse, and is restored as their
///   strings.
/// - A birthday of `.distantPast`, which one old export made up for a child
///   with none, restores as no birthday.
/// - `bornAfterSunset` (format v43) goes out as the record reads it: false
///   when it holds none (a record from before schema 21).
/// - A row without `enrollmentStatusRaw`, `modifiedAt` or `bornAfterSunset`
///   leaves the record's own.
///
/// The old row's `createdAt` and `updatedAt` were always written as nil and
/// never restored (the model has neither), so they're no longer read at all.
public enum StudentBackupRow: ModelRowKind {
    public static let spec = ModelRowSpec(
        "Student",
        omitting: ["levelRaw"],
        addedLater: ["enrollmentStatusRaw", "modifiedAt"],
        computed: [
            .computed(
                "level", .string, of: CDStudent.self, required: true,
                allowedStrings: Set(CDStudent.Level.allCases.map(StudentLevelKey.key)),
                read: { .string(StudentLevelKey.key($0.level)) },
                write: { student, value, _ in
                    guard case .string(let key)? = value,
                          let level = CDStudent.Level.allCases.first(where: { StudentLevelKey.key($0) == key })
                    else { return }
                    student.level = level
                }
            ),
            .computed(
                "nextLessons", .uuids, of: CDStudent.self, required: true,
                read: { .uuids($0.nextLessonUUIDs) },
                write: { student, value, _ in
                    guard case .uuids(let ids)? = value else { return }
                    student.nextLessons = ids.map(\.uuidString) as NSArray
                }
            ),
            .computed(
                "birthday", .date, of: CDStudent.self,
                read: { $0.birthday.map(ModelValue.date) },
                write: { student, value, _ in
                    guard case .date(let date)? = value, date != .distantPast else {
                        student.birthday = nil
                        return
                    }
                    student.birthday = date
                }
            ),
            .computed(
                "bornAfterSunset", .bool, of: CDStudent.self, kept: true,
                read: { .bool($0.bornAfterSunset) },
                write: { student, value, _ in
                    if case .bool(let isAfterSunset)? = value { student.bornAfterSunset = isAfterSunset }
                }
            )
        ],
        dropsRecordsWithoutID: true
    )
}

/// The backup's word for each level: the old row's own enum, lower-cased
/// unlike the model's raw values.
nonisolated private enum StudentLevelKey {
    static func key(_ level: CDStudent.Level) -> String {
        switch level {
        case .lower: "lower"
        case .upper: "upper"
        case .adolescent: "adolescent"
        }
    }
}
