import Foundation
import CoreData
import SwiftData
import os

// MARK: - Presentation Recording

extension LifecycleService {

    /// Record a LessonAssignment as presented and upsert LessonPresentation records,
    /// but do NOT auto-create WorkModel items. Use this when work creation is handled separately
    /// (e.g., via the unified workflow panel or explicit user action).
    static func recordPresentation(
        from lessonAssignment: CDLessonAssignment,
        presentedAt: Date,
        modelContext: NSManagedObjectContext
    ) throws -> CDLessonAssignment {
        // CRITICAL: Clean orphaned student IDs before processing to prevent ghost data
        let allStudents = try modelContext.fetch(CDFetchRequest(CDStudent.self))
        let validStudentIDs = Set(allStudents.compactMap { $0.id?.uuidString })
        cleanOrphanedStudentIDs(for: lessonAssignment, validStudentIDs: validStudentIDs, modelContext: modelContext)

        let lessonIDStr = lessonAssignment.lessonID
        let studentIDStrs = lessonAssignment.studentIDs

        // Update to presented state if not already
        if lessonAssignment.state != .presented {
            lessonAssignment.markPresented(at: presentedAt)
        }

        // Update track info if not already set
        if lessonAssignment.trackID == nil, let lesson = lessonAssignment.lesson {
            let subject = lesson.subject.trimmed()
            let group = lesson.group.trimmed()
            if !subject.isEmpty && !group.isEmpty,
               GroupTrackService.isTrack(subject: subject, group: group, context: modelContext) {
                do {
                    let track = try GroupTrackService.getOrCreateTrack(
                        subject: subject,
                        group: group,
                        context: modelContext
                    )
                    lessonAssignment.trackID = track.id?.uuidString
                    if let lessonUUID = UUID(uuidString: lessonIDStr) {
                        let allSteps = safeFetch(
                            CDFetchRequest(CDTrackStepEntity.self),
                            using: modelContext,
                            caller: "recordPresentation"
                        )
                        if let step = allSteps.first(where: {
                            $0.track?.id == track.id && $0.lessonTemplateID == lessonUUID
                        }) {
                            lessonAssignment.trackStepID = step.id?.uuidString
                        }
                    }
                } catch {
                    logger.warning("Failed to get or create track: \(error.localizedDescription)")
                }
            }
        }

        // Upsert LessonPresentation records per student (for individual progress tracking)
        let assignmentIDStr = lessonAssignment.id?.uuidString ?? ""
        for sid in studentIDStrs {
            try upsertLessonPresentation(
                presentationID: assignmentIDStr,
                studentID: sid,
                lessonID: lessonIDStr,
                presentedAt: presentedAt,
                context: modelContext
            )
        }

        return lessonAssignment
    }

    // Record a LessonAssignment as presented and create per-student WorkModel items.
    // Idempotent by (presentationID, studentID) on WorkModel.
    //
    // Only use this when work items should be explicitly created (e.g., GiveLessonViewModel with needsPractice,
    // or the syncAllStudentProgress migration path).
    // swiftlint:disable:next function_body_length
    static func recordPresentationAndExplodeWork(
        from lessonAssignment: CDLessonAssignment,
        presentedAt: Date,
        modelContext: NSManagedObjectContext
    ) throws -> (lessonAssignment: CDLessonAssignment, work: [CDWorkModel]) {
        let la = try recordPresentation(
            from: lessonAssignment,
            presentedAt: presentedAt,
            modelContext: modelContext
        )

        let lessonIDStr = la.lessonID
        let studentIDStrs = la.studentIDs

        // Ensure WorkModels exist per student
        var workForPresentation: [CDWorkModel] = []
        var createdCount = 0
        var skippedCount = 0
        for sid in studentIDStrs {
            // Check for existing WorkModel first
            if let existing = try fetchWorkModel(
                presentationID: la.id?.uuidString ?? "",
                studentID: sid, context: modelContext
            ) {
                workForPresentation.append(existing)
                skippedCount += 1
            } else {
                // Create new WorkModel
                guard let studentUUID = UUID(uuidString: sid),
                      let lessonUUID = UUID(uuidString: lessonIDStr) else {
                    continue
                }

                let repository = WorkRepository(context: modelContext)
                do {
                    let workModel = try repository.createWork(
                        studentID: studentUUID,
                        lessonID: lessonUUID,
                        title: nil,
                        kind: WorkKind.practiceLesson,
                        presentationID: la.id,
                        scheduledDate: nil as Date?
                    )

                    // Link WorkModel to Track if lesson belongs to a track
                    if let lesson = la.lesson {
                        let subject = lesson.subject.trimmed()
                        let group = lesson.group.trimmed()
                        if !subject.isEmpty && !group.isEmpty,
                           GroupTrackService.isTrack(subject: subject, group: group, context: modelContext) {
                            do {
                                _ = try GroupTrackService.getOrCreateTrack(
                                    subject: subject,
                                    group: group,
                                    context: modelContext
                                )
                            } catch {
                                logger.warning("Failed to link work to track: \(error.localizedDescription)")
                            }
                        }
                    }

                    createdCount += 1
                } catch {
                    logger.warning(
                        // swiftlint:disable:next line_length
                        "Failed to create WorkModel for LessonAssignment \(la.id?.uuidString ?? "nil", privacy: .public), student \(sid, privacy: .public): \(error.localizedDescription)"
                    )
                }
            }
        }

        // Fetch all associated WorkModels for this assignment
        let allForAssignment = try fetchAllWorkModels(presentationID: la.id?.uuidString ?? "", context: modelContext)

        return (la, allForAssignment)
    }

    // MARK: - Deprecated SwiftData Bridges

    @available(*, deprecated, message: "Pass CDLessonAssignment and NSManagedObjectContext")
    @discardableResult
    static func recordPresentation(
        from lessonAssignment: LessonAssignment,
        presentedAt: Date,
        modelContext: ModelContext
    ) throws -> LessonAssignment {
        let cdContext = AppBootstrapping.getSharedCoreDataStack().viewContext
        let request = CDFetchRequest(CDLessonAssignment.self)
        request.predicate = NSPredicate(format: "id == %@", lessonAssignment.id as CVarArg)
        request.fetchLimit = 1
        guard let cdLA = cdContext.safeFetch(request).first else { return lessonAssignment }
        _ = try recordPresentation(from: cdLA, presentedAt: presentedAt, modelContext: cdContext)
        cdContext.safeSave()
        return lessonAssignment
    }

    @available(*, deprecated, message: "Pass CDLessonAssignment and NSManagedObjectContext")
    static func recordPresentationAndExplodeWork(
        from lessonAssignment: LessonAssignment,
        presentedAt: Date,
        modelContext: ModelContext
    ) throws -> (lessonAssignment: LessonAssignment, work: [WorkModel]) {
        let cdContext = AppBootstrapping.getSharedCoreDataStack().viewContext
        let request = CDFetchRequest(CDLessonAssignment.self)
        request.predicate = NSPredicate(format: "id == %@", lessonAssignment.id as CVarArg)
        request.fetchLimit = 1
        guard let cdLA = cdContext.safeFetch(request).first else { return (lessonAssignment, []) }
        _ = try recordPresentationAndExplodeWork(from: cdLA, presentedAt: presentedAt, modelContext: cdContext)
        cdContext.safeSave()
        // Re-fetch SwiftData WorkModels
        return (lessonAssignment, [])
    }
}
