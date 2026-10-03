import CoreData
import Foundation

// MARK: - Lesson mirroring

extension SampleClassroomSeeder {
    static func lessonSnapshots(from context: NSManagedObjectContext) throws -> [LessonSnapshot] {
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

            let sampleWorks = ((lesson.sampleWorks?.allObjects as? [CDSampleWork]) ?? [])
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

    static func mirror(
        lessons: [LessonSnapshot],
        into context: NSManagedObjectContext
    ) throws {
        let existingLessons = try context.fetch(CDFetchRequest(CDLesson.self))
        var lessonsByID = firstByID(existingLessons, id: \CDLesson.id)

        let existingAttachments = try context.fetch(CDFetchRequest(CDLessonAttachment.self))
        var attachmentsByID = firstByID(existingAttachments, id: \CDLessonAttachment.id)

        let existingWorks = try context.fetch(CDFetchRequest(CDSampleWork.self))
        var worksByID = firstByID(existingWorks, id: \CDSampleWork.id)

        let existingSteps = try context.fetch(CDFetchRequest(CDSampleWorkStep.self))
        var stepsByID = firstByID(existingSteps, id: \CDSampleWorkStep.id)

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
                let work = worksByID[workSnapshot.id] ?? CDSampleWork(context: context)
                work.id = workSnapshot.id
                work.title = workSnapshot.title
                work.workKindRaw = workSnapshot.workKindRaw
                work.orderIndex = workSnapshot.orderIndex
                work.notes = workSnapshot.notes
                work.createdAt = workSnapshot.createdAt
                work.lesson = lesson
                worksByID[workSnapshot.id] = work

                for stepSnapshot in workSnapshot.steps {
                    let step = stepsByID[stepSnapshot.id] ?? CDSampleWorkStep(context: context)
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
}
