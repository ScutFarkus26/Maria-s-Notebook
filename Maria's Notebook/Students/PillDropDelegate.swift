import OSLog
import SwiftUI
import SwiftData
import UniformTypeIdentifiers

private let logger = Logger.students

struct PillDropDelegate: DropDelegate {
    let modelContext: ModelContext
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
                    var srcDesc = FetchDescriptor<LessonAssignment>(predicate: #Predicate { $0.id == sourceID })
                    srcDesc.fetchLimit = 1
                    var tgtDesc = FetchDescriptor<LessonAssignment>(predicate: #Predicate { $0.id == targetID })
                    tgtDesc.fetchLimit = 1
                    let src: LessonAssignment?
                    let tgt: LessonAssignment?
                    do {
                        src = try modelContext.fetch(srcDesc).first
                        tgt = try modelContext.fetch(tgtDesc).first
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
                        if !target.students.contains(where: { $0.id == studentID }) {
                            var stuDesc = FetchDescriptor<Student>(predicate: #Predicate { $0.id == studentID })
                            stuDesc.fetchLimit = 1
                            do {
                                if let s = try modelContext.fetch(stuDesc).first {
                                    target.students.append(s)
                                } else if let s2 = source.students.first(where: { $0.id == studentID }) {
                                    target.students.append(s2)
                                }
                            } catch {
                                logger.warning("Failed to fetch Student on drop: \(error)")
                                if let s2 = source.students.first(where: { $0.id == studentID }) {
                                    target.students.append(s2)
                                }
                            }
                        }

                    }
                    source.studentIDs.removeAll { $0 == studentIDString }
                    if source.studentIDs.isEmpty {
                        modelContext.delete(source)
                    } else {
                        let remainingIDs = source.studentIDs.compactMap { UUID(uuidString: $0) }
                        // NOTE: SwiftData #Predicate doesn't support capturing local Array/Set variables,
                        // so we fetch all and filter in memory
                        let remainingSet = Set(remainingIDs)
                        let allStudents: [Student]
                        do {
                            allStudents = try modelContext.fetch(FetchDescriptor<Student>())
                        } catch {
                            logger.warning("Failed to fetch all Students on drop: \(error)")
                            allStudents = []
                        }
                        let fetched = allStudents.filter { remainingSet.contains($0.id) }
                        source.students = fetched

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
                        context: modelContext
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
                    var srcDesc = FetchDescriptor<LessonAssignment>(predicate: #Predicate { $0.id == sourceID })
                    srcDesc.fetchLimit = 1
                    let source: LessonAssignment?
                    do {
                        source = try modelContext.fetch(srcDesc).first
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
