import SwiftUI
import CoreData
import OSLog

struct PresentationDraftSheet: View {
    private static let logger = Logger.students
    @Environment(\.managedObjectContext) private var viewContext

    // Filtered query to observe the draft by its ID
    @FetchRequest(sortDescriptors: []) private var matches: FetchedResults<CDLessonAssignment>

    let id: UUID
    let onDone: () -> Void

    init(id: UUID, onDone: @escaping () -> Void) {
        self.id = id
        self.onDone = onDone
        _matches = FetchRequest(sortDescriptors: [], predicate: NSPredicate(format: "id == %@", id as CVarArg))
    }

    var body: some View {
        Group {
            if let sl = matches.first {
                PresentationDetailView(lessonAssignment: sl, onDone: onDone, autoFocusLessonPicker: true)
                    .onDisappear {
                        // If the draft is still empty when the sheet closes, remove it
                        if let current = matches.first {
                            if current.lesson == nil && current.studentIDs.isEmpty {
                                viewContext.delete(current)
                                do {
                                    try viewContext.save()
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
