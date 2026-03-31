import Foundation
import CoreData
import OSLog

// MARK: - Lessons

extension BackupEntityImporter {

    // Imports lessons from DTOs.
    // swiftlint:disable:next cyclomatic_complexity
    static func importLessons(
        _ dtos: [LessonDTO],
        into viewContext: NSManagedObjectContext,
        existingCheck: EntityExistsCheck<CDLesson>
    ) rethrows {
        try importSimpleEntities(
            dtos, into: viewContext,
            existingCheck: existingCheck,
            idExtractor: { $0.id },
            entityBuilder: { dto in
            let lesson = CDLesson(context: viewContext)
            lesson.id = dto.id
            lesson.name = dto.name
            lesson.subject = dto.subject
            lesson.group = dto.group
            lesson.orderInGroup = Int64(dto.orderInGroup)
            lesson.subheading = dto.subheading
            lesson.writeUp = dto.writeUp
            if let pages = dto.pagesFileRelativePath { lesson.pagesFileRelativePath = pages }
            if let primaryAttachmentID = dto.primaryAttachmentID {
                lesson.primaryAttachmentID = primaryAttachmentID.uuidString
            }
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

    // MARK: - Sample Works

    /// Imports sample works from DTOs.
    static func importSampleWorks(
        _ dtos: [SampleWorkDTO],
        into viewContext: NSManagedObjectContext,
        existingCheck: EntityExistsCheck<CDSampleWork>,
        lessonCheck: EntityExistsCheck<CDLesson>
    ) rethrows {
        for dto in dtos {
            if shouldSkipExisting(id: dto.id, existingCheck: existingCheck) { continue }
            let sw = CDSampleWork(context: viewContext)
            sw.id = dto.id
            sw.title = dto.title
            sw.workKindRaw = (WorkKind(rawValue: dto.workKindRaw) ?? .practiceLesson).rawValue
            sw.orderIndex = Int64(dto.orderIndex)
            sw.notes = dto.notes
            sw.createdAt = dto.createdAt
            if let lessonID = dto.lessonID {
                do {
                    if let lesson = try lessonCheck(lessonID) {
                        sw.lesson = lesson
                    }
                } catch {
                    let desc = error.localizedDescription
                    Logger.backup.warning("Failed to check lesson for sample work: \(desc, privacy: .public)")
                }
            }
            viewContext.insert(sw)
        }
    }

    // MARK: - Sample Work Steps

    /// Imports sample work steps from DTOs.
    static func importSampleWorkSteps(
        _ dtos: [SampleWorkStepDTO],
        into viewContext: NSManagedObjectContext,
        existingCheck: EntityExistsCheck<CDSampleWorkStep>,
        sampleWorkCheck: EntityExistsCheck<CDSampleWork>
    ) rethrows {
        for dto in dtos {
            if shouldSkipExisting(id: dto.id, existingCheck: existingCheck) { continue }
            let step = CDSampleWorkStep(context: viewContext)
            step.id = dto.id
            step.title = dto.title
            step.orderIndex = Int64(dto.orderIndex)
            step.instructions = dto.instructions
            step.createdAt = dto.createdAt
            if let sampleWorkID = dto.sampleWorkID {
                do {
                    if let sw = try sampleWorkCheck(sampleWorkID) {
                        step.sampleWork = sw
                    }
                } catch {
                    let desc = error.localizedDescription
                    Logger.backup.warning("Failed to check sample work for step: \(desc, privacy: .public)")
                }
            }
            viewContext.insert(step)
        }
    }

    // MARK: - LessonAssignments

    /// Imports lesson assignments from DTOs.
    ///
    /// - Parameters:
    ///   - dtos: The lesson assignment DTOs to import
    ///   - viewContext: The model context for database operations
    ///   - existingCheck: Function to check if a lesson assignment already exists
    ///   - lessonCheck: Function to look up a lesson by ID for linking
    static func importLessonAssignments(
        _ dtos: [LessonAssignmentDTO],
        into viewContext: NSManagedObjectContext,
        existingCheck: EntityExistsCheck<CDLessonAssignment>,
        lessonCheck: EntityExistsCheck<CDLesson>
    ) rethrows {
        for dto in dtos {
            do {
                if try existingCheck(dto.id) != nil { continue }
            } catch {
                let desc = error.localizedDescription
                Logger.backup.warning("Failed to check existing lesson assignment: \(desc, privacy: .public)")
                continue
            }

            // Parse state from raw value
            let state = LessonAssignmentState(rawValue: dto.stateRaw) ?? .draft

            // Parse lesson ID
            guard let lessonUUID = UUID(uuidString: dto.lessonID) else { continue }

            // Parse student IDs
            let studentUUIDs = dto.studentIDs.compactMap { UUID(uuidString: $0) }

            let assignment = CDLessonAssignment(context: viewContext)
            assignment.id = dto.id
            assignment.createdAt = dto.createdAt
            assignment.stateRaw = state.rawValue
            assignment.scheduledFor = dto.scheduledFor
            assignment.presentedAt = dto.presentedAt
            assignment.lessonID = lessonUUID.uuidString
            assignment.studentIDs = studentUUIDs.map(\.uuidString)
            assignment.needsPractice = dto.needsPractice
            assignment.needsAnotherPresentation = dto.needsAnotherPresentation
            assignment.followUpWork = dto.followUpWork
            assignment.notes = dto.notes
            assignment.trackID = dto.trackID
            assignment.trackStepID = dto.trackStepID

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
                let desc = error.localizedDescription
                Logger.backup.warning("Failed to check lesson for assignment: \(desc, privacy: .public)")
            }

            viewContext.insert(assignment)
        }
    }

    // MARK: - CDLesson Attachments

    static func importLessonAttachments(
        _ dtos: [LessonAttachmentDTO],
        into viewContext: NSManagedObjectContext,
        existingCheck: EntityExistsCheck<LessonAttachment>,
        lessonCheck: EntityExistsCheck<CDLesson>
    ) rethrows {
        for dto in dtos {
            if shouldSkipExisting(id: dto.id, existingCheck: existingCheck) { continue }
            let attachment = LessonAttachment(context: viewContext)
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
                    let desc = error.localizedDescription
                    Logger.backup.warning("Failed to check lesson for attachment: \(desc, privacy: .public)")
                }
            }
            viewContext.insert(attachment)
        }
    }

    // MARK: - CDLesson Presentations

    static func importLessonPresentations(
        _ dtos: [LessonPresentationDTO],
        into viewContext: NSManagedObjectContext,
        existingCheck: EntityExistsCheck<CDLessonPresentation>
    ) rethrows {
        try importSimpleEntities(
            dtos, into: viewContext,
            existingCheck: existingCheck,
            idExtractor: { $0.id },
            entityBuilder: { dto in
            let lp = CDLessonPresentation(context: viewContext)
            lp.id = dto.id
            lp.createdAt = dto.createdAt
            lp.studentID = dto.studentID
            lp.lessonID = dto.lessonID
            lp.presentationID = dto.presentationID
            lp.trackID = dto.trackID
            lp.trackStepID = dto.trackStepID
            lp.stateRaw = (LessonPresentationState(rawValue: dto.stateRaw) ?? .presented).rawValue
            lp.presentedAt = dto.presentedAt
            lp.lastObservedAt = dto.lastObservedAt
            lp.masteredAt = dto.masteredAt
            lp.notes = dto.notes
            return lp
        })
    }
}
