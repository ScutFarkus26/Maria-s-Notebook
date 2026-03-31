import SwiftUI
import CoreData
import OSLog
import UniformTypeIdentifiers

/// Unified drop delegate for planning slots (used by both the Planning Board and Agenda views).
///
/// Handles three payload types:
/// 1. Plain UUID — reorder or merge a CDLessonAssignment within a slot
/// 2. `STUDENT_TO_INBOX:` / `STUDENT_TO_SLOT:` — move a student into a slot
/// 3. `UnifiedCalendarDragPayload` — presentation or work check-in scheduling
struct PlanningSlotDropDelegate: DropDelegate {
    private static let logger = Logger.planning

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

    // MARK: - DropDelegate

    func dropEntered(info: DropInfo) {
        onTargetChange(true)
        onInsertionIndexChange(computeIndex(info))
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        onInsertionIndexChange(computeIndex(info))
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        onTargetChange(false)
        onInsertionIndexChange(nil)
    }

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [UTType.text])
    }

    func performDrop(info: DropInfo) -> Bool {
        onTargetChange(false)
        onInsertionIndexChange(nil)
        let providers = info.itemProviders(for: [UTType.text])
        return loadAndHandleDrop(providers: providers, location: info.location)
    }

    // MARK: - Async loading

    private func loadAndHandleDrop(providers: [NSItemProvider], location: CGPoint) -> Bool {
        guard let provider = providers.first, provider.canLoadObject(ofClass: NSString.self) else {
            return false
        }
        provider.loadObject(ofClass: NSString.self) { reading, _ in
            guard let ns = reading as? NSString else { return }
            let payload = ns as String
            Task { @MainActor in
                self.handleDropPayload(payload: payload, location: location)
            }
        }
        return true
    }

    // MARK: - Payload routing

    @MainActor
    private func handleDropPayload(payload: String, location: CGPoint) {
        if payload.hasPrefix("STUDENT_TO_INBOX:") || payload.hasPrefix("STUDENT_TO_SLOT:") {
            handleStudentToSlotPayload(payload: payload, location: location)
            return
        }
        handlePlainIDPayload(payload: payload, location: location)
    }

    // MARK: - Student-to-slot drops

    @MainActor
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
        let dict = buildFramesDictionary(current: current)
        let insertionIndex = PlanningDropUtils.computeInsertionIndex(locationY: location.y, frames: dict)

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
    }

    // MARK: - Plain UUID (reorder / merge) drops

    @MainActor
    private func handlePlainIDPayload(payload: String, location: CGPoint) {
        guard let id = UUID(uuidString: payload.trimmed()) else {
            return
        }

        let current = getCurrent()

        // Check if the drop landed on a pill for the same lesson — merge instead of reorder
        if let source = allLessonAssignments.first(where: { $0.id == id }), !source.isGiven {
            let frames = itemFramesProvider()
            let dropY = location.y
            if let targetLA = current.first(where: { la in
                guard let laID = la.id, laID != id, !la.isGiven,
                      la.resolvedLessonID == source.resolvedLessonID,
                      let frame = frames[laID] else { return false }
                return dropY >= frame.minY && dropY <= frame.maxY
            }) {
                if let targetLAID = targetLA.id {
                    PresentationMergeService.merge(
                        sourceID: id,
                        targetID: targetLAID,
                        context: viewContext
                    )
                }
                return
            }
        }

        var ids = current.compactMap(\.id)
        if let existing = ids.firstIndex(of: id) {
            ids.remove(at: existing)
        }

        let dict = buildFramesDictionary(current: current)
        let insertionIndex = PlanningDropUtils.computeInsertionIndex(locationY: location.y, frames: dict)
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

    private func buildFramesDictionary(current: [CDLessonAssignment]) -> [UUID: CGRect] {
        let frames = itemFramesProvider()
        return Dictionary(
            current.compactMap { item -> (UUID, CGRect)? in
                guard let itemID = item.id, let rect = frames[itemID] else { return nil }
                return (itemID, rect)
            },
            uniquingKeysWith: { first, _ in first }
        )
    }

    @MainActor
    private func findOrCreateTargetLessonAssignment(lessonID: UUID, studentID: UUID) -> CDLessonAssignment {
        let studentIDString = studentID.uuidString
        let lessonIDString = lessonID.uuidString

        if let existing = allLessonAssignments.first(where: { la in
            la.lessonID == lessonIDString && la.scheduledFor == nil && !la.isGiven && la.studentIDs == [studentIDString]
        }) {
            return existing
        }

        let new = PresentationFactory.makeDraft(lessonID: lessonID, studentIDs: [studentID])

        let lessonFetch = NSFetchRequest<CDLesson>(entityName: "CDLesson")
        lessonFetch.predicate = NSPredicate(format: "id == %@", lessonID as CVarArg)
        lessonFetch.fetchLimit = 1
        do {
            new.lesson = try viewContext.fetch(lessonFetch).first
        } catch {
            Self.logger.warning("Failed to fetch lesson: \(error)")
        }
        return new
    }

    @MainActor
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

    @MainActor
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
            GroupTrackService.autoEnrollInTrackIfNeeded(
                lessonSubject: lesson.subject,
                lessonGroup: lesson.group,
                studentIDs: item.studentIDs,
                context: viewContext
            )
        }
    }

    @MainActor
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

    private func computeIndex(_ info: DropInfo) -> Int {
        let current = getCurrent()
        let dict = buildFramesDictionary(current: current)
        return PlanningDropUtils.computeInsertionIndex(locationY: info.location.y, frames: dict)
    }

    private func saveContext(_ operation: String) {
        do {
            try viewContext.save()
        } catch {
            Self.logger.warning("Failed to save context after \(operation): \(error)")
        }
    }
}
