import SwiftUI

/// Settings › Classroom: last year's records still in the classroom share, and the way to
/// take them out (`ClassroomShareRelease`). Shown to the lead guide once the new school year
/// has begun and something from before it is still shared. The button is the Mac's; on an
/// iPhone or iPad the card only says so.
struct ClassroomLastYearCard: View {
    let contents: ClassroomShareContents?
    let onFinished: () async -> Void

    @State private var showingRelease = false

    private var waiting: Int { (contents?.toRelease ?? 0) + (contents?.mixedDuplicates ?? 0) }
    private var stoppedEarlier: Bool { ClassroomShareRelease.stoppedPartway }

    var body: some View {
        if waiting > 0 || stoppedEarlier {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
                ClassroomShareBanner(
                    icon: "calendar.badge.minus",
                    tint: AppColors.warning,
                    title: title,
                    message: "Children who left in an earlier school year, and marks from before this one. "
                        + "They stay in your notebook; taking them out of the share takes them off your "
                        + "assistants' iPhones."
                )
                if ClassroomShareRelease.isAvailableHere {
                    Button {
                        showingRelease = true
                    } label: {
                        Label(
                            stoppedEarlier ? "Finish Removing Last Year…" : "Remove Last Year from the Share…",
                            systemImage: "calendar.badge.minus"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .sheet(isPresented: $showingRelease) {
                        ClassroomReleaseSheet {
                            await onFinished()
                        }
                    }
                } else {
                    Text("Remove them on your Mac, in Settings › Classroom.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var title: String {
        if waiting == 0 { return "Removing last year was stopped partway" }
        return waiting == 1
            ? "1 record from before this school year is still shared"
            : "\(waiting.formatted()) records from before this school year are still shared"
    }
}
