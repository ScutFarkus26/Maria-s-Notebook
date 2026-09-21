import SwiftUI
import CoreData
import UniformTypeIdentifiers

/// Unified drop delegate for planning slots (used by both the Planning Board and Agenda views).
///
/// Handles three payload types:
/// 1. Plain UUID — reorder or merge a CDLessonAssignment within a slot
/// 2. `STUDENT_TO_INBOX:` / `STUDENT_TO_SLOT:` — move a student into a slot
/// 3. `UnifiedCalendarDragPayload` — presentation or work check-in scheduling
///
/// The highlight, the insertion indicator and the pasteboard read come from
/// `PresentationDropTarget`; what is here is the slot itself.
struct PlanningSlotDropDelegate: PresentationDropTarget {
    let calendar: Calendar
    let viewContext: NSManagedObjectContext
    let allLessonAssignments: [CDLessonAssignment]
    let day: Date
    let baseDateProvider: () -> Date
    let spacingSeconds: Int
    let getCurrent: () -> [CDLessonAssignment]
    let itemFramesProvider: () -> [UUID: CGRect]
    let onTargetChange: (Bool) -> Void
    let onInsertionIndexChange: (Int?) -> Void

    // MARK: - PresentationDropTarget

    func insertionIndex(at location: CGPoint) -> Int? {
        PlanningDropUtils.computeInsertionIndex(locationY: location.y, frames: currentFrames())
    }

    func handleDroppedText(_ text: String, location: CGPoint) {
        if text.hasPrefix("STUDENT_TO_INBOX:") || text.hasPrefix("STUDENT_TO_SLOT:") {
            handleStudentToSlotPayload(payload: text, location: location)
            return
        }
        handlePlainIDPayload(payload: text, location: location)
    }

    // MARK: - CDStudent-to-slot drops

    private func handleStudentToSlotPayload(payload: String, location: CGPoint) {
        let parts = payload.split(separator: ":")
        guard parts.count == 4,
              let srcID = UUID(uuidString: String(parts[1])),
              let lessonID = UUID(uuidString: String(parts[2])),
              let studentID = UUID(uuidString: String(parts[3])) else {
            return
        }

        let current = getCurrent()
        var ids = current.compactMap(\.id)
        let insertionIndex = PlanningDropUtils.computeInsertionIndex(
            locationY: location.y, frames: currentFrames(current)
        )

        let targetLA = findOrCreateTargetLessonAssignment(lessonID: lessonID, studentID: studentID)
        guard let targetID = targetLA.id else { return }

        ids.removeAll(where: { $0 == targetID })
        let boundedIndex = max(0, min(insertionIndex, ids.count))
        ids.insert(targetID, at: boundedIndex)

        let timeMap = PlanningDropUtils.assignSequentialTimes(
            ids: ids, base: baseDateProvider(), calendar: calendar,
            spacingSeconds: spacingSeconds
        )
        applyTimeMap(ids: ids, timeMap: timeMap, targetLA: targetLA)

        removeStudentFromSource(srcID: srcID, studentID: studentID)
        saveContext("student move")

        PresentationDropHandling.autoPopulateSequence(
            for: targetLA, fallbackDate: baseDateProvider, context: viewContext
        )
    }

    // MARK: - Plain UUID (reorder / merge) drops

    private func handlePlainIDPayload(payload: String, location: CGPoint) {
        guard let id = UUID(uuidString: payload.trimmed()) else {
            return
        }

        let current = getCurrent()

        // Check if the drop landed on a pill for the same lesson — merge instead of reorder
        if let targetLA = PresentationDropHandling.mergeTarget(
            for: id, locationY: location.y, among: current,
            in: allLessonAssignments, frames: itemFramesProvider()
        ) {
            if let targetLAID = targetLA.id {
                PresentationMergeService.merge(
                    sourceID: id,
                    targetID: targetLAID,
                    context: viewContext
                )
            }
            return
        }

        var ids = current.compactMap(\.id)
        if let existing = ids.firstIndex(of: id) {
            ids.remove(at: existing)
        }

        let insertionIndex = PlanningDropUtils.computeInsertionIndex(
            locationY: location.y, frames: currentFrames(current)
        )
        let bounded = max(0, min(insertionIndex, ids.count))
        ids.insert(id, at: bounded)

        let timeMap = PlanningDropUtils.assignSequentialTimes(
            ids: ids, base: baseDateProvider(), calendar: calendar,
            spacingSeconds: spacingSeconds
        )
        applyTimeMapForReorder(ids: ids, timeMap: timeMap)
        saveContext("reorder")
    }

    // MARK: - Helpers

    private func currentFrames(_ current: [CDLessonAssignment]? = nil) -> [UUID: CGRect] {
        PresentationDropHandling.frames(
            for: (current ?? getCurrent()).compactMap(\.id),
            in: itemFramesProvider()
        )
    }

    private func findOrCreateTargetLessonAssignment(lessonID: UUID, studentID: UUID) -> CDLessonAssignment {
        let studentIDString = studentID.uuidString
        let lessonIDString = lessonID.uuidString

        if let existing = allLessonAssignments.first(where: { la in
            la.lessonID == lessonIDString && la.scheduledFor == nil && !la.isGiven && la.studentIDs == [studentIDString]
        }) {
            return existing
        }

        let new = PresentationFactory.makeDraft(lessonID: lessonID, studentIDs: [studentID], context: viewContext)

        new.lesson = viewContext.object(CDLesson.self, id: lessonID)
        return new
    }

    private func applyTimeMap(ids: [UUID], timeMap: [UUID: Date], targetLA: CDLessonAssignment) {
        for id in ids {
            if let item = allLessonAssignments.first(where: { $0.id == id }) {
                item.setScheduledFor(timeMap[id], using: AppCalendar.shared)
                autoEnrollIfNeeded(item)
            }
            if id == targetLA.id {
                targetLA.setScheduledFor(timeMap[id], using: AppCalendar.shared)
                autoEnrollIfNeeded(targetLA)
            }
        }
    }

    private func applyTimeMapForReorder(ids: [UUID], timeMap: [UUID: Date]) {
        for id in ids {
            if let item = allLessonAssignments.first(where: { $0.id == id }) {
                item.setScheduledFor(timeMap[id], using: AppCalendar.shared)
                autoEnrollIfNeeded(item)
            }
        }
    }

    private func autoEnrollIfNeeded(_ item: CDLessonAssignment) {
        if let lesson = item.lesson {
            SequenceTrackService.autoEnrollInTrackIfNeeded(
                lessonArea: lesson.area,
                lessonSequence: lesson.sequence,
                studentIDs: item.studentIDs,
                context: viewContext
            )
        }
    }

    private func removeStudentFromSource(srcID: UUID, studentID: UUID) {
        guard let src = allLessonAssignments.first(where: { $0.id == srcID }) else {
            return
        }

        let studentIDString = studentID.uuidString
        src.studentIDs.removeAll { $0 == studentIDString }

        if src.studentIDs.isEmpty {
            viewContext.delete(src)
        }
    }

    private func saveContext(_ operation: String) {
        viewContext.safeSave()
    }
}
