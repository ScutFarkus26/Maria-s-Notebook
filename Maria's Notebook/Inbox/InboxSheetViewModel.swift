// InboxSheetViewModel.swift
// ViewModel for InboxSheetView - handles consolidation and drop logic

import SwiftUI
import SwiftData
import Combine

@MainActor
final class InboxSheetViewModel: ObservableObject {
    // MARK: - Published State
    @Published var selected: Set<UUID> = []
    @Published var toastMessage: String? = nil

    // MARK: - Callbacks
    var onUpdateOrder: ((String) -> Void)?

    // MARK: - Computed Properties

    var isSelectionMode: Bool {
        !selected.isEmpty
    }

    func canConsolidate(orderedUnscheduledLessons: [StudentLesson]) -> Bool {
        let selectedSLs = orderedUnscheduledLessons.filter { selected.contains($0.id) }
        let groups = selectedSLs.grouped(by: { $0.lessonID })
        return groups.values.contains { $0.count >= 2 }
    }

    // MARK: - Selection Actions

    func toggleSelection(_ id: UUID) {
        if selected.contains(id) {
            selected.remove(id)
        } else {
            selected.insert(id)
        }
    }

    func clearSelection() {
        selected.removeAll()
    }

    // MARK: - Consolidation

    func consolidateSelected(
        orderedUnscheduledLessons: [StudentLesson],
        studentLessons: [StudentLesson],
        inboxOrderRaw: Binding<String>,
        modelContext: ModelContext,
        appRouter: AppRouter,
        saveCoordinator: SaveCoordinator
    ) {
        let selectedSLs = orderedUnscheduledLessons.filter { selected.contains($0.id) }
        guard !selectedSLs.isEmpty else { return }

        let groups = selectedSLs.grouped(by: { $0.resolvedLessonID })
        var consolidatedGroups = 0
        var deletedIDs: [UUID] = []
        let currentOrder = orderedUnscheduledLessons.map(\.id)

        for (_, group) in groups {
            guard group.count >= 2 else { continue }
            consolidatedGroups += 1

            let groupIDs = group.map(\.id)
            guard let targetID = currentOrder.first(where: { groupIDs.contains($0) }),
                  let target = studentLessons.first(where: { $0.id == targetID }) else { continue }

            var union = Set<UUID>(target.resolvedStudentIDs)
            for sl in group { union.formUnion(sl.resolvedStudentIDs) }
            let remainingIDs = Array(union)

            if remainingIDs.isEmpty {
                deletedIDs.append(targetID)
                modelContext.delete(target)
            } else {
                target.studentIDs = remainingIDs.map { $0.uuidString }
                // NOTE: SwiftData #Predicate doesn't support capturing local Array/Set variables,
                // so we fetch all and filter in memory
                let remainingSet = Set(remainingIDs)
                let allStudents = (try? modelContext.fetch(FetchDescriptor<Student>())) ?? []
                let fetched = allStudents.filter { remainingSet.contains($0.id) }
                target.students = fetched
            }

            for sl in group where sl.id != targetID {
                deletedIDs.append(sl.id)
                modelContext.delete(sl)
            }
        }

        saveCoordinator.save(modelContext, reason: "Consolidating lessons")

        var newOrder = currentOrder
        for id in deletedIDs { newOrder.removeAll { $0 == id } }
        let serialized = InboxOrderStore.serialize(newOrder)
        inboxOrderRaw.wrappedValue = serialized
        onUpdateOrder?(serialized)

        let msg = consolidatedGroups == 1 ? "Consolidated 1 lesson" : "Consolidated \(consolidatedGroups) lessons"
        showToast(msg)

        selected.removeAll()
        appRouter.refreshPlanningInbox()
    }

    // MARK: - Toast

    func showToast(_ message: String) {
        // Delegate to centralized ToastService
        ToastService.shared.showInfo(message)
    }

    // MARK: - Drop Handling

    func handleDrop(
        providers: [NSItemProvider],
        location: CGPoint,
        studentLessons: [StudentLesson],
        orderedUnscheduledLessons: [StudentLesson],
        itemFrames: [UUID: CGRect],
        inboxOrderRaw: Binding<String>,
        modelContext: ModelContext,
        saveCoordinator: SaveCoordinator
    ) -> Bool {
        guard let itemProvider = providers.first else { return false }
        if itemProvider.canLoadObject(ofClass: NSString.self) {
            // These captures are safe because:
            // 1. The outer loadObject callback runs on an arbitrary queue but only extracts the string
            // 2. The inner Task is @MainActor isolated, ensuring all SwiftData access happens on main
            // 3. The captured arrays are read-only snapshots from the caller's @MainActor context
            // Using nonisolated(unsafe) to silence warnings while maintaining the safe pattern.
            nonisolated(unsafe) let studentLessonsRef = studentLessons
            nonisolated(unsafe) let orderedUnscheduledLessonsRef = orderedUnscheduledLessons
            nonisolated(unsafe) let modelContextRef = modelContext

            _ = itemProvider.loadObject(ofClass: NSString.self) { [weak self] reading, _ in
                guard let ns = reading as? NSString else { return }
                let raw = ns as String
                Task { @MainActor [weak self] in
                    if raw.hasPrefix("STUDENT_TO_INBOX:") {
                        self?.handleStudentToInboxDrop(
                            payload: raw,
                            location: location,
                            studentLessons: studentLessonsRef,
                            orderedUnscheduledLessons: orderedUnscheduledLessonsRef,
                            itemFrames: itemFrames,
                            inboxOrderRaw: inboxOrderRaw,
                            modelContext: modelContextRef,
                            saveCoordinator: saveCoordinator
                        )
                    } else if let droppedId = UUID(uuidString: raw.trimmed()) {
                        self?.handleLessonDrop(
                            droppedId: droppedId,
                            location: location,
                            studentLessons: studentLessonsRef,
                            orderedUnscheduledLessons: orderedUnscheduledLessonsRef,
                            itemFrames: itemFrames,
                            inboxOrderRaw: inboxOrderRaw,
                            modelContext: modelContextRef,
                            saveCoordinator: saveCoordinator
                        )
                    }
                }
            }
            return true
        }
        return false
    }

    private func handleStudentToInboxDrop(
        payload: String,
        location: CGPoint,
        studentLessons: [StudentLesson],
        orderedUnscheduledLessons: [StudentLesson],
        itemFrames: [UUID: CGRect],
        inboxOrderRaw: Binding<String>,
        modelContext: ModelContext,
        saveCoordinator: SaveCoordinator
    ) {
        let parts = payload.split(separator: ":")
        guard parts.count == 4,
              parts[0] == "STUDENT_TO_INBOX",
              let sourceID = UUID(uuidString: String(parts[1])),
              let lessonID = UUID(uuidString: String(parts[2])),
              let studentID = UUID(uuidString: String(parts[3])) else { return }

        // Find or create an unscheduled single-student StudentLesson
        let targetSL: StudentLesson = {
            let matchesLesson = { (sl: StudentLesson) in sl.resolvedLessonID == lessonID }
            let isUnscheduled = { (sl: StudentLesson) in sl.scheduledFor == nil && !sl.isGiven }
            let matchesStudent = { (sl: StudentLesson) in Set(sl.resolvedStudentIDs) == Set([studentID]) }

            if let existing = studentLessons.first(where: { sl in
                matchesLesson(sl) && isUnscheduled(sl) && matchesStudent(sl)
            }) {
                return existing
            }

            var lessonFetch = FetchDescriptor<Lesson>(predicate: #Predicate { $0.id == lessonID })
            lessonFetch.fetchLimit = 1
            var studentFetch = FetchDescriptor<Student>(predicate: #Predicate { $0.id == studentID })
            studentFetch.fetchLimit = 1
            let lessonObj = (try? modelContext.fetch(lessonFetch))?.first
            let studentObj = (try? modelContext.fetch(studentFetch))?.first

            let new = StudentLessonFactory.makeUnscheduled(lessonID: lessonID, studentIDs: [studentID])
            StudentLessonFactory.attachRelationships(
                to: new,
                lesson: lessonObj,
                students: studentObj.map { [$0] } ?? []
            )
            modelContext.insert(new)
            return new
        }()

        // Remove the student from the source
        let sourceDescriptor = FetchDescriptor<StudentLesson>(predicate: #Predicate { $0.id == sourceID })
        if let src = modelContext.safeFetchFirst(sourceDescriptor) {
            let studentIDString = studentID.uuidString
            src.studentIDs.removeAll { $0 == studentIDString }
            src.students.removeAll { $0.id == studentID }
            if src.studentIDs.isEmpty {
                modelContext.delete(src)
            }
        }

        // Insert into inbox order
        let currentOrder = orderedUnscheduledLessons.map(\.id)
        var framesByID: [UUID: CGRect] = [:]
        for id in currentOrder {
            if let frame = itemFrames[id] { framesByID[id] = frame }
        }
        let insertionIndex = PlanningDropUtils.computeInsertionIndex(locationY: location.y, frames: framesByID)
        var newOrder = currentOrder
        newOrder.removeAll(where: { $0 == targetSL.id })
        let boundedIndex = max(0, min(insertionIndex, newOrder.count))
        newOrder.insert(targetSL.id, at: boundedIndex)
        let serialized = InboxOrderStore.serialize(newOrder)
        inboxOrderRaw.wrappedValue = serialized
        onUpdateOrder?(serialized)
        saveCoordinator.save(modelContext, reason: "Handling student to inbox drop")
    }

    private func handleLessonDrop(
        droppedId: UUID,
        location: CGPoint,
        studentLessons: [StudentLesson],
        orderedUnscheduledLessons: [StudentLesson],
        itemFrames: [UUID: CGRect],
        inboxOrderRaw: Binding<String>,
        modelContext: ModelContext,
        saveCoordinator: SaveCoordinator
    ) {
        let descriptor = FetchDescriptor<StudentLesson>(predicate: #Predicate { $0.id == droppedId })
        guard let sl = modelContext.safeFetchFirst(descriptor) ?? studentLessons.first(where: { $0.id == droppedId }) else { return }

        let currentOrder = orderedUnscheduledLessons.map(\.id)
        var framesByID: [UUID: CGRect] = [:]
        for id in currentOrder {
            if let frame = itemFrames[id] { framesByID[id] = frame }
        }
        let insertionIndex = PlanningDropUtils.computeInsertionIndex(locationY: location.y, frames: framesByID)
        var newOrder = currentOrder.filter { currentOrder.contains($0) }

        // If scheduled, clear scheduledFor
        if sl.scheduledFor != nil {
            let targetId = droppedId
            let slDescriptor = FetchDescriptor<StudentLesson>(predicate: #Predicate { $0.id == targetId })
            if let lesson = modelContext.safeFetchFirst(slDescriptor) {
                lesson.scheduledFor = nil
                saveCoordinator.save(modelContext, reason: "Clearing scheduled date")
            }
        }

        newOrder.removeAll(where: { $0 == droppedId })
        let boundedIndex = max(0, min(insertionIndex, newOrder.count))
        newOrder.insert(droppedId, at: boundedIndex)
        let serialized = InboxOrderStore.serialize(newOrder)
        inboxOrderRaw.wrappedValue = serialized
        onUpdateOrder?(serialized)
        saveCoordinator.save(modelContext, reason: "Handling lesson drop")
    }
}
