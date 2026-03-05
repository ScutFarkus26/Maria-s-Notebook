import Foundation
import SwiftData

// MARK: - Lessons

extension BackupEntityImporter {

    /// Imports lessons from DTOs.
    static func importLessons(
        _ dtos: [LessonDTO],
        into modelContext: ModelContext,
        existingCheck: EntityExistsCheck<Lesson>
    ) rethrows {
        try importSimpleEntities(dtos, into: modelContext, existingCheck: existingCheck, idExtractor: { $0.id }, entityBuilder: { dto in
            let lesson = Lesson(id: dto.id, name: dto.name, subject: dto.subject, group: dto.group, orderInGroup: dto.orderInGroup, subheading: dto.subheading, writeUp: dto.writeUp)
            if let pages = dto.pagesFileRelativePath { lesson.pagesFileRelativePath = pages }
            // Format v9+ fields
            if let v = dto.suggestedFollowUpWork { lesson.suggestedFollowUpWork = v }
            if let v = dto.sourceRaw { lesson.sourceRaw = v }
            if let v = dto.personalKindRaw { lesson.personalKindRaw = v }
            if let v = dto.defaultWorkKindRaw { lesson.defaultWorkKindRaw = v }
            if let v = dto.materials { lesson.materials = v }
            if let v = dto.purpose { lesson.purpose = v }
            if let v = dto.ageRange { lesson.ageRange = v }
            if let v = dto.teacherNotes { lesson.teacherNotes = v }
            if let v = dto.prerequisiteLessonIDs { lesson.prerequisiteLessonIDs = v }
            if let v = dto.relatedLessonIDs { lesson.relatedLessonIDs = v }
            return lesson
        })
    }

    // MARK: - Lesson Exercises

    /// Imports lesson exercises from DTOs.
    static func importLessonExercises(
        _ dtos: [LessonExerciseDTO],
        into modelContext: ModelContext,
        existingCheck: EntityExistsCheck<LessonExercise>,
        lessonCheck: EntityExistsCheck<Lesson>
    ) rethrows {
        for dto in dtos {
            if shouldSkipExisting(id: dto.id, existingCheck: existingCheck) { continue }
            let exercise = LessonExercise(
                id: dto.id,
                orderIndex: dto.orderIndex,
                title: dto.title,
                preparation: dto.preparation,
                presentationSteps: dto.presentationSteps,
                notes: dto.notes,
                createdAt: dto.createdAt
            )
            if let lessonID = dto.lessonID {
                do {
                    if let lesson = try lessonCheck(lessonID) {
                        exercise.lesson = lesson
                    }
                } catch {
                    print("⚠️ [Backup:\(#function)] Failed to check lesson for exercise: \(error)")
                }
            }
            modelContext.insert(exercise)
        }
    }

    // MARK: - Legacy Presentations

    /// Imports legacy presentations from DTOs.
    ///
    /// - Parameters:
    ///   - dtos: The legacy presentation DTOs to import
    ///   - modelContext: The model context for database operations
    /// Imports old LegacyPresentationDTO records as LessonAssignment records.
    /// This provides backward compatibility when restoring backups created before
    /// the LegacyPresentation model was removed.
    ///   - existingCheck: Function to check if a LessonAssignment already exists with this ID
    ///   - lessonCheck: Function to check if the referenced lesson exists
    ///   - studentCheck: Function to look up a student by ID
    static func importLegacyPresentations(
        _ dtos: [LegacyPresentationDTO],
        into modelContext: ModelContext,
        existingCheck: EntityExistsCheck<LessonAssignment>,
        lessonCheck: EntityExistsCheck<Lesson>,
        studentCheck: EntityExistsCheck<Student>
    ) rethrows {
        for dto in dtos {
            // Skip if lesson doesn't exist
            do {
                guard try lessonCheck(dto.lessonID) != nil else { continue }
            } catch {
                print("⚠️ [Backup:\(#function)] Failed to check lesson existence: \(error)")
                continue
            }
            // Skip if already exists
            do {
                if try existingCheck(dto.id) != nil { continue }
            } catch {
                print("⚠️ [Backup:\(#function)] Failed to check existing lesson assignment: \(error)")
                continue
            }

            // Determine state from old LegacyPresentation fields
            let state: LessonAssignmentState
            let presentedAt: Date?
            if dto.givenAt != nil {
                state = .presented
                presentedAt = dto.givenAt
            } else if dto.scheduledFor != nil {
                state = .scheduled
                presentedAt = nil
            } else {
                state = .draft
                presentedAt = nil
            }

            let la = LessonAssignment(
                id: dto.id,
                createdAt: dto.createdAt,
                state: state,
                scheduledFor: dto.scheduledFor,
                presentedAt: presentedAt,
                lessonID: dto.lessonID,
                studentIDs: dto.studentIDs,
                needsPractice: dto.needsPractice,
                needsAnotherPresentation: dto.needsAnotherPresentation,
                followUpWork: dto.followUpWork,
                notes: dto.notes
            )
            la.migratedFromStudentLessonID = dto.id.uuidString

            var linkedStudents: [Student] = []
            for studentID in dto.studentIDs {
                do {
                    if let student = try studentCheck(studentID) {
                        linkedStudents.append(student)
                    }
                } catch {
                    print("⚠️ [Backup:\(#function)] Failed to check student: \(error)")
                    continue
                }
            }
            if !linkedStudents.isEmpty {
                la.students = linkedStudents
            }

            modelContext.insert(la)
        }
    }

    // MARK: - LessonAssignments

    /// Imports lesson assignments from DTOs.
    ///
    /// - Parameters:
    ///   - dtos: The lesson assignment DTOs to import
    ///   - modelContext: The model context for database operations
    ///   - existingCheck: Function to check if a lesson assignment already exists
    ///   - lessonCheck: Function to look up a lesson by ID for linking
    static func importLessonAssignments(
        _ dtos: [LessonAssignmentDTO],
        into modelContext: ModelContext,
        existingCheck: EntityExistsCheck<LessonAssignment>,
        lessonCheck: EntityExistsCheck<Lesson>
    ) rethrows {
        for dto in dtos {
            do {
                if try existingCheck(dto.id) != nil { continue }
            } catch {
                print("⚠️ [Backup:\(#function)] Failed to check existing lesson assignment: \(error)")
                continue
            }

            // Parse state from raw value
            let state = LessonAssignmentState(rawValue: dto.stateRaw) ?? .draft

            // Parse lesson ID
            guard let lessonUUID = UUID(uuidString: dto.lessonID) else { continue }

            // Parse student IDs
            let studentUUIDs = dto.studentIDs.compactMap { UUID(uuidString: $0) }

            let assignment = LessonAssignment(
                id: dto.id,
                createdAt: dto.createdAt,
                state: state,
                scheduledFor: dto.scheduledFor,
                presentedAt: dto.presentedAt,
                lessonID: lessonUUID,
                studentIDs: studentUUIDs,
                lesson: nil,
                needsPractice: dto.needsPractice,
                needsAnotherPresentation: dto.needsAnotherPresentation,
                followUpWork: dto.followUpWork,
                notes: dto.notes,
                trackID: dto.trackID,
                trackStepID: dto.trackStepID
            )

            // Update modifiedAt
            assignment.modifiedAt = dto.modifiedAt

            // Set snapshots
            assignment.lessonTitleSnapshot = dto.lessonTitleSnapshot
            assignment.lessonSubheadingSnapshot = dto.lessonSubheadingSnapshot

            // Set migration tracking
            assignment.migratedFromStudentLessonID = dto.migratedFromLegacyID
            assignment.migratedFromPresentationID = dto.migratedFromPresentationID

            // Link to lesson if exists
            do {
                if let lesson = try lessonCheck(lessonUUID) {
                    assignment.lesson = lesson
                }
            } catch {
                print("⚠️ [Backup:\(#function)] Failed to check lesson for assignment: \(error)")
            }

            modelContext.insert(assignment)
        }
    }

    // MARK: - Lesson Attachments

    static func importLessonAttachments(
        _ dtos: [LessonAttachmentDTO],
        into modelContext: ModelContext,
        existingCheck: EntityExistsCheck<LessonAttachment>,
        lessonCheck: EntityExistsCheck<Lesson>
    ) rethrows {
        for dto in dtos {
            if shouldSkipExisting(id: dto.id, existingCheck: existingCheck) { continue }
            let attachment = LessonAttachment()
            attachment.id = dto.id
            attachment.fileName = dto.fileName
            attachment.fileRelativePath = dto.fileRelativePath
            attachment.attachedAt = dto.attachedAt
            attachment.fileType = dto.fileType
            attachment.fileSizeBytes = dto.fileSizeBytes
            attachment.scopeRaw = dto.scopeRaw
            attachment.notes = dto.notes
            if let lessonID = dto.lessonID {
                do {
                    if let lesson = try lessonCheck(lessonID) {
                        attachment.lesson = lesson
                    }
                } catch {
                    print("⚠️ [Backup:\(#function)] Failed to check lesson for attachment: \(error)")
                }
            }
            modelContext.insert(attachment)
        }
    }

    // MARK: - Lesson Presentations

    static func importLessonPresentations(_ dtos: [LessonPresentationDTO], into modelContext: ModelContext, existingCheck: EntityExistsCheck<LessonPresentation>) rethrows {
        try importSimpleEntities(dtos, into: modelContext, existingCheck: existingCheck, idExtractor: { $0.id }, entityBuilder: { dto in
            let lp = LessonPresentation(
                id: dto.id,
                createdAt: dto.createdAt,
                studentID: dto.studentID,
                lessonID: dto.lessonID,
                presentationID: dto.presentationID,
                trackID: dto.trackID,
                trackStepID: dto.trackStepID,
                state: LessonPresentationState(rawValue: dto.stateRaw) ?? .presented,
                presentedAt: dto.presentedAt,
                lastObservedAt: dto.lastObservedAt,
                masteredAt: dto.masteredAt,
                notes: dto.notes
            )
            return lp
        })
    }
}
