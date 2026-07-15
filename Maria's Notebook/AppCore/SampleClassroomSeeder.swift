import CoreData
import Foundation

/// Builds and maintains the isolated Sample Class data set.
///
/// The lesson catalog is mirrored by value, with the same stable lesson IDs,
/// into the sample store. Student records and all activity records are created
/// only in that sample store. No managed object is ever shared between the two
/// contexts.
@MainActor
enum SampleClassroomSeeder {
    private struct AttachmentSnapshot {
        let id: UUID
        let fileName: String
        let fileBookmark: Data?
        let fileRelativePath: String
        let attachedAt: Date?
        let fileType: String
        let fileSizeBytes: Int64
        let scopeRaw: String
        let notes: String
        let thumbnailData: Data?
    }

    private struct SampleWorkStepSnapshot {
        let id: UUID
        let title: String
        let orderIndex: Int64
        let instructions: String
        let createdAt: Date?
    }

    private struct SampleWorkSnapshot {
        let id: UUID
        let title: String
        let workKindRaw: String
        let orderIndex: Int64
        let notes: String
        let createdAt: Date?
        let steps: [SampleWorkStepSnapshot]
    }

    private struct LessonSnapshot {
        let id: UUID
        let name: String
        let area: String
        let sequence: String
        let orderInSequence: Int64
        let sortIndex: Int64
        let section: String
        let writeUp: String
        let suggestedFollowUpWork: String
        let materials: String
        let purpose: String
        let ageRange: String
        let teacherNotes: String
        let prerequisiteLessonIDs: String
        let relatedLessonIDs: String
        let greatLessonRaw: String?
        let sourceRaw: String
        let personalKindRaw: String?
        let lessonFormatRaw: String
        let parentStoryID: String?
        let defaultWorkKindRaw: String?
        let pagesFileBookmark: Data?
        let pagesFileRelativePath: String?
        let primaryAttachmentID: String?
        let requiresPracticeOverride: String
        let requiresConfirmationOverride: String
        let parshaKey: String?
        let derivedFromLessonID: String?
        let attachments: [AttachmentSnapshot]
        let sampleWorks: [SampleWorkSnapshot]
    }

    private struct FakeStudent {
        let id: UUID
        let firstName: String
        let lastName: String
        let age: Int
        let birthMonth: Int
        let birthDay: Int
        let level: CDStudent.Level
    }

    private static let fakeStudents: [FakeStudent] = [
        .init(
            id: UUID(uuidString: "A0000000-0000-0000-0000-000000000001")!,
            firstName: "Ari", lastName: "Cedar", age: 7, birthMonth: 10, birthDay: 8, level: .lower
        ),
        .init(
            id: UUID(uuidString: "A0000000-0000-0000-0000-000000000002")!,
            firstName: "Maya", lastName: "Stone", age: 8, birthMonth: 2, birthDay: 14, level: .lower
        ),
        .init(
            id: UUID(uuidString: "A0000000-0000-0000-0000-000000000003")!,
            firstName: "Noah", lastName: "Linden", age: 8, birthMonth: 6, birthDay: 3, level: .lower
        ),
        .init(
            id: UUID(uuidString: "A0000000-0000-0000-0000-000000000004")!,
            firstName: "Leah", lastName: "Hart", age: 9, birthMonth: 12, birthDay: 19, level: .lower
        ),
        .init(
            id: UUID(uuidString: "A0000000-0000-0000-0000-000000000005")!,
            firstName: "Ezra", lastName: "Bloom", age: 10, birthMonth: 4, birthDay: 25, level: .upper
        ),
        .init(
            id: UUID(uuidString: "A0000000-0000-0000-0000-000000000006")!,
            firstName: "Tamar", lastName: "Reed", age: 10, birthMonth: 9, birthDay: 11, level: .upper
        ),
        .init(
            id: UUID(uuidString: "A0000000-0000-0000-0000-000000000007")!,
            firstName: "Miriam", lastName: "Vale", age: 11, birthMonth: 1, birthDay: 30, level: .upper
        ),
        .init(
            id: UUID(uuidString: "A0000000-0000-0000-0000-000000000008")!,
            firstName: "Eli", lastName: "Brooks", age: 11, birthMonth: 7, birthDay: 17, level: .upper
        )
    ]

    static func prepare(
        lessonsFrom sourceContext: NSManagedObjectContext,
        sampleContext: NSManagedObjectContext,
        now: Date = Date(),
        calendar: Calendar = AppCalendar.shared
    ) throws {
        let lessons = try lessonSnapshots(from: sourceContext)

        do {
            try mirror(lessons: lessons, into: sampleContext)
            try seedStudentsIfNeeded(in: sampleContext, now: now, calendar: calendar)
            try seedAttendanceIfNeeded(in: sampleContext, now: now, calendar: calendar)
            try seedLessonActivityIfNeeded(
                lessons: lessons,
                in: sampleContext,
                now: now,
                calendar: calendar
            )
            try seedNotesIfNeeded(in: sampleContext, now: now, calendar: calendar)

            if sampleContext.hasChanges {
                try sampleContext.save()
            }
        } catch {
            sampleContext.rollback()
            throw error
        }
    }

    // MARK: - Lesson mirroring

    private static func lessonSnapshots(from context: NSManagedObjectContext) throws -> [LessonSnapshot] {
        let request = CDFetchRequest(CDLesson.self)
        request.sortDescriptors = [
            NSSortDescriptor(keyPath: \CDLesson.sortIndex, ascending: true),
            NSSortDescriptor(keyPath: \CDLesson.name, ascending: true)
        ]

        var seenIDs = Set<UUID>()
        return try context.fetch(request).compactMap { lesson in
            guard let id = lesson.id, seenIDs.insert(id).inserted else { return nil }

            let attachments = ((lesson.attachments?.allObjects as? [CDLessonAttachment]) ?? [])
                .compactMap { attachment -> AttachmentSnapshot? in
                    guard let attachmentID = attachment.id else { return nil }
                    return AttachmentSnapshot(
                        id: attachmentID,
                        fileName: attachment.fileName,
                        fileBookmark: attachment.fileBookmark,
                        fileRelativePath: attachment.fileRelativePath,
                        attachedAt: attachment.attachedAt,
                        fileType: attachment.fileType,
                        fileSizeBytes: attachment.fileSizeBytes,
                        scopeRaw: attachment.scopeRaw,
                        notes: attachment.notes,
                        thumbnailData: attachment.thumbnailData
                    )
                }

            let sampleWorks = ((lesson.sampleWorks?.allObjects as? [CDSampleWorkEntity]) ?? [])
                .compactMap { work -> SampleWorkSnapshot? in
                    guard let workID = work.id else { return nil }
                    let steps = work.orderedSteps.compactMap { step -> SampleWorkStepSnapshot? in
                        guard let stepID = step.id else { return nil }
                        return SampleWorkStepSnapshot(
                            id: stepID,
                            title: step.title,
                            orderIndex: step.orderIndex,
                            instructions: step.instructions,
                            createdAt: step.createdAt
                        )
                    }
                    return SampleWorkSnapshot(
                        id: workID,
                        title: work.title,
                        workKindRaw: work.workKindRaw,
                        orderIndex: work.orderIndex,
                        notes: work.notes,
                        createdAt: work.createdAt,
                        steps: steps
                    )
                }

            return LessonSnapshot(
                id: id,
                name: lesson.name,
                area: lesson.area,
                sequence: lesson.sequence,
                orderInSequence: lesson.orderInSequence,
                sortIndex: lesson.sortIndex,
                section: lesson.section,
                writeUp: lesson.writeUp,
                suggestedFollowUpWork: lesson.suggestedFollowUpWork,
                materials: lesson.materials,
                purpose: lesson.purpose,
                ageRange: lesson.ageRange,
                teacherNotes: lesson.teacherNotes,
                prerequisiteLessonIDs: lesson.prerequisiteLessonIDs,
                relatedLessonIDs: lesson.relatedLessonIDs,
                greatLessonRaw: lesson.greatLessonRaw,
                sourceRaw: lesson.sourceRaw,
                personalKindRaw: lesson.personalKindRaw,
                lessonFormatRaw: lesson.lessonFormatRaw,
                parentStoryID: lesson.parentStoryID,
                defaultWorkKindRaw: lesson.defaultWorkKindRaw,
                pagesFileBookmark: lesson.pagesFileBookmark,
                pagesFileRelativePath: lesson.pagesFileRelativePath,
                primaryAttachmentID: lesson.primaryAttachmentID,
                requiresPracticeOverride: lesson.requiresPracticeOverride,
                requiresConfirmationOverride: lesson.requiresConfirmationOverride,
                parshaKey: lesson.parshaKey,
                derivedFromLessonID: lesson.derivedFromLessonID,
                attachments: attachments,
                sampleWorks: sampleWorks
            )
        }
    }

    private static func mirror(
        lessons: [LessonSnapshot],
        into context: NSManagedObjectContext
    ) throws {
        let existingLessons = try context.fetch(CDFetchRequest(CDLesson.self))
        var lessonsByID = firstByID(existingLessons, id: \CDLesson.id)

        let existingAttachments = try context.fetch(CDFetchRequest(CDLessonAttachment.self))
        var attachmentsByID = firstByID(existingAttachments, id: \CDLessonAttachment.id)

        let existingWorks = try context.fetch(CDFetchRequest(CDSampleWorkEntity.self))
        var worksByID = firstByID(existingWorks, id: \CDSampleWorkEntity.id)

        let existingSteps = try context.fetch(CDFetchRequest(CDSampleWorkStepEntity.self))
        var stepsByID = firstByID(existingSteps, id: \CDSampleWorkStepEntity.id)

        for snapshot in lessons {
            let lesson = lessonsByID[snapshot.id] ?? CDLesson(context: context)
            lesson.id = snapshot.id
            lesson.name = snapshot.name
            lesson.area = snapshot.area
            lesson.sequence = snapshot.sequence
            lesson.orderInSequence = snapshot.orderInSequence
            lesson.sortIndex = snapshot.sortIndex
            lesson.section = snapshot.section
            lesson.writeUp = snapshot.writeUp
            lesson.suggestedFollowUpWork = snapshot.suggestedFollowUpWork
            lesson.materials = snapshot.materials
            lesson.purpose = snapshot.purpose
            lesson.ageRange = snapshot.ageRange
            lesson.teacherNotes = snapshot.teacherNotes
            lesson.prerequisiteLessonIDs = snapshot.prerequisiteLessonIDs
            lesson.relatedLessonIDs = snapshot.relatedLessonIDs
            lesson.greatLessonRaw = snapshot.greatLessonRaw
            lesson.sourceRaw = snapshot.sourceRaw
            lesson.personalKindRaw = snapshot.personalKindRaw
            lesson.lessonFormatRaw = snapshot.lessonFormatRaw
            lesson.parentStoryID = snapshot.parentStoryID
            lesson.defaultWorkKindRaw = snapshot.defaultWorkKindRaw
            lesson.pagesFileBookmark = snapshot.pagesFileBookmark
            lesson.pagesFileRelativePath = snapshot.pagesFileRelativePath
            lesson.primaryAttachmentID = snapshot.primaryAttachmentID
            lesson.requiresPracticeOverride = snapshot.requiresPracticeOverride
            lesson.requiresConfirmationOverride = snapshot.requiresConfirmationOverride
            lesson.parshaKey = snapshot.parshaKey
            lesson.derivedFromLessonID = snapshot.derivedFromLessonID
            lessonsByID[snapshot.id] = lesson

            for attachmentSnapshot in snapshot.attachments {
                let attachment = attachmentsByID[attachmentSnapshot.id]
                    ?? CDLessonAttachment(context: context)
                attachment.id = attachmentSnapshot.id
                attachment.fileName = attachmentSnapshot.fileName
                attachment.fileBookmark = attachmentSnapshot.fileBookmark
                attachment.fileRelativePath = attachmentSnapshot.fileRelativePath
                attachment.attachedAt = attachmentSnapshot.attachedAt
                attachment.fileType = attachmentSnapshot.fileType
                attachment.fileSizeBytes = attachmentSnapshot.fileSizeBytes
                attachment.scopeRaw = attachmentSnapshot.scopeRaw
                attachment.notes = attachmentSnapshot.notes
                attachment.thumbnailData = attachmentSnapshot.thumbnailData
                attachment.lesson = lesson
                attachmentsByID[attachmentSnapshot.id] = attachment
            }

            for workSnapshot in snapshot.sampleWorks {
                let work = worksByID[workSnapshot.id] ?? CDSampleWorkEntity(context: context)
                work.id = workSnapshot.id
                work.title = workSnapshot.title
                work.workKindRaw = workSnapshot.workKindRaw
                work.orderIndex = workSnapshot.orderIndex
                work.notes = workSnapshot.notes
                work.createdAt = workSnapshot.createdAt
                work.lesson = lesson
                worksByID[workSnapshot.id] = work

                for stepSnapshot in workSnapshot.steps {
                    let step = stepsByID[stepSnapshot.id] ?? CDSampleWorkStepEntity(context: context)
                    step.id = stepSnapshot.id
                    step.title = stepSnapshot.title
                    step.orderIndex = stepSnapshot.orderIndex
                    step.instructions = stepSnapshot.instructions
                    step.createdAt = stepSnapshot.createdAt
                    step.sampleWork = work
                    stepsByID[stepSnapshot.id] = step
                }
            }
        }
    }

    private static func firstByID<Object: NSManagedObject>(
        _ objects: [Object],
        id: KeyPath<Object, UUID?>
    ) -> [UUID: Object] {
        var result: [UUID: Object] = [:]
        for object in objects {
            guard let objectID = object[keyPath: id], result[objectID] == nil else { continue }
            result[objectID] = object
        }
        return result
    }

    // MARK: - Fake classroom records

    private static func seedStudentsIfNeeded(
        in context: NSManagedObjectContext,
        now: Date,
        calendar: Calendar
    ) throws {
        guard try context.count(for: CDFetchRequest(CDStudent.self)) == 0 else { return }

        let currentYear = calendar.component(.year, from: now)
        for (index, seed) in fakeStudents.enumerated() {
            let student = CDStudent(context: context)
            student.id = seed.id
            student.firstName = seed.firstName
            student.lastName = seed.lastName
            student.level = seed.level
            student.manualOrder = Int64(index)
            student.birthday = calendar.date(from: DateComponents(
                year: currentYear - seed.age,
                month: seed.birthMonth,
                day: seed.birthDay
            ))
            student.dateStarted = calendar.date(byAdding: .month, value: -(index + 1), to: now)
            student.modifiedAt = now
        }
    }

    private static func seedAttendanceIfNeeded(
        in context: NSManagedObjectContext,
        now: Date,
        calendar: Calendar
    ) throws {
        let request = CDFetchRequest(CDAttendanceRecord.self)
        guard try context.count(for: request) == 0 else { return }

        let today = calendar.startOfDay(for: now)
        for dayOffset in 0..<5 {
            guard let day = calendar.date(byAdding: .day, value: -dayOffset, to: today) else { continue }
            for (index, studentSeed) in fakeStudents.enumerated() {
                let record = CDAttendanceRecord(context: context)
                record.studentIDUUID = studentSeed.id
                record.date = day

                if dayOffset == 0 && index == 3 {
                    record.status = .absent
                    record.absenceReason = .sick
                } else if dayOffset == 0 && index == 6 {
                    record.status = .tardy
                } else if dayOffset == 2 && index == 1 {
                    record.status = .absent
                    record.absenceReason = .vacation
                } else {
                    record.status = .present
                }
            }
        }
    }

    private static func seedLessonActivityIfNeeded(
        lessons: [LessonSnapshot],
        in context: NSManagedObjectContext,
        now: Date,
        calendar: Calendar
    ) throws {
        guard !lessons.isEmpty else { return }

        let historyRequest = CDFetchRequest(CDLessonPresentation.self)
        if try context.count(for: historyRequest) == 0 {
            for (studentIndex, studentSeed) in fakeStudents.enumerated() {
                for lessonOffset in 0..<min(3, lessons.count) {
                    let lesson = lessons[(studentIndex + lessonOffset) % lessons.count]
                    let history = CDLessonPresentation(context: context)
                    history.studentID = studentSeed.id.uuidString
                    history.lessonID = lesson.id.uuidString
                    history.presentedAt = calendar.date(
                        byAdding: .day,
                        value: -(studentIndex * 3 + lessonOffset + 2),
                        to: now
                    )
                    history.createdAt = history.presentedAt
                    history.state = lessonOffset == 0 ? .proficient : .presented
                    history.masteredAt = lessonOffset == 0 ? history.presentedAt : nil
                    history.notes = lessonOffset == 0
                        ? "Worked independently and explained the key idea clearly."
                        : "Sample presentation record for exploring the student timeline."
                }
            }
        }

        let assignmentRequest = CDFetchRequest(CDLessonAssignment.self)
        guard try context.count(for: assignmentRequest) == 0 else { return }

        let presentedGroups = Array(lessons.prefix(2))
        for (index, lesson) in presentedGroups.enumerated() {
            let assignment = CDLessonAssignment(context: context)
            assignment.lessonID = lesson.id.uuidString
            assignment.studentIDs = fakeStudents
                .dropFirst(index * 2)
                .prefix(3)
                .map { $0.id.uuidString }
            assignment.lessonTitleSnapshot = lesson.name
            assignment.lessonSectionSnapshot = lesson.section
            assignment.presentedAt = calendar.date(byAdding: .day, value: -(index + 1), to: now)
            assignment.state = .presented
            assignment.notes = "Sample small-group presentation."
        }

        for (index, lesson) in lessons.dropFirst(2).prefix(3).enumerated() {
            let assignment = CDLessonAssignment(context: context)
            assignment.lessonID = lesson.id.uuidString
            assignment.studentIDs = [fakeStudents[(index + 4) % fakeStudents.count].id.uuidString]
            assignment.lessonTitleSnapshot = lesson.name
            assignment.lessonSectionSnapshot = lesson.section
            if let scheduledDate = calendar.date(byAdding: .day, value: index, to: now) {
                assignment.schedule(for: scheduledDate, using: calendar)
            }
            assignment.notes = "Sample plan—safe to reschedule or complete."
        }
    }

    private static func seedNotesIfNeeded(
        in context: NSManagedObjectContext,
        now: Date,
        calendar: Calendar
    ) throws {
        let request = CDFetchRequest(CDNote.self)
        guard try context.count(for: request) == 0 else { return }

        let bodies = [
            "Chose a challenging follow-up and stayed with it through two revisions.",
            "Asked to repeat yesterday's lesson with a partner and took the lead calmly.",
            "Needed a quieter workspace, then returned and completed the planned work.",
            "Connected today's lesson to an earlier story during group reflection.",
            "Showed careful material care while helping a younger classmate reset the shelf.",
            "Recorded a question to bring back to the next conference.",
            "Worked independently for a longer cycle than last week.",
            "Requested another presentation before beginning the follow-up work."
        ]

        for (index, studentSeed) in fakeStudents.enumerated() {
            let note = CDNote(context: context)
            note.body = bodies[index]
            note.scope = .student(studentSeed.id)
            note.category = index == 2 ? .emotional : .academic
            note.tagsArray = index.isMultiple(of: 2) ? ["independence"] : ["follow-up"]
            note.createdAt = calendar.date(byAdding: .day, value: -index, to: now)
            note.updatedAt = note.createdAt
            note.needsFollowUp = index == 5 || index == 7

            let link = CDNoteStudentLink(context: context)
            link.noteIDUUID = note.id
            link.studentIDUUID = studentSeed.id
            link.note = note
        }
    }
}
