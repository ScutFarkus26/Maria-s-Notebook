import SwiftUI
import CoreData

/// Helper to identify and facilitate sequence practice opportunities
struct SequencePracticeHelper {
    let modelContext: NSManagedObjectContext

    /// Finds students who have work from the same lesson
    func findSequencePracticeOpportunities(for work: CDWorkModel, in allWork: [CDWorkModel]) -> [CDWorkModel] {
        guard !work.lessonID.isEmpty else { return [] }

        return allWork.filter { otherWork in
            otherWork.id != work.id &&
            otherWork.lessonID == work.lessonID &&
            otherWork.status != .complete &&
            !otherWork.studentID.isEmpty
        }
    }

    /// Checks if there are practice partners available for this work
    func hasSequencePracticeOpportunity(for work: CDWorkModel, in allWork: [CDWorkModel]) -> Bool {
        !findSequencePracticeOpportunities(for: work, in: allWork).isEmpty
    }
}

/// Badge indicator for sequence practice availability
struct SequencePracticeBadge: View {
    let partnerCount: Int
    var action: (() -> Void)?

    var body: some View {
        Button(action: { action?() }, label: {
            HStack(spacing: 4) {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 10, weight: .semibold))
                Text("+\(partnerCount)")
                    .font(AppTheme.ScaledFont.captionSemibold)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(Color.blue)
            )
        })
        .buttonStyle(.plain)
        .help("Start sequence practice with \(partnerCount) partner\(partnerCount == 1 ? "" : "s")")
    }
}

/// Extension to WorkCard to add sequence practice indicators
extension View {
    /// Adds a sequence practice badge overlay if partners are available
    func groupPracticeBadge(
        for work: CDWorkModel,
        in allWork: [CDWorkModel],
        context: NSManagedObjectContext,
        action: @escaping () -> Void
    ) -> some View {
        let helper = SequencePracticeHelper(modelContext: context)
        let partners = helper.findSequencePracticeOpportunities(for: work, in: allWork)

        return self.overlay(alignment: .topTrailing) {
            if !partners.isEmpty {
                SequencePracticeBadge(partnerCount: partners.count, action: action)
                    .padding(8)
            }
        }
    }
}

// MARK: - Preview

#Preview("Group Practice Badge") {
    VStack(spacing: 20) {
        SequencePracticeBadge(partnerCount: 2)

        SequencePracticeBadge(partnerCount: 1)

        SequencePracticeBadge(partnerCount: 5)
    }
    .padding()
}
