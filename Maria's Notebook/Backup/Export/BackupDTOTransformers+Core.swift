import Foundation
import SwiftData
import OSLog

// MARK: - Core Transformers (Student, Lesson, Note, LessonExercise, LessonAttachment, LessonPresentation)

extension BackupDTOTransformers {

    // MARK: - Student

    static func toDTO(_ student: Student) -> StudentDTO {
        let level: StudentDTO.Level = (student.level == .upper) ? .upper : .lower
        return StudentDTO(
            id: student.id,
            firstName: student.firstName,
            lastName: student.lastName,
            birthday: student.birthday,
            dateStarted: student.dateStarted,
            level: level,
            nextLessons: student.nextLessonUUIDs,
            manualOrder: student.manualOrder,
            createdAt: nil,
            updatedAt: nil
        )
    }

    // MARK: - Lesson

    static func toDTO(_ lesson: Lesson) -> LessonDTO {
        LessonDTO(
            id: lesson.id,
            name: lesson.name,
            subject: lesson.subject,
            group: lesson.group,
            orderInGroup: lesson.orderInGroup,
            subheading: lesson.subheading,
            writeUp: lesson.writeUp,
            createdAt: nil,
            updatedAt: nil,
            pagesFileRelativePath: lesson.pagesFileRelativePath,
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

    // MARK: - LessonExercise

    static func toDTO(_ exercise: LessonExercise) -> LessonExerciseDTO {
        LessonExerciseDTO(
            id: exercise.id,
            lessonID: exercise.lesson?.id,
            orderIndex: exercise.orderIndex,
            title: exercise.title,
            preparation: exercise.preparation,
            presentationSteps: exercise.presentationSteps,
            notes: exercise.notes,
            createdAt: exercise.createdAt
        )
    }

    // MARK: - Note

    static func toDTO(_ note: Note) -> NoteDTO {
        let scopeString: String
        do {
            let data = try JSONEncoder().encode(note.scope)
            scopeString = String(data: data, encoding: .utf8) ?? "{}"
        } catch {
            logger.warning("Failed to encode note scope: \(error)")
            scopeString = "{}"
        }

        return NoteDTO(
            id: note.id,
            createdAt: note.createdAt,
            updatedAt: note.updatedAt,
            body: note.body,
            isPinned: note.isPinned,
            scope: scopeString,
            tags: note.tags.isEmpty ? nil : note.tags,
            needsFollowUp: note.needsFollowUp ? true : nil,
            lessonID: note.lesson?.id,
            imagePath: note.imagePath
        )
    }

    // MARK: - LessonAttachment

    static func toDTO(_ attachment: LessonAttachment) -> LessonAttachmentDTO {
        LessonAttachmentDTO(
            id: attachment.id,
            fileName: attachment.fileName,
            fileRelativePath: attachment.fileRelativePath,
            attachedAt: attachment.attachedAt,
            fileType: attachment.fileType,
            fileSizeBytes: attachment.fileSizeBytes,
            scopeRaw: attachment.scopeRaw,
            notes: attachment.notes,
            lessonID: attachment.lesson?.id
        )
    }

    // MARK: - LessonPresentation

    static func toDTO(_ lp: LessonPresentation) -> LessonPresentationDTO {
        LessonPresentationDTO(
            id: lp.id,
            createdAt: lp.createdAt,
            studentID: lp.studentID,
            lessonID: lp.lessonID,
            presentationID: lp.presentationID,
            trackID: lp.trackID,
            trackStepID: lp.trackStepID,
            stateRaw: lp.stateRaw,
            presentedAt: lp.presentedAt,
            lastObservedAt: lp.lastObservedAt,
            masteredAt: lp.masteredAt,
            notes: lp.notes
        )
    }

    // MARK: - Batch Transformations (Core)

    static func toDTOs(_ students: [Student]) -> [StudentDTO] {
        students.map { toDTO($0) }
    }

    static func toDTOs(_ lessons: [Lesson]) -> [LessonDTO] {
        lessons.map { toDTO($0) }
    }

    static func toDTOs(_ notes: [Note]) -> [NoteDTO] {
        notes.map { toDTO($0) }
    }

    static func toDTOs(_ exercises: [LessonExercise]) -> [LessonExerciseDTO] {
        exercises.map { toDTO($0) }
    }

    static func toDTOs(_ attachments: [LessonAttachment]) -> [LessonAttachmentDTO] {
        attachments.map { toDTO($0) }
    }

    static func toDTOs(_ presentations: [LessonPresentation]) -> [LessonPresentationDTO] {
        presentations.map { toDTO($0) }
    }
}
