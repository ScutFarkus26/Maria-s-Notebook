import SwiftUI

// MARK: - THE SMART CELL

struct ClassChecklistSmartCell: View {
    let state: StudentChecklistRowState?
    let isSelected: Bool
    let isSelectionMode: Bool
    var studentName: String = ""
    var lessonName: String = ""

    var onTap: () -> Void
    var onSelect: () -> Void
    var onMarkComplete: () -> Void
    var onMarkPresented: () -> Void
    var onMarkPreviouslyPresented: () -> Void
    var onClear: () -> Void

    var body: some View {
        let displayStatus = state?.displayStatus ?? .empty
        let isScheduled = state?.isScheduled ?? false
        let blockingReason = state?.blockingReason ?? .none

        cellContent(displayStatus: displayStatus, blockingReason: blockingReason)
            .overlay(selectionStroke)
            .onTapGesture { isSelectionMode ? onSelect() : onTap() }
            .contextMenu { cellContextMenu(blockingReason: blockingReason, isScheduled: isScheduled) }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(studentName), \(lessonName)")
            .accessibilityValue(accessibilityValueText)
            .accessibilityHint(isSelectionMode ? "Double tap to select" : "Double tap to see options")
    }

    // MARK: - Cell Content

    private func cellContent(displayStatus: ChecklistDisplayStatus, blockingReason: BlockingReason) -> some View {
        let isStale = state?.isStale ?? false

        return ZStack {
            // Staleness tint background
            if isStale && displayStatus != .proficient && displayStatus != .empty {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.orange.opacity(UIConstants.OpacityConstants.light))
            }

            // Selection highlight background
            if isSelected {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.accentColor.opacity(UIConstants.OpacityConstants.accent))
            }

            Color.clear.contentShape(Rectangle())

            statusIcon(displayStatus: displayStatus)
            blockingBadge(reason: blockingReason, show: displayStatus == .empty)
            selectionBadge
        }
    }

    // MARK: - Status Icon

    @ViewBuilder
    private func statusIcon(displayStatus: ChecklistDisplayStatus) -> some View {
        let isInboxPlan = state?.isInboxPlan ?? false

        switch displayStatus {
        case .proficient:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Color.green)
                .font(.title2)
        case .reviewing:
            Image(systemName: "eye.fill")
                .foregroundStyle(Color.yellow)
                .font(.title3)
        case .practicing:
            Image(systemName: "pencil")
                .foregroundStyle(Color.blue)
                .font(.title3.weight(.bold))
        case .presented:
            Image(systemName: "checkmark")
                .foregroundStyle(Color.blue)
                .font(.title3.weight(.bold))
        case .scheduled:
            Image(systemName: isInboxPlan ? "tray" : "calendar")
                .foregroundStyle(Color.orange)
                .font(.title3)
        case .empty:
            Circle()
                .stroke(Color.secondary.opacity(UIConstants.OpacityConstants.moderate), lineWidth: 2)
                .frame(width: 16, height: 16)
        }
    }

    private var selectionStroke: some View {
        RoundedRectangle(cornerRadius: 6)
            .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
            .padding(2)
    }

    // MARK: - Accessibility

    private var accessibilityValueText: String {
        var value = state?.displayStatus.label ?? "Not Started"
        if let reason = state?.blockingReason, reason != .none {
            value += ", \(reason.label)"
        }
        return value
    }

    // MARK: - Context Menu

    @ViewBuilder
    private func cellContextMenu(blockingReason: BlockingReason, isScheduled: Bool) -> some View {
        if blockingReason != .none {
            Label(blockingReason.label, systemImage: blockingReason.iconName)
            Divider()
        }
        Button {
            #if os(iOS)
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
            #endif
            onSelect()
        } label: {
            Label("Select", systemImage: "checkmark.circle")
        }
        Divider()
        Button { onTap() } label: { Label(isScheduled ? "Remove Plan" : "Add to Inbox", systemImage: "tray") }
        Button { onMarkPresented() } label: { Label("Mark Presented", systemImage: "checkmark") }
        Button { onMarkPreviouslyPresented() } label: {
            Label("Previously Presented", systemImage: "clock.badge.checkmark")
        }
        Button { onMarkComplete() } label: { Label("Mark Mastered", systemImage: "checkmark.circle.fill") }
        Divider()
        Button(role: .destructive) { onClear() } label: { Label("Clear All Status", systemImage: "xmark.circle") }
    }

    // MARK: - Extracted Subviews

    @ViewBuilder
    private func blockingBadge(reason: BlockingReason, show: Bool) -> some View {
        if reason != .none && show {
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Image(systemName: reason.iconName)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(reason.color)
                        .padding(2)
                        .background(Circle().fill(Color.white).shadow(radius: 0.5))
                }
            }
            .padding(2)
        }
    }

    @ViewBuilder
    private var selectionBadge: some View {
        if isSelected {
            VStack {
                HStack {
                    Spacer()
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.accentColor)
                        .font(.caption)
                        .background(Circle().fill(Color.white).padding(-1))
                }
                Spacer()
            }
            .padding(4)
        }
    }
}

// MARK: - Cell Identifier for Multi-Selection

struct CellIdentifier: Hashable {
    let studentID: UUID
    let lessonID: UUID
}
