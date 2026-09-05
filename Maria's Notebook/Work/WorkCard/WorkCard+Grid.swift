import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Grid mode content for WorkCard
/// Displays: age indicator bar, title, student name, status, needs attention badge
/// Supports: tap to open, context menu, drag for calendar scheduling
struct WorkCardGridContent: View {
    let config: WorkCard.GridModeConfig

    // Not private: the context menu lives in WorkCard+GridMenu.swift.
    @Environment(\.managedObjectContext) var viewContext
    @Environment(\.appRouter) var appRouter

    // Not private: the Schedule menu, which lives in the other file, is what
    // raises the calendar. Held on the card rather than on the grid so the
    // popover points at the card the guide right-clicked.
    @State var isPickingCheckDay = false

    @SyncedAppStorage("WorkAge.warningDays") private var ageWarningDays: Int = LessonAgeDefaults.warningDays
    @SyncedAppStorage("WorkAge.overdueDays") private var ageOverdueDays: Int = LessonAgeDefaults.overdueDays
    @SyncedAppStorage("WorkAge.freshColorHex") private var ageFreshColorHex: String = LessonAgeDefaults.freshColorHex
    @SyncedAppStorage("WorkAge.warningColorHex")
    private var ageWarningColorHex: String = LessonAgeDefaults.warningColorHex
    @SyncedAppStorage("WorkAge.overdueColorHex")
    private var ageOverdueColorHex: String = LessonAgeDefaults.overdueColorHex

    private var ageStatus: LessonAgeStatus {
        if config.ageSchoolDays >= max(0, ageOverdueDays) { return .overdue }
        if config.ageSchoolDays >= max(0, ageWarningDays) { return .warning }
        return .fresh
    }

    private var ageColor: Color {
        switch ageStatus {
        case .fresh: return ColorUtils.color(from: ageFreshColorHex)
        case .warning: return ColorUtils.color(from: ageWarningColorHex)
        case .overdue: return ColorUtils.color(from: ageOverdueColorHex)
        }
    }

    private var kindText: String {
        (config.work.kind ?? .research).displayName
    }

    private var displayTitle: String {
        let trimmedTitle = config.work.title.trimmed()
        if !trimmedTitle.isEmpty {
            return trimmedTitle
        }
        return config.lessonTitle
    }

    var body: some View {
        HStack(spacing: 0) {
            ageIndicator
            gridContent
        }
        .padding(8)
        .frame(maxWidth: .infinity, minHeight: 60)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.primary.opacity(UIConstants.OpacityConstants.trace))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.primary.opacity(UIConstants.OpacityConstants.veryFaint))
        )
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        // Command-click extends the selection instead of opening the card, so
        // one click never both selects and navigates away.
        .onTapGesture {
            guard config.selection?.handleTap(on: config.work.id) != true else { return }
            config.onOpen(config.work)
        }
        // A substituted id resolves to nothing on drop, and the drop reports
        // success regardless — so a card with no id is not a drag source.
        .modifier(WorkCardDragModifier(
            workID: config.work.id,
            title: displayTitle,
            studentDisplay: config.studentDisplay,
            selection: config.selection
        ))
        .workspaceSelectionRing(config.selection?.contains(config.work.id) == true)
        // On the card, not on the metadata line it used to hang off — a menu
        // you can only reach by right-clicking "Adina T. • Practice • 110d" is
        // a menu most of the card doesn't have.
        .contextMenu { gridContextMenu }
        .popover(isPresented: $isPickingCheckDay) {
            // Resolved when the day is picked, not when the menu opened: the
            // selection is the menu's target, and it can change underneath a
            // popover that stays up.
            WorkCheckDayPicker(count: menuTargets.count) { day in
                isPickingCheckDay = false
                schedule(menuTargets, on: day)
            } onCancel: {
                isPickingCheckDay = false
            }
        }
    }

    private var ageIndicator: some View {
        Rectangle()
            .fill(ageColor)
            .frame(width: UIConstants.ageIndicatorWidth)
            .opacity(config.work.status == .complete ? 0.0 : 1.0)
            .accessibilityHidden(true)
    }

    private var gridContent: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                titleRow
                metadataRow
            }
            Spacer()
        }
    }

    private var titleRow: some View {
        HStack {
            Text(displayTitle)
                .font(.subheadline.weight(.bold))
                .lineLimit(2)
            Spacer()
            if config.needsAttention {
                Text("Needs Attention")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.red.opacity(UIConstants.OpacityConstants.nearSolid)))
                    .accessibilityLabel("Needs Attention")
            }
        }
    }

    private var metadataRow: some View {
        HStack(spacing: 8) {
            Text(config.studentDisplay)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text("•")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(kindText)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text("•")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("\(config.ageSchoolDays)d")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    func copyWorkTitle() {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(displayTitle, forType: .string)
        #else
        UIPasteboard.general.string = displayTitle
        #endif
    }
}

// The `#Preview` closure is expanded and type-checked in every compiler job
// for the module; a private view is checked once, in this file's job.
private struct WorkCardGridPreview: View {
    var body: some View {
        let stack = CoreDataStack.preview
        let ctx = stack.viewContext
        let work = CDWorkModel(context: ctx)
        work.status = .active; work.studentID = UUID().uuidString; work.lessonID = UUID().uuidString

        return WorkCard.grid(
            work: work,
            lessonTitle: "Long Division",
            studentDisplay: "Ada Lovelace",
            needsAttention: true,
            ageSchoolDays: 7,
            onOpen: { _ in },
            onMarkCompleted: { _ in },
            onSchedule: { _, _ in }
        )
        .padding()
        .previewEnvironment(using: stack)
    }
}

#Preview {
    WorkCardGridPreview()
}

/// Makes a work card draggable onto the calendar, and only when it has an id.
private struct WorkCardDragModifier: ViewModifier {
    let workID: UUID?
    let title: String
    let studentDisplay: String
    /// Dragging a selected card drags every selected card.
    let selection: WorkspaceMultiSelection?

    func body(content: Content) -> some View {
        if let workID {
            let payload = selection?.dragPayload(
                startingAt: workID,
                make: UnifiedCalendarDragPayload.work
            ) ?? UnifiedCalendarDragPayload.work(workID).stringRepresentation
            content.draggable(payload) {
                // Plain strings only, so the preview needs no environment.
                VStack(alignment: .leading, spacing: 6) {
                    Text(title).font(.subheadline)
                    Text(studentDisplay).font(.caption).foregroundStyle(.secondary)
                }
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.primary.opacity(UIConstants.OpacityConstants.veryFaint))
                )
            }
        } else {
            content
        }
    }
}
