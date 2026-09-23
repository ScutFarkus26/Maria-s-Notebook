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
        let validStudentIDs = try existingStudentIDStrings(namedBy: lessonAssignment, context: modelContext)
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
                        // This lesson's steps only (UUID attribute, UUID argument);
                        // the track match stays in memory as before.
                        let stepRequest = CDFetchRequest(CDTrackStep.self)
                        stepRequest.predicate = NSPredicate(format: "lessonTemplateID == %@", lessonUUID as CVarArg)
                        let lessonSteps = modelContext.safeFetch(stepRequest)
                        if let step = lessonSteps.first(where: {
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

        // The history rows above are what settle these children's year-plan
        // intentions — that reading is derived, not written (YearPlanSatisfaction).
        // What is not derived is a plan for the same lesson still sitting on
        // another day: take the children who have just had it off that group.
        YearPlanReleaseService.releaseRedundantPlans(after: lessonAssignment, in: modelContext)

        return lessonAssignment
    }

    /// The `uuidString`s of the students `lessonAssignment` names that exist.
    /// Only those students can be valid, so this reads them (by UUID — `id` is
    /// a UUID attribute) rather than the whole roster; an id string that
    /// doesn't parse, or whose student is gone, is absent from the set exactly
    /// as it was from the whole-roster set.
    static func existingStudentIDStrings(
        namedBy lessonAssignment: CDLessonAssignment,
        context: NSManagedObjectContext
    ) throws -> Set<String> {
        let named = Array(Set(lessonAssignment.studentIDs.compactMap(UUID.init(uuidString:))))
        guard !named.isEmpty else { return [] }
        let request = CDFetchRequest(CDStudent.self)
        request.predicate = NSPredicate(format: "id IN %@", named)
        return Set(try context.fetch(request).compactMap { $0.id?.uuidString })
    }

    // Record a CDLessonAssignment as presented and create per-student CDWorkModel items.
    // Idempotent by (presentationID, studentID) on CDWorkModel.
    //
    // Only use this when work items should be explicitly created (e.g., GiveLessonViewModel with needsPractice).
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

}
