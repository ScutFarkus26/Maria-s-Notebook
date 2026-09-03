import Foundation
import CoreData
import os

// MARK: - Presentation Recording

extension LifecycleService {

    /// Record a CDLessonAssignment as presented and upsert CDLessonPresentation records,
    /// but do NOT auto-create CDWorkModel items. Use this when work creation is handled separately
    /// (e.g., via the unified workflow panel or explicit user action).
    static func recordPresentation(
        from lessonAssignment: CDLessonAssignment,
        presentedAt: Date,
        modelContext: NSManagedObjectContext,
        beginFollowUp: Bool = true
    ) throws -> CDLessonAssignment {
        // CRITICAL: Clean orphaned student IDs before processing to prevent ghost data
        let allStudents = try modelContext.fetch(CDFetchRequest(CDStudent.self))
        let validStudentIDs = Set(allStudents.compactMap { $0.id?.uuidString })
        cleanOrphanedStudentIDs(for: lessonAssignment, validStudentIDs: validStudentIDs, modelContext: modelContext)

        let lessonIDStr = lessonAssignment.lessonID
        let studentIDStrs = lessonAssignment.studentIDs

        // Apply the supplied occurrence date even when this assignment was
        // previously stored as an undated or older presentation. The operation is
        // still idempotent because the per-student rows are upserted below.
        lessonAssignment.markPresented(at: presentedAt)

        // Update track info if not already set
        if lessonAssignment.trackID == nil, let lesson = lessonAssignment.lesson {
            let area = lesson.area.trimmed()
            let sequence = lesson.sequence.trimmed()
            if !area.isEmpty && !sequence.isEmpty,
               SequenceTrackService.isTrack(area: area, sequence: sequence, context: modelContext) {
                do {
                    let track = try SequenceTrackService.getOrCreateTrack(
                        area: area,
                        sequence: sequence,
                        context: modelContext
                    )
                    lessonAssignment.trackID = track.id?.uuidString
                    if let lessonUUID = UUID(uuidString: lessonIDStr) {
                        let allSteps = modelContext.safeFetch(CDFetchRequest(CDTrackStepEntity.self))
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

        // Upsert CDLessonPresentation records per student (for individual progress tracking)
        let assignmentIDStr = lessonAssignment.id?.uuidString ?? ""
        for sid in studentIDStrs {
            let historyRow = try upsertLessonPresentation(
                presentationID: assignmentIDStr,
                studentID: sid,
                lessonID: lessonIDStr,
                presentedAt: presentedAt,
                context: modelContext
            )
            if beginFollowUp {
                PresentationFollowUpService.beginFollowing(historyRow, at: presentedAt)
            }
        }

        return lessonAssignment
    }

    // Record a CDLessonAssignment as presented and create per-student CDWorkModel items.
    // Idempotent by (presentationID, studentID) on CDWorkModel.
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
            // Check for existing CDWorkModel first
            if let existing = try fetchWorkModel(
                presentationID: la.id?.uuidString ?? "",
                studentID: sid, context: modelContext
            ) {
                workForPresentation.append(existing)
                skippedCount += 1
            } else {
                // Create new CDWorkModel
                guard let studentUUID = UUID(uuidString: sid),
                      let lessonUUID = UUID(uuidString: lessonIDStr) else {
                    continue
                }

                let repository = WorkRepository(context: modelContext)
                do {
                    _ = try repository.createWork(
                        studentID: studentUUID,
                        lessonID: lessonUUID,
                        title: nil,
                        kind: WorkKind.practiceLesson,
                        presentationID: la.id,
                        scheduledDate: nil as Date?
                    )

                    // Link CDWorkModel to CDTrackEntity if lesson belongs to a track
                    if let lesson = la.lesson {
                        let area = lesson.area.trimmed()
                        let sequence = lesson.sequence.trimmed()
                        if !area.isEmpty && !sequence.isEmpty,
                           SequenceTrackService.isTrack(area: area, sequence: sequence, context: modelContext) {
                            do {
                                _ = try SequenceTrackService.getOrCreateTrack(
                                    area: area,
                                    sequence: sequence,
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
                        "Failed to create CDWorkModel for CDLessonAssignment \(la.id?.uuidString ?? "nil", privacy: .public), student \(sid, privacy: .public): \(error.localizedDescription)"
                    )
                }
            }
        }

        // Fetch all associated WorkModels for this assignment
        let allForAssignment = try fetchAllWorkModels(presentationID: la.id?.uuidString ?? "", context: modelContext)

        return (la, allForAssignment)
    }

    // Deprecated SwiftData bridge methods removed - no longer needed with Core Data.
}
