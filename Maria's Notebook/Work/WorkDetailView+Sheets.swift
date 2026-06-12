import SwiftUI
import CoreData
import Foundation

// MARK: - Helpers

private struct NextLessonResolver {
    static func resolveNextLesson(from currentID: UUID, lessons: [CDLesson]) -> CDLesson? {
        guard let current = lessons.first(where: { $0.id == currentID }) else { return nil }
        let candidates = lessons.filter { $0.area == current.area && $0.sequence == current.sequence }
            .sorted { $0.orderInSequence < $1.orderInSequence }
        if let idx = candidates.firstIndex(where: { $0.id == current.id }), idx + 1 < candidates.count {
            return candidates[idx + 1]
        }
        return nil
    }
}

struct WorkModelScheduleNextLessonSheet: View {
    let work: CDWorkModel
    var onCreated: () -> Void
    @Environment(\.dismiss) var dismiss
    var body: some View {
        Button("Tap to Unlock") { onCreated(); dismiss() }.padding()
    }
}
