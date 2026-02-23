#if canImport(Testing)
import Foundation
import SwiftData
@testable import Maria_s_Notebook

/// Test data factories for snapshot testing.
/// All factories use deterministic data (no random values) for reproducible snapshots.
enum SnapshotTestData {

    // MARK: - Students

    /// Creates a test student with deterministic data
    static func makeStudent(
        id: UUID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
        firstName: String = "Emma",
        lastName: String = "Johnson",
        birthday: Date = SnapshotDates.studentBirthday,
        nickname: String? = nil,
        level: Student.Level = .lower,
        dateStarted: Date? = SnapshotDates.schoolYearStart,
        manualOrder: Int = 0
    ) -> Student {
        Student(
            id: id,
            firstName: firstName,
            lastName: lastName,
            birthday: birthday,
            nickname: nickname,
            level: level,
            dateStarted: dateStarted,
            manualOrder: manualOrder
        )
    }

    /// Creates a set of 5 test students with varied data
    static func makeStudentSet() -> [Student] {
        [
            makeStudent(
                id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
                firstName: "Emma",
                lastName: "Johnson",
                birthday: SnapshotDates.date(year: 2015, month: 6, day: 15),
                level: .lower,
                manualOrder: 1
            ),
            makeStudent(
                id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
                firstName: "Liam",
                lastName: "Smith",
                birthday: SnapshotDates.date(year: 2016, month: 3, day: 22),
                level: .lower,
                manualOrder: 2
            ),
            makeStudent(
                id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
                firstName: "Olivia",
                lastName: "Williams",
                birthday: SnapshotDates.date(year: 2014, month: 9, day: 8),
                level: .upper,
                manualOrder: 3
            ),
            makeStudent(
                id: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!,
                firstName: "Noah",
                lastName: "Brown",
                birthday: SnapshotDates.date(year: 2015, month: 1, day: 30),
                level: .upper,
                manualOrder: 4
            ),
            makeStudent(
                id: UUID(uuidString: "55555555-5555-5555-5555-555555555555")!,
                firstName: "Ava",
                lastName: "Davis",
                birthday: SnapshotDates.date(year: 2016, month: 11, day: 5),
                level: .lower,
                manualOrder: 5
            ),
        ]
    }

    /// Creates a student with birthday today (for birthday card testing)
    static func makeStudentWithBirthdayToday() -> Student {
        // Birthday on same month/day as reference date
        makeStudent(
            id: UUID(uuidString: "66666666-6666-6666-6666-666666666666")!,
            firstName: "Birthday",
            lastName: "Student",
            birthday: SnapshotDates.date(year: 2015, month: 1, day: 15),
            level: .lower
        )
    }

    /// Creates a student with birthday in 5 days (for upcoming birthday testing)
    static func makeStudentWithUpcomingBirthday() -> Student {
        makeStudent(
            id: UUID(uuidString: "77777777-7777-7777-7777-777777777777")!,
            firstName: "Upcoming",
            lastName: "Birthday",
            birthday: SnapshotDates.date(year: 2015, month: 1, day: 20),
            level: .upper
        )
    }

    // MARK: - Lessons

    /// Creates a test lesson with deterministic data
    static func makeLesson(
        id: UUID = UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!,
        name: String = "Addition Facts",
        subject: String = "Math",
        group: String = "Operations",
        orderInGroup: Int = 1,
        sortIndex: Int = 0,
        subheading: String = "Basic addition practice",
        writeUp: String = ""
    ) -> Lesson {
        Lesson(
            id: id,
            name: name,
            subject: subject,
            group: group,
            orderInGroup: orderInGroup,
            sortIndex: sortIndex,
            subheading: subheading,
            writeUp: writeUp
        )
    }

    /// Creates a set of test lessons organized by subject
    static func makeLessonSet() -> [Lesson] {
        [
            makeLesson(
                id: UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!,
                name: "Addition Facts",
                subject: "Math",
                group: "Operations",
                orderInGroup: 1,
                subheading: "Basic addition practice"
            ),
            makeLesson(
                id: UUID(uuidString: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")!,
                name: "Subtraction Facts",
                subject: "Math",
                group: "Operations",
                orderInGroup: 2,
                subheading: "Basic subtraction practice"
            ),
            makeLesson(
                id: UUID(uuidString: "cccccccc-cccc-cccc-cccc-cccccccccccc")!,
                name: "Multiplication Tables",
                subject: "Math",
                group: "Operations",
                orderInGroup: 3,
                subheading: "Times tables 1-12"
            ),
            makeLesson(
                id: UUID(uuidString: "dddddddd-dddd-dddd-dddd-dddddddddddd")!,
                name: "Reading Fluency",
                subject: "Language",
                group: "Reading",
                orderInGroup: 1,
                subheading: "Oral reading practice"
            ),
            makeLesson(
                id: UUID(uuidString: "eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee")!,
                name: "Sentence Structure",
                subject: "Language",
                group: "Writing",
                orderInGroup: 1,
                subheading: "Grammar and syntax"
            ),
        ]
    }

    // MARK: - Work Models

    /// Creates a test work model with deterministic data
    static func makeWork(
        id: UUID = UUID(uuidString: "11111111-aaaa-1111-aaaa-111111111111")!,
        title: String = "Practice Sheet",
        kind: WorkKind = .practiceLesson,
        status: WorkStatus = .active,
        assignedAt: Date = SnapshotDates.fiveDaysAgo,
        completedAt: Date? = nil,
        lastTouchedAt: Date? = nil,
        dueAt: Date? = nil,
        studentID: String = "",
        lessonID: String = ""
    ) -> WorkModel {
        WorkModel(
            id: id,
            title: title,
            kind: kind,
            completedAt: completedAt,
            status: status,
            assignedAt: assignedAt,
            lastTouchedAt: lastTouchedAt,
            dueAt: dueAt
        )
    }

    /// Creates work items for each work type
    static func makeWorkSet() -> [WorkModel] {
        [
            makeWork(
                id: UUID(uuidString: "11111111-aaaa-1111-aaaa-111111111111")!,
                title: "Math Practice",
                kind: .practiceLesson,
                status: .active
            ),
            makeWork(
                id: UUID(uuidString: "22222222-aaaa-2222-aaaa-222222222222")!,
                title: "Reading Follow-up",
                kind: .followUpAssignment,
                status: .active
            ),
            makeWork(
                id: UUID(uuidString: "33333333-aaaa-3333-aaaa-333333333333")!,
                title: "Progress Report",
                kind: .report,
                status: .active
            ),
        ]
    }

    // MARK: - Student Lessons

    /// Creates a test student lesson with deterministic data
    static func makeStudentLesson(
        id: UUID = UUID(uuidString: "aaaaaaaa-1111-aaaa-1111-aaaaaaaaaaaa")!,
        lessonID: UUID = UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!,
        studentIDs: [UUID] = [UUID(uuidString: "11111111-1111-1111-1111-111111111111")!],
        scheduledFor: Date? = nil,
        givenAt: Date? = nil,
        isPresented: Bool = false,
        notes: String = ""
    ) -> StudentLesson {
        StudentLesson(
            id: id,
            lessonID: lessonID,
            studentIDs: studentIDs,
            scheduledFor: scheduledFor,
            givenAt: givenAt,
            isPresented: isPresented,
            notes: notes
        )
    }

    // MARK: - Attendance

    /// Creates test attendance data (present, tardy, absent arrays)
    static func makeAttendanceData(students: [Student]? = nil) -> (present: [String], tardy: [String], absent: [String]) {
        let studentSet = students ?? makeStudentSet()
        let names = studentSet.map { $0.fullName }
        return (
            present: Array(names.prefix(3)),
            tardy: names.count > 3 ? [names[3]] : [],
            absent: names.count > 4 ? [names[4]] : []
        )
    }

    /// Creates an attendance record with deterministic data
    static func makeAttendanceRecord(
        id: UUID = UUID(uuidString: "11111111-cccc-1111-cccc-111111111111")!,
        studentID: UUID,
        date: Date = SnapshotDates.reference,
        status: AttendanceStatus = .present,
        absenceReason: AbsenceReason = .none,
        note: String? = nil
    ) -> AttendanceRecord {
        AttendanceRecord(
            id: id,
            studentID: studentID,
            date: date.normalizedDay(),
            status: status,
            absenceReason: absenceReason,
            note: note
        )
    }

    // MARK: - Backup Data

    /// Creates a test backup manifest
    static func makeBackupManifest(
        entityCounts: [String: Int]? = nil,
        sha256: String = "abc123def456789...",
        notes: String? = "Test backup",
        compression: String? = nil
    ) -> BackupManifest {
        let counts = entityCounts ?? [
            "Student": 25,
            "Lesson": 150,
            "StudentLesson": 500,
            "Note": 1200,
            "AttendanceRecord": 3000,
            "WorkModel": 450
        ]
        return BackupManifest(
            entityCounts: counts,
            sha256: sha256,
            notes: notes,
            compression: compression
        )
    }

    /// Creates a test backup envelope
    static func makeBackupEnvelope(
        manifest: BackupManifest? = nil
    ) -> BackupEnvelope {
        BackupEnvelope(
            formatVersion: BackupFile.formatVersion,
            createdAt: SnapshotDates.reference,
            appBuild: "100",
            appVersion: "2.0.0",
            device: "Test Device",
            manifest: manifest ?? makeBackupManifest(),
            payload: nil,
            encryptedPayload: nil,
            compressedPayload: nil
        )
    }

    /// Creates a test restore preview
    static func makeRestorePreview(
        mode: String = "merge"
    ) -> RestorePreview {
        RestorePreview(
            mode: mode,
            entityInserts: ["Student": 5, "Lesson": 10, "Note": 50],
            entitySkips: ["Student": 20, "Lesson": 140, "Note": 1150],
            entityDeletes: [:],
            totalInserts: 65,
            totalDeletes: 0,
            warnings: ["Some lessons reference missing students"]
        )
    }

    // MARK: - Notes

    /// Creates a test note with deterministic data
    @MainActor
    static func makeNote(
        id: UUID = UUID(uuidString: "11111111-dddd-1111-dddd-111111111111")!,
        body: String = "Test note content",
        scope: NoteScope = .all,
        isPinned: Bool = false,
        createdAt: Date = SnapshotDates.reference,
        updatedAt: Date = SnapshotDates.reference
    ) -> Note {
        let note = Note(
            id: id,
            body: body,
            scope: scope,
            isPinned: isPinned
        )
        return note
    }

    // MARK: - Group Track

    /// Creates a test group track with deterministic data
    static func makeGroupTrack(
        id: UUID = UUID(uuidString: "11111111-eeee-1111-eeee-111111111111")!,
        subject: String = "Math",
        group: String = "Operations"
    ) -> GroupTrack {
        GroupTrack(
            id: id,
            subject: subject,
            group: group
        )
    }
}

// MARK: - WorkCard Test Data

extension SnapshotTestData {
    /// Creates a WorkCard.GridConfig for testing
    static func makeGridConfig(
        work: WorkModel? = nil,
        lessonTitle: String = "Addition Facts",
        studentDisplay: String = "Emma J.",
        needsAttention: Bool = false,
        ageSchoolDays: Int = 5
    ) -> WorkCard.GridConfig {
        WorkCard.GridConfig(
            work: work ?? makeWork(),
            lessonTitle: lessonTitle,
            studentDisplay: studentDisplay,
            needsAttention: needsAttention,
            ageSchoolDays: ageSchoolDays,
            onOpen: { _ in },
            onMarkCompleted: { _ in },
            onScheduleToday: { _ in }
        )
    }

    /// Creates a WorkCard.ListConfig for testing
    static func makeListConfig(
        work: WorkModel? = nil,
        title: String = "Math Practice",
        subtitle: String = "Math - Operations",
        badge: WorkCardBadge? = nil
    ) -> WorkCard.ListConfig {
        WorkCard.ListConfig(
            work: work ?? makeWork(),
            title: title,
            subtitle: subtitle,
            badge: badge,
            onOpen: { _ in }
        )
    }
}

#endif
