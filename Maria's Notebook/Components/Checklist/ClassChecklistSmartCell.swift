import SwiftUI

// MARK: - THE SMART CELL

struct ClassChecklistSmartCell: View {
    let state: StudentChecklistRowState?
    let isSelected: Bool
    let isSelectionMode: Bool

    var onTap: () -> Void
    var onSelect: () -> Void
    var onMarkComplete: () -> Void
    var onMarkPresented: () -> Void
    var onMarkPreviouslyPresented: () -> Void
    var onClear: () -> Void

    var body: some View {
        let displayStatus = state?.displayStatus ?? .empty
        let isInboxPlan = state?.isInboxPlan ?? false
        let isStale = state?.isStale ?? false
        let isScheduled = state?.isScheduled ?? false

        ZStack {
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

            Color.clear.contentShape(Rectangle()) // Hit area

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
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 2)
                    .frame(width: 16, height: 16)
            }

            // Selection indicator
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
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
                .padding(2)
        )
        .onTapGesture {
            if isSelectionMode {
                onSelect()
            } else {
                onTap()
            }
        }
        .contextMenu {
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
    }
}

// MARK: - Cell Identifier for Multi-Selection

struct CellIdentifier: Hashable {
    let studentID: UUID
    let lessonID: UUID
}
