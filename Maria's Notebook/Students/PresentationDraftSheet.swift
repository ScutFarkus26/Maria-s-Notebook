import SwiftUI
import SwiftData
import OSLog

struct PresentationDraftSheet: View {
    private static let logger = Logger.students
    @Environment(\.modelContext) private var modelContext

    // Filtered query to observe the draft by its ID
    @Query private var matches: [LessonAssignment]

    let id: UUID
    let onDone: () -> Void

    init(id: UUID, onDone: @escaping () -> Void) {
        self.id = id
        self.onDone = onDone
        _matches = Query(filter: #Predicate<LessonAssignment> { $0.id == id })
    }

    var body: some View {
        Group {
            if let sl = matches.first {
                PresentationDetailView(lessonAssignment: sl, onDone: onDone, autoFocusLessonPicker: true)
                    .onDisappear {
                        // If the draft is still empty when the sheet closes, remove it
                        if let current = matches.first {
                            if current.lesson == nil && current.studentIDs.isEmpty {
                                modelContext.delete(current)
                                do {
                                    try modelContext.save()
                                } catch {
                                    Self.logger.warning("Failed to save: \(error)")
                                }
                            }
                        }
                    }
            } else {
                // Keep the sheet alive instead of returning EmptyView to avoid ViewBridge cancellation
                ProgressView("Preparing…")
                    .frame(minWidth: 320, minHeight: 240)
            }
        }
    }
}
