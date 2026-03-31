import SwiftUI
import CoreData
import Foundation

// MARK: - Sheet Presentation Extension

extension View {
    /// Present work detail as a sheet with platform-adaptive sizing
    func workDetailSheet(workID: Binding<UUID?>, onDone: (() -> Void)? = nil) -> some View {
        self.sheet(isPresented: Binding(
            get: { workID.wrappedValue != nil },
            set: { if !$0 { workID.wrappedValue = nil } }
        )) {
            if let id = workID.wrappedValue {
                WorkDetailView(workID: id, onDone: {
                    workID.wrappedValue = nil
                    onDone?()
                })
                #if os(macOS)
                .frame(minWidth: 720, minHeight: 640)
                .presentationSizingFitted()
                #else
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                #endif
            }
        }
    }
}

// MARK: - Helpers

private struct NextLessonResolver {
    static func resolveNextLesson(from currentID: UUID, lessons: [Lesson]) -> Lesson? {
        guard let current = lessons.first(where: { $0.id == currentID }) else { return nil }
        let candidates = lessons.filter { $0.subject == current.subject && $0.group == current.group }
            .sorted { $0.orderInGroup < $1.orderInGroup }
        if let idx = candidates.firstIndex(where: { $0.id == current.id }), idx + 1 < candidates.count {
            return candidates[idx + 1]
        }
        return nil
    }
}

struct WorkModelScheduleNextLessonSheet: View {
    let work: WorkModel
    var onCreated: () -> Void
    @Environment(\.dismiss) var dismiss
    var body: some View {
        Button("Tap to Unlock") { onCreated(); dismiss() }.padding()
    }
}
