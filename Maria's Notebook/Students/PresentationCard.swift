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

    private var subject: String {
        lesson?.subject ?? ""
    }

    private var subjectColor: Color {
        AppColors.color(forSubject: subject)
    }

    private var subjectBadge: some View {
        StatusPill(
            text: subject.isEmpty ? "Subject" : subject,
            color: subjectColor,
            icon: nil
        )
        .accessibilityLabel("Subject: \(subject.isEmpty ? "Unknown" : subject)")
    }

    private struct StudentChip: Identifiable { let id: UUID; let label: String; let isMissing: Bool }
    private var studentChips: [StudentChip] {
        var chips: [StudentChip] = []
        for id in snapshot.studentIDs {
            if let s = students.first(where: { $0.id == id }) {
                chips.append(StudentChip(id: id, label: StudentFormatter.displayName(for: s), isMissing: false))
            } else {
                chips.append(StudentChip(id: id, label: "(Removed)", isMissing: true))
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
                subjectBadge
            }

            if !studentChips.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: AppTheme.Spacing.verySmall) {
                        ForEach(studentChips, id: \.id) { chip in
                            HStack(spacing: AppTheme.Spacing.verySmall) {
                                Text(chip.label)
                                    .font(AppTheme.ScaledFont.captionSemibold)
                                    .foregroundStyle(chip.isMissing ? .secondary : .primary)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, AppTheme.Spacing.verySmall)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(
                                        chip.isMissing
                                            ? Color.primary.opacity(UIConstants.OpacityConstants.faint)
                                            : subjectColor.opacity(UIConstants.OpacityConstants.accent)
                                    )
                            )
                        }
                    }
                }
            }

            Text(statusText)
                .font(AppTheme.ScaledFont.caption)
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)
        }
        .padding(14) // Keep custom value - not in constants
        .frame(minHeight: 100)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(cardBackgroundColor)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.primary.opacity(UIConstants.OpacityConstants.veryFaint), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(UIConstants.OpacityConstants.trace), radius: 6, x: 0, y: 2)
        )
        .accessibilityElement(children: .combine)
    }

    private var cardBackgroundColor: Color {
        #if os(macOS)
        return Color(NSColor.windowBackgroundColor)
        #else
        return Color(uiColor: .secondarySystemBackground)
        #endif
    }
}
