import SwiftUI
import CoreData
import UniformTypeIdentifiers

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
    var onMergeReceived: () -> Void = {}
    var onSourceEmptied: () -> Void = {}

    func dropEntered(info: DropInfo) { checkHighlight(info: info) }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        checkHighlight(info: info)
        return DropProposal(operation: .copy)
    }

    func dropExited(info: DropInfo) {
        setHighlight(false)
        setMergeHighlight(false)
    }

    func validateDrop(info: DropInfo) -> Bool { info.hasItemsConforming(to: [UTType.text]) }

    func performDrop(info: DropInfo) -> Bool {
        setHighlight(false)
        setMergeHighlight(false)
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
                    guard let source = viewContext.object(CDLessonAssignment.self, id: sourceID),
                          let target = viewContext.object(CDLessonAssignment.self, id: targetID),
                          source.id != target.id,
                          lessonID == targetLessonID else { return }
                    let studentIDString = studentID.uuidString
                    if !target.studentIDs.contains(studentIDString) {
                        target.studentIDs.append(studentIDString)
                    }
                    source.studentIDs.removeAll { $0 == studentIDString }
                    let sourceEmptied = source.studentIDs.isEmpty
                    if sourceEmptied {
                        viewContext.delete(source)
                    }
                    onDidMutate("Move student between lessons")
                    if sourceEmptied {
                        onSourceEmptied()
                    }
                    appRouter.refreshPlanningInbox()
                }
                return
            }

            if enableMergeDrop,
               let payload = UnifiedCalendarDragPayload.parse(str),
               case .presentation(let sourceID) = payload {
                Task { @MainActor in
                    if PresentationMergeService.merge(
                        sourceID: sourceID,
                        targetID: targetID,
                        context: viewContext
                    ) {
                        onMergeReceived()
                    }
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
            } else if enableMergeDrop,
                      let payload = UnifiedCalendarDragPayload.parse(str),
                      case .presentation(let sourceID) = payload {
                Task { @MainActor in
                    guard sourceID != targetID else {
                        setHighlight(false)
                        setMergeHighlight(false)
                        return
                    }
                    let source = viewContext.object(CDLessonAssignment.self, id: sourceID)
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
