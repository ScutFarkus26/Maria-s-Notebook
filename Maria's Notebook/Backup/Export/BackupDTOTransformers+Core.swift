import Foundation
import CoreData
import OSLog

// MARK: - Core Transformers (CDStudent, CDLesson, CDNote, LessonAttachment, CDLessonPresentation)

extension BackupDTOTransformers {

    // MARK: - CDStudent

    static func toDTO(_ student: CDStudent) -> StudentDTO {
        let level: StudentDTO.Level = (student.level == .upper) ? .upper : .lower
        return StudentDTO(
            id: student.id ?? UUID(),
            firstName: student.firstName,
            lastName: student.lastName,
            birthday: student.birthday ?? Date.distantPast,
            dateStarted: student.dateStarted,
            level: level,
            nextLessons: student.nextLessonUUIDs,
            manualOrder: Int(student.manualOrder),
            createdAt: nil,
            updatedAt: nil
        )
    }

    // MARK: - CDLesson

    static func toDTO(_ lesson: CDLesson) -> LessonDTO {
        LessonDTO(
            id: lesson.id ?? UUID(),
            name: lesson.name,
            subject: lesson.subject,
            group: lesson.group,
            orderInGroup: Int(lesson.orderInGroup),
            subheading: lesson.subheading,
            writeUp: lesson.writeUp,
            createdAt: nil,
            updatedAt: nil,
            pagesFileRelativePath: lesson.pagesFileRelativePath,
            primaryAttachmentID: lesson.primaryAttachmentIDUUID,
            suggestedFollowUpWork: lesson.suggestedFollowUpWork,
            sourceRaw: lesson.sourceRaw,
            personalKindRaw: lesson.personalKindRaw,
            defaultWorkKindRaw: lesson.defaultWorkKindRaw,
            materials: lesson.materials,
            purpose: lesson.purpose,
            ageRange: lesson.ageRange,
            teacherNotes: lesson.teacherNotes,
            prerequisiteLessonIDs: lesson.prerequisiteLessonIDs,
            relatedLessonIDs: lesson.relatedLessonIDs
        )
    }

    // MARK: - CDSampleWork

    static func toDTO(_ sw: CDSampleWork) -> SampleWorkDTO {
        SampleWorkDTO(
            id: sw.id ?? UUID(),
            lessonID: (sw.lesson as? CDLesson)?.id,
            title: sw.title,
            workKindRaw: sw.workKindRaw,
            orderIndex: Int(sw.orderIndex),
            notes: sw.notes,
            createdAt: sw.createdAt ?? Date()
        )
    }

    // MARK: - CDSampleWorkStep

    static func toDTO(_ step: CDSampleWorkStep) -> SampleWorkStepDTO {
        SampleWorkStepDTO(
            id: step.id ?? UUID(),
            sampleWorkID: step.sampleWork?.id,
            title: step.title,
            orderIndex: Int(step.orderIndex),
            instructions: step.instructions,
            createdAt: step.createdAt ?? Date()
        )
    }

    // MARK: - CDNote

    static func toDTO(_ note: CDNote) -> NoteDTO {
        let scopeString: String
        do {
            let data = try JSONEncoder().encode(note.scope)
            scopeString = String(data: data, encoding: .utf8) ?? "{}"
        } catch {
            logger.warning("Failed to encode note scope: \(error)")
            scopeString = "{}"
        }

        let tagsArray = (note.tags as? [String]) ?? []
        return NoteDTO(
            id: note.id ?? UUID(),
            createdAt: note.createdAt ?? Date(),
            updatedAt: note.updatedAt ?? Date(),
            body: note.body,
            isPinned: note.isPinned,
            scope: scopeString,
            tags: tagsArray.isEmpty ? nil : tagsArray,
            needsFollowUp: note.needsFollowUp ? true : nil,
            lessonID: note.lesson?.id,
            imagePath: note.imagePath
        )
    }

    // MARK: - LessonAttachment

    static func toDTO(_ attachment: LessonAttachment) -> LessonAttachmentDTO {
        LessonAttachmentDTO(
            id: attachment.id ?? UUID(),
            fileName: attachment.fileName,
            fileRelativePath: attachment.fileRelativePath,
            attachedAt: attachment.attachedAt ?? Date(),
            fileType: attachment.fileType,
            fileSizeBytes: attachment.fileSizeBytes,
            scopeRaw: attachment.scopeRaw,
            notes: attachment.notes,
            lessonID: attachment.lesson?.id
        )
    }

    // MARK: - CDLessonPresentation

    static func toDTO(_ lp: CDLessonPresentation) -> LessonPresentationDTO {
        LessonPresentationDTO(
            id: lp.id ?? UUID(),
            createdAt: lp.createdAt ?? Date(),
            studentID: lp.studentID,
            lessonID: lp.lessonID,
            presentationID: lp.presentationID,
            trackID: lp.trackID,
            trackStepID: lp.trackStepID,
            stateRaw: lp.stateRaw,
            presentedAt: lp.presentedAt ?? Date(),
            lastObservedAt: lp.lastObservedAt,
            masteredAt: lp.masteredAt,
            notes: lp.notes
        )
    }

    // MARK: - Batch Transformations (Core)

    static func toDTOs(_ students: [CDStudent]) -> [StudentDTO] {
        students.map { toDTO($0) }
    }

    static func toDTOs(_ lessons: [CDLesson]) -> [LessonDTO] {
        lessons.map { toDTO($0) }
    }

    static func toDTOs(_ notes: [CDNote]) -> [NoteDTO] {
        notes.map { toDTO($0) }
    }

    static func toDTOs(_ sampleWorks: [CDSampleWork]) -> [SampleWorkDTO] {
        sampleWorks.map { toDTO($0) }
    }

    static func toDTOs(_ sampleWorkSteps: [CDSampleWorkStep]) -> [SampleWorkStepDTO] {
        sampleWorkSteps.map { toDTO($0) }
    }

    static func toDTOs(_ attachments: [LessonAttachment]) -> [LessonAttachmentDTO] {
        attachments.map { toDTO($0) }
    }

    static func toDTOs(_ presentations: [CDLessonPresentation]) -> [LessonPresentationDTO] {
        presentations.map { toDTO($0) }
    }
}
