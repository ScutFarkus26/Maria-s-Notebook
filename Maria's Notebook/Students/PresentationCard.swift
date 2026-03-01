// PresentationCard.swift
// Presentation card component extracted from PresentationsListView

import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct PresentationCard: View {
    let snapshot: LessonAssignmentSnapshot
    let lesson: Lesson?
    let students: [Student]

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
                chips.append(StudentChip(id: id, label: displayName(for: s), isMissing: false))
            } else {
                chips.append(StudentChip(id: id, label: "(Removed)", isMissing: true))
            }
        }
        return chips
    }

    private func displayName(for student: Student) -> String {
        let parts = student.fullName.split(separator: " ")
        guard let first = parts.first else { return student.fullName }
        let lastInitial = parts.dropFirst().first?.first.map { String($0) } ?? ""
        return lastInitial.isEmpty ? String(first) : "\(first) \(lastInitial)."
    }

    private var statusText: String {
        if snapshot.isPresented {
            if let given = snapshot.presentedAt {
                let fmt = DateFormatter()
                fmt.setLocalizedDateFormatFromTemplate("EEEE, MMM d")
                return "Presented on " + fmt.string(from: given)
            } else {
                return "Presented"
            }
        } else if let scheduled = snapshot.scheduledFor {
            let fmt = DateFormatter()
            fmt.setLocalizedDateFormatFromTemplate("EEEE, MMM d")
            return "Scheduled for " + fmt.string(from: scheduled)
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
                                    .fill(chip.isMissing ? Color.primary.opacity(UIConstants.OpacityConstants.faint) : subjectColor.opacity(0.15))
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
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.primary.opacity(0.06), lineWidth: 1))
                .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 2)
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

