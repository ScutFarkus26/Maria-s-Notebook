// ProgressDashboardCategoryRow.swift
// One sequence row inside a student's subject section.
//
// Visual: leading colored bar, sequence label, then a row of lesson pills tinted by the
// area color. Each pill's fill density / icon overlay encodes its progression status
// (not started, scheduled, presented, practicing, reviewing, completed).
// Tapping the row opens the sequence detail sheet.

import SwiftUI

struct ProgressDashboardCategoryRow: View {
    let sequence: SequenceProgression
    let areaColor: Color
    let onTap: () -> Void

    @State private var isPinned: Bool = false

    private let labelColumnWidth: CGFloat = 180
    private let collapsedHeight: CGFloat = 38
    private let barWidth: CGFloat = 3

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: isPinned ? .top : .center, spacing: 12) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(areaColor.opacity(0.85))
                    .frame(width: barWidth, height: isPinned ? 14 : (collapsedHeight - 12))
                    .padding(.top, isPinned ? 9 : 0)

                Text(sequence.sequence)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .frame(width: labelColumnWidth, alignment: .leading)
                    .padding(.top, isPinned ? 5 : 0)

                pillsContainer

                Spacer(minLength: 8)

                progressBadge
                    .padding(.top, isPinned ? 5 : 0)

                pinToggleButton
                    .padding(.top, isPinned ? 5 : 0)
            }
            .padding(.horizontal, 8)
            .frame(minHeight: collapsedHeight)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(areaColor.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(areaColor.opacity(0.18), lineWidth: 0.5)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .help("\(sequence.area) — \(sequence.sequence) · \(sequence.presentedCount)/\(sequence.totalCount) presented")
    }

    /// "X / Y" presented count, color-coded.
    private var progressBadge: some View {
        Text("\(sequence.presentedCount)/\(sequence.totalCount)")
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(.secondary)
    }

    /// Chevron to pin the row open so all pills wrap onto multiple lines.
    private var pinToggleButton: some View {
        Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
                isPinned.toggle()
            }
        } label: {
            Image(systemName: isPinned ? "chevron.up" : "chevron.down")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.tertiary)
                .frame(minWidth: 18, alignment: .trailing)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(isPinned ? "Collapse" : "Show all lessons")
    }

    @ViewBuilder
    private var pillsContainer: some View {
        if isPinned {
            FlowLayout(spacing: 5) {
                ForEach(sequence.pills) { pill in
                    ProgressionStatusPill(pill: pill, areaColor: areaColor)
                }
            }
            .padding(.vertical, 5)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 5) {
                    ForEach(sequence.pills) { pill in
                        ProgressionStatusPill(pill: pill, areaColor: areaColor)
                    }
                }
                .padding(.vertical, 3)
            }
        }
    }
}

/// Lesson pill whose visual treatment encodes its progression status.
/// - notStarted: hollow pill, faint tint
/// - scheduled: dashed border in status color, clock leading icon
/// - presented: solid area-tinted fill
/// - practicing: solid fill + pencil leading icon
/// - reviewing: solid fill + warning leading icon, yellow tint
/// - completed: solid fill + checkmark leading icon, green tint
struct ProgressionStatusPill: View {
    let pill: LessonPillState
    let areaColor: Color

    var body: some View {
        HStack(spacing: 4) {
            if let icon = leadingIcon {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(statusForeground)
            }
            Text(pill.name)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(textColor)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(
            Capsule(style: .continuous)
                .fill(fillColor)
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(strokeColor, style: strokeStyle)
        )
        .help("\(pill.name) — \(pill.status.label)")
        .accessibilityLabel("\(pill.name), \(pill.status.label)")
    }

    private var leadingIcon: String? {
        switch pill.status {
        case .notStarted:   return nil
        case .scheduled:    return "clock"
        case .presented:    return nil
        case .practicing:   return "pencil"
        case .reviewing:    return "exclamationmark"
        case .completed:    return "checkmark"
        }
    }

    private var fillColor: Color {
        switch pill.status {
        case .notStarted:   return Color.gray.opacity(0.06)
        case .scheduled:    return areaColor.opacity(0.08)
        case .presented:    return areaColor.opacity(0.22)
        case .practicing:   return areaColor.opacity(0.30)
        case .reviewing:    return Color.yellow.opacity(0.25)
        case .completed:    return Color.green.opacity(0.30)
        }
    }

    private var strokeColor: Color {
        switch pill.status {
        case .notStarted:   return Color.gray.opacity(0.35)
        case .scheduled:    return areaColor.opacity(0.65)
        case .presented:    return areaColor.opacity(0.60)
        case .practicing:   return areaColor.opacity(0.75)
        case .reviewing:    return Color.yellow.opacity(0.85)
        case .completed:    return Color.green.opacity(0.80)
        }
    }

    private var strokeStyle: StrokeStyle {
        switch pill.status {
        case .scheduled:
            return StrokeStyle(lineWidth: 0.75, dash: [2.5, 2])
        default:
            return StrokeStyle(lineWidth: 0.75)
        }
    }

    private var textColor: Color {
        switch pill.status {
        case .notStarted:   return .secondary
        default:            return .primary
        }
    }

    private var statusForeground: Color {
        switch pill.status {
        case .reviewing:    return Color(.systemOrange)
        case .completed:    return Color.green
        default:            return areaColor
        }
    }
}
