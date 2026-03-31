import OSLog
import SwiftUI
import CoreData

struct MarkCompletionButton: View {
    private static let logger = Logger.work
    let workID: UUID
    let studentID: UUID
    var label: String = "Mark Completed"
    var noteProvider: (() -> String)?

    @Environment(\.managedObjectContext) private var viewContext
    @State private var isWorking = false
    @State private var justCompleted = false

    var body: some View {
        Button(action: markCompleted) {
            HStack(spacing: 8) {
                if justCompleted {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(AppColors.success)
                } else if isWorking {
                    ProgressView().controlSize(.mini)
                } else {
                    Image(systemName: "checkmark.circle")
                }
                Text(label)
            }
        }
        .disabled(isWorking)
        .buttonStyle(.borderedProminent)
        .tint(.green)
    }

    private func markCompleted() {
        guard isWorking == false else { return }
        isWorking = true
        let note = noteProvider?() ?? ""
        do {
            _ = try WorkCompletionService.markCompleted(
                workID: workID, studentID: studentID, note: note, in: viewContext
            )
            #if canImport(UIKit)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            #endif
            adaptiveWithAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                justCompleted = true
            }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1.5))
                adaptiveWithAnimation(.easeOut) { justCompleted = false }
            }
        } catch {
            Self.logger.error("[\(#function)] Failed to mark work completed: \(error)")
            #if canImport(UIKit)
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            #endif
        }
        isWorking = false
    }
}

#Preview {
    MarkCompletionButton(workID: UUID(), studentID: UUID())
        .padding()
        .previewEnvironment()
}
