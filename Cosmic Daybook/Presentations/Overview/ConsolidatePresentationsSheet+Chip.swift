// ConsolidatePresentationsSheet+Chip.swift
// One child's chip in Merge Groups: dragged onto another group to move her,
// or removed from its menu. Split from ConsolidatePresentationsSheet.swift for
// SwiftLint's file-length limit.

import SwiftUI

/// A child on one of the lesson's presentations in Merge Groups.
struct DraggableStudentChip: View {
    let student: CDStudent?
    let studentID: UUID
    let sourcePresentationID: UUID
    let lessonID: UUID
    let areaColor: Color
    let isDuplicate: Bool
    let onRemove: () -> Void

    private var label: String {
        if let student { return student.shortName }
        return "(Removed)"
    }

    private var fillColor: Color {
        isDuplicate
            ? AppColors.warning.opacity(UIConstants.OpacityConstants.accent)
            : areaColor.opacity(UIConstants.OpacityConstants.accent)
    }

    private var strokeColor: Color {
        isDuplicate
            ? AppColors.warning
            : areaColor.opacity(UIConstants.OpacityConstants.medium)
    }

    var body: some View {
        HStack(spacing: 4) {
            if isDuplicate {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundStyle(AppColors.warning)
            }
            Text(label)
                .font(.caption.weight(.medium))
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .capsuleFill(fillColor)
        .overlay(
            Capsule().stroke(strokeColor, lineWidth: isDuplicate ? 1.5 : 1)
        )
        .foregroundStyle(.primary)
        .contentShape(Capsule())
        .onDrag {
            let payload = DragPayload.encode(
                sourceID: sourcePresentationID,
                lessonID: lessonID,
                studentID: studentID
            )
            let provider = NSItemProvider(object: NSString(string: payload))
            provider.suggestedName = label
            return provider
        }
        .contextMenu {
            Button(role: .destructive, action: onRemove) {
                Label("Remove from this presentation", systemImage: "person.fill.xmark")
            }
        }
        .accessibilityLabel(isDuplicate ? "\(label), also in another presentation" : label)
    }
}
