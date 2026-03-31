// InboxSheetViewModel.swift
// ViewModel for InboxSheetView - handles consolidation and drop logic

import SwiftUI
import CoreData
import OSLog

@Observable
@MainActor
final class InboxSheetViewModel {
    private static let logger = Logger.inbox
    // MARK: - State
    var selected: Set<UUID> = []
    var toastMessage: String?

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

    func canConsolidate(orderedUnscheduledLessons: [CDLessonAssignment]) -> Bool {
        let selectedLAs = orderedUnscheduledLessons.filter { la in
            guard let id = la.id else { return false }
            return selected.contains(id)
        }
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

    // swiftlint:disable:next function_parameter_count
    func consolidateSelected(
        orderedUnscheduledLessons: [CDLessonAssignment],
        lessonAssignments: [CDLessonAssignment],
        inboxOrderRaw: Binding<String>,
        viewContext: NSManagedObjectContext,
        appRouter: AppRouter,
        saveCoordinator: SaveCoordinator
    ) {
        let selectedLAs = orderedUnscheduledLessons.filter { la in
            guard let id = la.id else { return false }
            return selected.contains(id)
        }
        guard !selectedLAs.isEmpty else { return }

        let groups = selectedLAs.grouped(by: { $0.lessonIDUUID })
        let currentOrder = orderedUnscheduledLessons.compactMap(\.id)
        let (consolidatedGroups, deletedIDs) = applyGroupConsolidations(
            groups, currentOrder: currentOrder, lessonAssignments: lessonAssignments, viewContext: viewContext
        )

        saveCoordinator.save(viewContext, reason: "Consolidating lessons")

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

    private func applyGroupConsolidations(
        _ groups: [UUID?: [CDLessonAssignment]],
        currentOrder: [UUID],
        lessonAssignments: [CDLessonAssignment],
        viewContext: NSManagedObjectContext
    ) -> (consolidatedCount: Int, deletedIDs: [UUID]) {
        var consolidatedCount = 0
        var deletedIDs: [UUID] = []
        for (_, group) in groups {
            guard group.count >= 2 else { continue }
            consolidatedCount += 1
            let groupIDs = group.compactMap(\.id)
            guard let targetID = currentOrder.first(where: { groupIDs.contains($0) }),
                  let target = lessonAssignments.first(where: { $0.id == targetID }) else { continue }
            var union = Set<UUID>(target.studentUUIDs)
            for la in group { union.formUnion(la.studentUUIDs) }
            let remainingIDs = Array(union)
            if remainingIDs.isEmpty {
                deletedIDs.append(targetID)
                viewContext.delete(target)
            } else {
                target.studentIDs = remainingIDs.map(\.uuidString)
            }
            for la in group {
                guard let laID = la.id, laID != targetID else { continue }
                deletedIDs.append(laID)
                viewContext.delete(la)
            }
        }
        return (consolidatedCount, deletedIDs)
    }

    // MARK: - Toast

    func showToast(_ message: String) {
        // Delegate to centralized ToastService
        toastService.showInfo(message)
    }

}

// MARK: - Drop Handling

extension InboxSheetViewModel {
    // swiftlint:disable:next function_parameter_count
    func handleDrop(
        providers: [NSItemProvider],
        location: CGPoint,
        lessonAssignments: [CDLessonAssignment],
        orderedUnscheduledLessons: [CDLessonAssignment],
        itemFrames: [UUID: CGRect],
        inboxOrderRaw: Binding<String>,
        viewContext: NSManagedObjectContext,
        saveCoordinator: SaveCoordinator
    ) -> Bool {
        guard let itemProvider = providers.first else { return false }
        if itemProvider.canLoadObject(ofClass: NSString.self) {
            Task { @MainActor [weak self] in
                guard let self else { return }
                do {
                    guard let raw = try await Self.loadDropPayload(from: itemProvider) else { return }
                    if raw.hasPrefix("STUDENT_TO_INBOX:") {
                        self.handleStudentToInboxDrop(
                            payload: raw,
                            location: location,
                            lessonAssignments: lessonAssignments,
                            orderedUnscheduledLessons: orderedUnscheduledLessons,
                            itemFrames: itemFrames,
                            inboxOrderRaw: inboxOrderRaw,
                            viewContext: viewContext,
                            saveCoordinator: saveCoordinator
                        )
                    } else if let droppedId = UUID(uuidString: raw.trimmed()) {
                        self.handleLessonDrop(
                            droppedId: droppedId,
                            location: location,
                            lessonAssignments: lessonAssignments,
                            orderedUnscheduledLessons: orderedUnscheduledLessons,
                            itemFrames: itemFrames,
                            inboxOrderRaw: inboxOrderRaw,
                            viewContext: viewContext,
                            saveCoordinator: saveCoordinator
                        )
                    }
                } catch {
                    Self.logger.debug("Failed to load drop payload: \(error.localizedDescription)")
                }
            }
            return true
        }
        return false
    }

    private nonisolated static func loadDropPayload(from itemProvider: NSItemProvider) async throws -> String? {
        try await withCheckedThrowingContinuation { continuation in
            _ = itemProvider.loadObject(ofClass: NSString.self) { reading, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let ns = reading as? NSString else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: ns as String)
            }
        }
    }

    // swiftlint:disable:next function_parameter_count
    private func handleStudentToInboxDrop(
        payload: String,
        location: CGPoint,
        lessonAssignments: [CDLessonAssignment],
        orderedUnscheduledLessons: [CDLessonAssignment],
        itemFrames: [UUID: CGRect],
        inboxOrderRaw: Binding<String>,
        viewContext: NSManagedObjectContext,
        saveCoordinator: SaveCoordinator
    ) {
        let parts = payload.split(separator: ":")
        guard parts.count == 4,
              parts[0] == "STUDENT_TO_INBOX",
              let sourceID = UUID(uuidString: String(parts[1])),
              let lessonID = UUID(uuidString: String(parts[2])),
              let studentID = UUID(uuidString: String(parts[3])) else { return }

        let targetLA = findOrCreateInboxLA(
            lessonID: lessonID, studentID: studentID,
            lessonAssignments: lessonAssignments, viewContext: viewContext
        )

        // Remove the student from the source
        let sourceDescriptor = { let r = CDLessonAssignment.fetchRequest() as! NSFetchRequest<CDLessonAssignment>; r.predicate = NSPredicate(format: "id == %@", sourceID as CVarArg); return r }()
        if let src = viewContext.safeFetchFirst(sourceDescriptor) {
            let studentIDString = studentID.uuidString
            src.studentIDs.removeAll { $0 == studentIDString }
            if src.studentIDs.isEmpty { viewContext.delete(src) }
        }

        // Insert into inbox order
        let currentOrder = orderedUnscheduledLessons.compactMap(\.id)
        var framesByID: [UUID: CGRect] = [:]
        for id in currentOrder {
            if let frame = itemFrames[id] { framesByID[id] = frame }
        }
        let insertionIndex = PlanningDropUtils.computeInsertionIndex(locationY: location.y, frames: framesByID)
        var newOrder = currentOrder
        let targetLAID = targetLA.id ?? UUID()
        newOrder.removeAll(where: { $0 == targetLAID })
        let boundedIndex = max(0, min(insertionIndex, newOrder.count))
        newOrder.insert(targetLAID, at: boundedIndex)
        let serialized = InboxOrderStore.serialize(newOrder)
        inboxOrderRaw.wrappedValue = serialized
        onUpdateOrder?(serialized)
        saveCoordinator.save(viewContext, reason: "Handling student to inbox drop")
    }

    private func findOrCreateInboxLA(
        lessonID: UUID,
        studentID: UUID,
        lessonAssignments: [CDLessonAssignment],
        viewContext: NSManagedObjectContext
    ) -> CDLessonAssignment {
        let matchesLesson = { (la: CDLessonAssignment) in la.lessonIDUUID == lessonID }
        let isUnscheduled = { (la: CDLessonAssignment) in la.scheduledFor == nil && !la.isGiven }
        let matchesStudent = { (la: CDLessonAssignment) in Set(la.studentUUIDs) == Set([studentID]) }
        if let existing = lessonAssignments.first(where: { la in
            matchesLesson(la) && isUnscheduled(la) && matchesStudent(la)
        }) {
            return existing
        }
        var lessonFetch = { let r = CDLesson.fetchRequest() as! NSFetchRequest<CDLesson>; r.predicate = NSPredicate(format: "id == %@", lessonID as CVarArg); return r }()
        lessonFetch.fetchLimit = 1
        var studentFetch = { let r = CDStudent.fetchRequest() as! NSFetchRequest<CDStudent>; r.predicate = NSPredicate(format: "id == %@", studentID as CVarArg); return r }()
        studentFetch.fetchLimit = 1
        let lessonObj = safeFetchFirst(lessonFetch, viewContext: viewContext, context: "findOrCreateInboxLA-lesson")
        let studentObj = safeFetchFirst(
            studentFetch, viewContext: viewContext, context: "findOrCreateInboxLA-student"
        )
        let new = PresentationFactory.makeDraft(lessonID: lessonID, studentIDs: [studentID])
        PresentationFactory.attachRelationships(to: new, lesson: lessonObj, students: studentObj.map { [$0] } ?? [])
        viewContext.insert(new)
        return new
    }

    // swiftlint:disable:next function_parameter_count
    private func handleLessonDrop(
        droppedId: UUID,
        location: CGPoint,
        lessonAssignments: [CDLessonAssignment],
        orderedUnscheduledLessons: [CDLessonAssignment],
        itemFrames: [UUID: CGRect],
        inboxOrderRaw: Binding<String>,
        viewContext: NSManagedObjectContext,
        saveCoordinator: SaveCoordinator
    ) {
        let descriptor: NSFetchRequest<CDLessonAssignment> = {
            let r = CDLessonAssignment.fetchRequest() as! NSFetchRequest<CDLessonAssignment>
            r.predicate = NSPredicate(format: "id == %@", droppedId as CVarArg)
            return r
        }()
        guard let la = viewContext.safeFetchFirst(descriptor)
                ?? lessonAssignments.first(where: { $0.id == droppedId })
        else { return }

        let currentOrder = orderedUnscheduledLessons.compactMap(\.id)
        var framesByID: [UUID: CGRect] = [:]
        for id in currentOrder {
            if let frame = itemFrames[id] { framesByID[id] = frame }
        }
        let insertionIndex = PlanningDropUtils.computeInsertionIndex(locationY: location.y, frames: framesByID)
        var newOrder = currentOrder

        // If scheduled, clear scheduledFor
        if la.scheduledFor != nil {
            let targetId = droppedId
            let laDescriptor = { let r = CDLessonAssignment.fetchRequest() as! NSFetchRequest<CDLessonAssignment>; r.predicate = NSPredicate(format: "id == %@", targetId as CVarArg); return r }()
            if let lesson = viewContext.safeFetchFirst(laDescriptor) {
                lesson.scheduledFor = nil
                saveCoordinator.save(viewContext, reason: "Clearing scheduled date")
            }
        }

        newOrder.removeAll(where: { $0 == droppedId })
        let boundedIndex = max(0, min(insertionIndex, newOrder.count))
        newOrder.insert(droppedId, at: boundedIndex)
        let serialized = InboxOrderStore.serialize(newOrder)
        inboxOrderRaw.wrappedValue = serialized
        onUpdateOrder?(serialized)
        saveCoordinator.save(viewContext, reason: "Handling lesson drop")
    }

    // MARK: - Error Handling Helpers

    private func safeFetch<T>(
        _ descriptor: NSFetchRequest<T>,
        viewContext: NSManagedObjectContext,
        context: String = #function
    ) -> [T] {
        do {
            return try viewContext.fetch(descriptor)
        } catch {
            Self.logger.warning("Failed to fetch \(T.self, privacy: .public) in \(context, privacy: .public): \(error)")
            return []
        }
    }

    private func safeFetchFirst<T>(
        _ descriptor: NSFetchRequest<T>,
        viewContext: NSManagedObjectContext,
        context: String = #function
    ) -> T? {
        do {
            return try viewContext.fetch(descriptor).first
        } catch {
            Self.logger.warning("Failed to fetch \(T.self, privacy: .public) in \(context, privacy: .public): \(error)")
            return nil
        }
    }
}
