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
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(UIConstants.OpacityConstants.trace)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(UIConstants.OpacityConstants.veryFaint)))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .onTapGesture { config.onOpen(config.work) }
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
        .contextMenu {
            Button {
                config.onOpen(config.work)
            } label: {
                Label("Open", systemImage: "arrow.forward.circle")
            }

            #if os(macOS)
            Button {
                if let id = config.work.id { openWorkInNewWindow(id) }
            } label: {
                Label("Open in New Window", systemImage: "uiwindow.split.2x1")
            }
            #endif

            Divider()

            Button {
                config.onMarkCompleted(config.work)
            } label: {
                Label("Mark Completed", systemImage: "checkmark.circle")
            }

            // Status change submenu
            Menu {
                Button {
                    // Set to Practice (active)
                } label: {
                    Label("Practice", systemImage: config.work.status == .active ? "checkmark" : "circle")
                }
                Button {
                    // Set to Follow-Up (review)
                } label: {
                    Label("Follow-Up", systemImage: config.work.status == .review ? "checkmark" : "circle")
                }
            } label: {
                Label("Change Status", systemImage: "arrow.triangle.2.circlepath")
            }

            Menu {
                Button("Today") { config.onScheduleToday(config.work) }
            } label: {
                Label("Schedule", systemImage: "calendar")
            }

            Divider()

            Button {
                copyWorkTitle()
            } label: {
                Label("Copy Title", systemImage: "doc.on.doc")
            }
        }
        .draggable(UnifiedCalendarDragPayload.work(config.work.id ?? UUID()).stringRepresentation) {
            VStack(alignment: .leading, spacing: 6) {
                Text(displayTitle).font(.subheadline)
                Text(config.studentDisplay).font(.caption).foregroundStyle(.secondary)
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(UIConstants.OpacityConstants.veryFaint)))
        }
    }

    private func copyWorkTitle() {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(displayTitle, forType: .string)
        #else
        UIPasteboard.general.string = displayTitle
        #endif
    }
}

#Preview {
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
        onScheduleToday: { _ in }
    )
    .padding()
    .previewEnvironment(using: stack)
}
