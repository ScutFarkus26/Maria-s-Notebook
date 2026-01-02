import SwiftUI
import SwiftData

struct MarkCompletionButton: View {
    let workID: UUID
    let studentID: UUID
    var label: String = "Mark Completed"
    var noteProvider: (() -> String)? = nil

    @Environment(\.modelContext) private var modelContext
    @State private var isWorking = false
    @State private var justCompleted = false

    var body: some View {
        Button(action: markCompleted) {
            HStack(spacing: 8) {
                if justCompleted {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
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
            _ = try WorkCompletionService.markCompleted(workID: workID, studentID: studentID, note: note, in: modelContext)
            #if canImport(UIKit)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            #endif
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                justCompleted = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                withAnimation(.easeOut) { justCompleted = false }
            }
        } catch {
            #if canImport(UIKit)
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            #endif
        }
        isWorking = false
    }
}

#Preview {
    struct PreviewHost: View {
        @State private var workID = UUID()
        @State private var studentID = UUID()
        var body: some View {
            MarkCompletionButton(workID: workID, studentID: studentID)
        }
    }

    return PreviewContainer(PreviewHost())
}

private struct PreviewContainer<Content: View>: View {
    private let content: Content
    init(_ content: Content) { self.content = content }

    var body: some View {
        content
            .padding()
            .modelContainer(ModelContainer.previewContainer(for: Schema([WorkCompletionRecord.self])))
    }
}
