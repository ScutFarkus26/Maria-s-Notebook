import SwiftUI

/// Settings › Classroom: last year's records still in the classroom share, and the way to
/// take them out (`ClassroomShareRelease`). Shown to the lead guide once the new school year
/// has begun and something from before it is still shared. The button is the Mac's; on an
/// iPhone or iPad the card only says so.
struct ClassroomLastYearCard: View {
    let contents: ClassroomShareContents?
    let onFinished: () async -> Void

    @State private var showingRelease = false

    /// Each record counted once. A record a stopped run left on both sides (`mixedDuplicates`)
    /// is already counted by its shared original (`toRelease`), and one whose shared copy
    /// belongs this year is nothing the release would take out.
    private var waiting: Int { contents?.toRelease ?? 0 }
    /// Records a stopped run left on both sides. Those whose shared copy belongs this year
    /// (the child came back) aren't in `waiting`, and nothing else would say they're there:
    /// shown until the release has put them back to one copy (bug hunt 2026-11-02, #38).
    private var heldTwice: Int { contents?.mixedDuplicates ?? 0 }
    private var stoppedEarlier: Bool { ClassroomShareRelease.stoppedPartway }
    /// A run going now, in this window's sheet or another's: not offered again meanwhile.
    private var running: Bool { ClassroomShareRelease.isRunning }

    var body: some View {
        if Self.isShown(waiting: waiting, heldTwice: heldTwice, stoppedEarlier: stoppedEarlier, running: running) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
                ClassroomShareBanner(
                    icon: "calendar.badge.minus",
                    tint: AppColors.warning,
                    title: Self.title(waiting: waiting, heldTwice: heldTwice, running: running),
                    message: message
                )
                if ClassroomShareRelease.isAvailableHere {
                    // Disabled rather than removed while running: the sheet hangs off it.
                    Button {
                        showingRelease = true
                    } label: {
                        Label(
                            stoppedEarlier || waiting == 0
                                ? "Finish Removing Last Year…" : "Remove Last Year from the Share…",
                            systemImage: "calendar.badge.minus"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(running)
                    .sheet(isPresented: $showingRelease) {
                        ClassroomReleaseSheet {
                            await onFinished()
                        }
                    }
                    if running {
                        Text("It's running now. Keep this Mac awake and online until it finishes.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("Remove them on your Mac, in Settings › Classroom.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    static func isShown(waiting: Int, heldTwice: Int, stoppedEarlier: Bool, running: Bool) -> Bool {
        waiting > 0 || heldTwice > 0 || stoppedEarlier || running
    }

    static func title(waiting: Int, heldTwice: Int, running: Bool) -> String {
        if running { return "Removing last year from the share…" }
        if waiting == 0, heldTwice > 0 {
            return heldTwice == 1
                ? "1 item is in your notebook twice"
                : "\(heldTwice.formatted()) items are in your notebook twice"
        }
        if waiting == 0 { return "Removing last year was stopped partway" }
        return waiting == 1
            ? "1 item from before this school year is still shared"
            : "\(waiting.formatted()) items from before this school year are still shared"
    }

    private var message: String {
        if waiting == 0, heldTwice > 0, !running {
            return "Removing last year stopped partway and left them on both sides of the share. Finishing "
                + "keeps the copy your assistants see and removes the other one."
        }
        return "Children who left in an earlier school year, and marks from before this one. "
            + "They stay in your notebook; taking them out of the share takes them off your "
            + "assistants' iPhones."
    }
}
