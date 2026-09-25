// PresentationCard.swift
// Presentation card component extracted from PresentationsListView

import SwiftUI
import CoreData
#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct PresentationCard: View {
    let snapshot: LessonAssignmentSnapshot
    let lesson: CDLesson?
    let students: [CDStudent]

    private var lessonName: String {
        (lesson?.name.isEmpty == false ? lesson?.name : nil) ?? "Lesson"
    }

    private var area: String {
        lesson?.area ?? ""
    }

    private var areaColor: Color {
        AppColors.color(forArea: area)
    }

    private var areaBadge: some View {
        StatusPill(
            text: area.isEmpty ? "Area" : area,
            color: areaColor,
            icon: nil
        )
        .accessibilityLabel("Area: \(area.isEmpty ? "Unknown" : area)")
    }

    private struct ChipEntry: Identifiable { let id: UUID; let label: String; let isMissing: Bool }
    private var studentChips: [ChipEntry] {
        var chips: [ChipEntry] = []
        for id in snapshot.studentIDs {
            if let s = students.first(where: { $0.id == id }) {
                chips.append(ChipEntry(id: id, label: s.shortName, isMissing: false))
            } else {
                chips.append(ChipEntry(id: id, label: "(Removed)", isMissing: true))
            }
        }
        return chips
    }

    private var statusText: String {
        if snapshot.isPresented {
            if let given = snapshot.presentedAt {
                return "Presented on " + DateFormatters.weekdayAndDate.string(from: given)
            } else {
                return "Presented"
            }
        } else if let scheduled = snapshot.scheduledFor {
            return "Scheduled for " + DateFormatters.weekdayAndDate.string(from: scheduled)
        } else {
            return "Not Scheduled"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(lessonName)
                    .font(AppTheme.ScaledFont.titleSmall)
                Spacer(minLength: 0)
                areaBadge
            }

            if !studentChips.isEmpty {
                // Wraps rather than scrolls: no scroll view per card.
                FlowLayout(spacing: AppTheme.Spacing.verySmall) {
                    ForEach(studentChips, id: \.id) { chip in
                        StudentChip(chip.label, tint: areaColor, isMissing: chip.isMissing, foreground: .label)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Text(statusText)
                .font(AppTheme.ScaledFont.caption)
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)
        }
        .padding(14) // Keep custom value - not in constants
        .frame(minHeight: 100)
        .background(
            RoundedRectangle(cornerRadius: UIConstants.CornerRadius.tile, style: .continuous)
                .fill(cardBackgroundColor)
                .overlay(
                    RoundedRectangle(cornerRadius: UIConstants.CornerRadius.tile, style: .continuous)
                        .stroke(Color.primary.opacity(UIConstants.OpacityConstants.veryFaint), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(UIConstants.OpacityConstants.trace), radius: 6, x: 0, y: 2)
        )
        .accessibilityElement(children: .combine)
    }

    private var cardBackgroundColor: Color {
        AppTheme.Colors.paneBackground
    }
}
