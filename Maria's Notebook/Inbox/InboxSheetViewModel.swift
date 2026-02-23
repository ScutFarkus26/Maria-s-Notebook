// InboxSheetViewModel.swift
// ViewModel for InboxSheetView - handles consolidation and drop logic

import SwiftUI
import SwiftData

@Observable
@MainActor
final class InboxSheetViewModel {
    // MARK: - State
    var selected: Set<UUID> = []
    var toastMessage: String? = nil

    // MARK: - Dependencies
    private let toastService: ToastService
    
    // MARK: - Callbacks
    var onUpdateOrder: ((String) -> Void)?
    
    // MARK: - Initialization
    
    init(toastService: ToastService = ToastService.shared) {
        self.toastService = toastService
    }

    // MARK: - Computed Properties

    var isSelectionMode: Bool {
        !selected.isEmpty
    }

    func canConsolidate(orderedUnscheduledLessons: [LessonAssignment]) -> Bool {
        let selectedLAs = orderedUnscheduledLessons.filter { selected.contains($0.id) }
        let groups = selectedLAs.grouped(by: { $0.lessonID })
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
        orderedUnscheduledLessons: [LessonAssignment],
        lessonAssignments: [LessonAssignment],
        inboxOrderRaw: Binding<String>,
        modelContext: ModelContext,
        appRouter: AppRouter,
        saveCoordinator: SaveCoordinator
    ) {
        let selectedLAs = orderedUnscheduledLessons.filter { selected.contains($0.id) }
        guard !selectedLAs.isEmpty else { return }

        let groups = selectedLAs.grouped(by: { $0.lessonIDUUID })
        var consolidatedGroups = 0
        var deletedIDs: [UUID] = []
        let currentOrder = orderedUnscheduledLessons.map(\.id)

        for (_, group) in groups {
            guard group.count >= 2 else { continue }
            consolidatedGroups += 1

            let groupIDs = group.map(\.id)
            guard let targetID = currentOrder.first(where: { groupIDs.contains($0) }),
                  let target = lessonAssignments.first(where: { $0.id == targetID }) else { continue }

            var union = Set<UUID>(target.studentUUIDs)
            for la in group { union.formUnion(la.studentUUIDs) }
            let remainingIDs = Array(union)

            if remainingIDs.isEmpty {
                deletedIDs.append(targetID)
                modelContext.delete(target)
            } else {
                target.studentIDs = remainingIDs.map { $0.uuidString }
                // NOTE: SwiftData #Predicate doesn't support capturing local Array/Set variables,
                // so we fetch all and filter in memory
                let remainingSet = Set(remainingIDs)
                let allStudents = safeFetch(FetchDescriptor<Student>(), modelContext: modelContext, context: "consolidateSelected")
                let fetched = allStudents.filter { remainingSet.contains($0.id) }
                target.students = fetched
            }

            for la in group where la.id != targetID {
                deletedIDs.append(la.id)
                modelContext.delete(la)
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
        toastService.showInfo(message)
    }

    // MARK: - Drop Handling

    func handleDrop(
        providers: [NSItemProvider],
        location: CGPoint,
        lessonAssignments: [LessonAssignment],
        orderedUnscheduledLessons: [LessonAssignment],
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
            nonisolated(unsafe) let lessonAssignmentsRef = lessonAssignments
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
                            lessonAssignments: lessonAssignmentsRef,
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
                            lessonAssignments: lessonAssignmentsRef,
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
        lessonAssignments: [LessonAssignment],
        orderedUnscheduledLessons: [LessonAssignment],
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

        // Find or create an unscheduled single-student LessonAssignment
        let targetLA: LessonAssignment = {
            let matchesLesson = { (la: LessonAssignment) in la.lessonIDUUID == lessonID }
            let isUnscheduled = { (la: LessonAssignment) in la.scheduledFor == nil && !la.isGiven }
            let matchesStudent = { (la: LessonAssignment) in Set(la.studentUUIDs) == Set([studentID]) }

            if let existing = lessonAssignments.first(where: { la in
                matchesLesson(la) && isUnscheduled(la) && matchesStudent(la)
            }) {
                return existing
            }

            var lessonFetch = FetchDescriptor<Lesson>(predicate: #Predicate { $0.id == lessonID })
            lessonFetch.fetchLimit = 1
            var studentFetch = FetchDescriptor<Student>(predicate: #Predicate { $0.id == studentID })
            studentFetch.fetchLimit = 1
            let lessonObj = safeFetchFirst(lessonFetch, modelContext: modelContext, context: "handleStudentToInboxDrop-lesson")
            let studentObj = safeFetchFirst(studentFetch, modelContext: modelContext, context: "handleStudentToInboxDrop-student")

            let new = PresentationFactory.makeDraft(lessonID: lessonID, studentIDs: [studentID])
            PresentationFactory.attachRelationships(
                to: new,
                lesson: lessonObj,
                students: studentObj.map { [$0] } ?? []
            )
            modelContext.insert(new)
            return new
        }()

        // Remove the student from the source
        let sourceDescriptor = FetchDescriptor<LessonAssignment>(predicate: #Predicate { $0.id == sourceID })
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
        newOrder.removeAll(where: { $0 == targetLA.id })
        let boundedIndex = max(0, min(insertionIndex, newOrder.count))
        newOrder.insert(targetLA.id, at: boundedIndex)
        let serialized = InboxOrderStore.serialize(newOrder)
        inboxOrderRaw.wrappedValue = serialized
        onUpdateOrder?(serialized)
        saveCoordinator.save(modelContext, reason: "Handling student to inbox drop")
    }

    private func handleLessonDrop(
        droppedId: UUID,
        location: CGPoint,
        lessonAssignments: [LessonAssignment],
        orderedUnscheduledLessons: [LessonAssignment],
        itemFrames: [UUID: CGRect],
        inboxOrderRaw: Binding<String>,
        modelContext: ModelContext,
        saveCoordinator: SaveCoordinator
    ) {
        let descriptor = FetchDescriptor<LessonAssignment>(predicate: #Predicate { $0.id == droppedId })
        guard let la = modelContext.safeFetchFirst(descriptor) ?? lessonAssignments.first(where: { $0.id == droppedId }) else { return }

        let currentOrder = orderedUnscheduledLessons.map(\.id)
        var framesByID: [UUID: CGRect] = [:]
        for id in currentOrder {
            if let frame = itemFrames[id] { framesByID[id] = frame }
        }
        let insertionIndex = PlanningDropUtils.computeInsertionIndex(locationY: location.y, frames: framesByID)
        var newOrder = currentOrder.filter { currentOrder.contains($0) }

        // If scheduled, clear scheduledFor
        if la.scheduledFor != nil {
            let targetId = droppedId
            let laDescriptor = FetchDescriptor<LessonAssignment>(predicate: #Predicate { $0.id == targetId })
            if let lesson = modelContext.safeFetchFirst(laDescriptor) {
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

    // MARK: - Error Handling Helpers

    private func safeFetch<T>(_ descriptor: FetchDescriptor<T>, modelContext: ModelContext, context: String = #function) -> [T] {
        do {
            return try modelContext.fetch(descriptor)
        } catch {
            print("⚠️ [\(context)] Failed to fetch \(T.self): \(error)")
            return []
        }
    }

    private func safeFetchFirst<T>(_ descriptor: FetchDescriptor<T>, modelContext: ModelContext, context: String = #function) -> T? {
        do {
            return try modelContext.fetch(descriptor).first
        } catch {
            print("⚠️ [\(context)] Failed to fetch \(T.self): \(error)")
            return nil
        }
    }
}
