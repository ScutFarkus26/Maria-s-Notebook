import OSLog
import SwiftUI
import CoreData
import UniformTypeIdentifiers

private let logger = Logger.students

struct PillDropDelegate: DropDelegate {
    let viewContext: NSManagedObjectContext
    let appRouter: AppRouter
    let targetLessonID: UUID
    let targetLessonAssignmentID: UUID?
    let enableMergeDrop: Bool
    let setHighlight: (Bool) -> Void
    let setMergeHighlight: (Bool) -> Void
    let canAccept: () -> Bool
    let onDidMutate: (String) -> Void

    func dropEntered(info: DropInfo) { checkHighlight(info: info) }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        checkHighlight(info: info)
        return canAccept() ? DropProposal(operation: .copy) : DropProposal(operation: .cancel)
    }

    func dropExited(info: DropInfo) {
        setHighlight(false)
        setMergeHighlight(false)
    }

    func validateDrop(info: DropInfo) -> Bool { info.hasItemsConforming(to: [UTType.text]) }

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    func performDrop(info: DropInfo) -> Bool {
        setHighlight(false)
        setMergeHighlight(false)
        guard canAccept() else { return false }
        guard let targetID = targetLessonAssignmentID else { return false }
        let providers = info.itemProviders(for: [UTType.text])
        guard let provider = providers.first else { return false }
        provider.loadObject(ofClass: NSString.self) { reading, _ in
            guard let ns = reading as? NSString else { return }
            let str = ns as String
            if let decoded = DragPayload.decode(str) {
                Task { @MainActor in
                    let sourceID = decoded.sourceID
                    let lessonID = decoded.lessonID
                    let studentID = decoded.studentID
                    let srcDesc = { let r = NSFetchRequest<CDLessonAssignment>(entityName: "LessonAssignment"); r.predicate = NSPredicate(format: "id == %@", sourceID as CVarArg); r.fetchLimit = 1; return r }()
                    let tgtDesc = { let r = NSFetchRequest<CDLessonAssignment>(entityName: "LessonAssignment"); r.predicate = NSPredicate(format: "id == %@", targetID as CVarArg); r.fetchLimit = 1; return r }()
                    let src: CDLessonAssignment?
                    let tgt: CDLessonAssignment?
                    do {
                        src = try viewContext.fetch(srcDesc).first
                        tgt = try viewContext.fetch(tgtDesc).first
                    } catch {
                        logger.warning("Failed to fetch LessonAssignments on drop: \(error)")
                        return
                    }
                    guard let source = src, let target = tgt,
                          source.id != target.id,
                          lessonID == targetLessonID else { return }
                    let studentIDString = studentID.uuidString
                    if !target.studentIDs.contains(studentIDString) {
                        target.studentIDs.append(studentIDString)
                    }
                    source.studentIDs.removeAll { $0 == studentIDString }
                    if source.studentIDs.isEmpty {
                        viewContext.delete(source)
                    }
                    onDidMutate("Move student between lessons")
                    appRouter.refreshPlanningInbox()
                }
                return
            }

            if enableMergeDrop, let sourceID = UUID(uuidString: str.trimmed()) {
                Task { @MainActor in
                    _ = PresentationMergeService.merge(
                        sourceID: sourceID,
                        targetID: targetID,
                        context: viewContext
                    )
                }
            }
        }
        return true
    }

    private func checkHighlight(info: DropInfo) {
        guard let targetID = targetLessonAssignmentID else { setHighlight(false); return }
        let providers = info.itemProviders(for: [UTType.text])
        guard let provider = providers.first else { setHighlight(false); return }
        provider.loadObject(ofClass: NSString.self) { reading, _ in
            guard let ns = reading as? NSString else { Task { @MainActor in setHighlight(false) }; return }
            let str = ns as String
            if let decoded = DragPayload.decode(str) {
                let sourceID = decoded.sourceID
                let lessonID = decoded.lessonID
                Task { @MainActor in
                    if lessonID == targetLessonID, sourceID != targetID {
                        setHighlight(true)
                        setMergeHighlight(false)
                    } else {
                        setHighlight(false)
                        setMergeHighlight(false)
                    }
                }
            } else if enableMergeDrop, let sourceID = UUID(uuidString: str.trimmed()) {
                Task { @MainActor in
                    guard sourceID != targetID else {
                        setHighlight(false)
                        setMergeHighlight(false)
                        return
                    }
                    let srcDesc = { let r = NSFetchRequest<CDLessonAssignment>(entityName: "LessonAssignment"); r.predicate = NSPredicate(format: "id == %@", sourceID as CVarArg); r.fetchLimit = 1; return r }()
                    let source: CDLessonAssignment?
                    do {
                        source = try viewContext.fetch(srcDesc).first
                    } catch {
                        logger.warning("Failed to fetch source for merge drop: \(error)")
                        source = nil
                    }
                    if let source, source.resolvedLessonID == targetLessonID, !source.isGiven {
                        setHighlight(false)
                        setMergeHighlight(true)
                    } else {
                        setHighlight(false)
                        setMergeHighlight(false)
                    }
                }
            } else {
                Task { @MainActor in
                    setHighlight(false)
                    setMergeHighlight(false)
                }
            }
        }
    }
}
