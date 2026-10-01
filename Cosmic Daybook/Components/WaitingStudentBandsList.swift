// WaitingStudentBandsList.swift
// The grouped body of the waiting column: the children past the long-wait line,
// then those who have waited a week or more, then one line standing in for
// everyone else.
//
// Which child goes where is `WaitingStudentBands`; this only draws the groups
// and remembers whether the folded one is open.

import CoreData
import SwiftUI

/// What the waiting rail remembers until the app quits, and no longer.
///
/// Deliberately not `@SceneStorage`, which state restoration carries across
/// launches: opening the folded group is a look, not a preference, and the rail
/// should come back folded tomorrow. It lives outside the view so the choice
/// survives the rail being rebuilt, as it is when the workspace switches halves
/// or the phone's sheet opens it.
@Observable
final class WaitingRailSession {
    static let shared = WaitingRailSession()

    /// Whether the guide has opened the "under a week" group.
    var showsUnderAWeek = false
}

struct WaitingStudentBandsList: View {
    let vocabulary: StudentWaitVocabulary
    let entries: [WaitingStudent]
    let palette: StudentAgePalette
    let selectedStudentID: UUID?
    /// While a search is narrowing the list, folding a match away would hide
    /// the very child that was searched for, so nothing folds.
    let isSearching: Bool
    let onSelect: (CDStudent) -> Void

    private var session: WaitingRailSession { .shared }

    var body: some View {
        let bands = WaitingStudentBands(entries, longWaitThreshold: palette.overdueDays)
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                group(bands.longWaitTitle, bands.longWait, tint: palette.overdue)
                group(WaitingStudentBands.aWeekOrMoreTitle, bands.aWeekOrMore, tint: nil)
                underAWeek(bands)
            }
            .padding(.horizontal, AppTheme.Spacing.small)
            .padding(.top, AppTheme.Spacing.xsmall)
            .padding(.bottom, AppTheme.Spacing.medium)
        }
    }

    @ViewBuilder
    private func group(_ title: String, _ members: [WaitingStudent], tint: Color?) -> some View {
        if !members.isEmpty {
            sectionLabel(title)
            lines(members, tint: tint)
        }
    }

    /// Folded by default into one line, because a child taught this week is
    /// not who the guide opened this rail to find.
    @ViewBuilder
    private func underAWeek(_ bands: WaitingStudentBands) -> some View {
        if !bands.underAWeek.isEmpty {
            if isSearching || !bands.hasChildrenAboveTheFold {
                sectionLabel(WaitingStudentBands.underAWeekTitle)
                lines(bands.underAWeek, tint: nil)
            } else if session.showsUnderAWeek {
                foldToggle(WaitingStudentBands.underAWeekTitle, count: bands.underAWeek.count, isOpen: true)
                lines(bands.underAWeek, tint: nil)
            } else {
                foldToggle(bands.underAWeekSummary, count: bands.underAWeek.count, isOpen: false)
            }
        }
    }

    private func lines(_ members: [WaitingStudent], tint: Color?) -> some View {
        ForEach(members) { entry in
            WaitingStudentLine(
                entry: entry,
                trailing: entry.daysWaiting.map { "\($0)" } ?? vocabulary.uncounted,
                sentence: vocabulary.spokenDetail(forDays: entry.daysWaiting),
                tint: tint,
                selectionHint: vocabulary.selectionHint,
                isSelected: selectedStudentID == entry.student.id,
                onTap: { onSelect(entry.student) }
            )
        }
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(AppTheme.ScaledFont.captionSmallSemibold)
            .foregroundStyle(.secondary)
            .padding(.horizontal, AppTheme.Spacing.small)
            .padding(.top, AppTheme.Spacing.small)
            .padding(.bottom, AppTheme.Spacing.xxsmall)
            .accessibilityAddTraits(.isHeader)
    }

    /// The folded group's one line, which turns into its label once open so
    /// the same place folds it away again.
    private func foldToggle(_ title: String, count: Int, isOpen: Bool) -> some View {
        Button {
            adaptiveWithAnimation(.easeInOut(duration: 0.15)) {
                session.showsUnderAWeek.toggle()
            }
        } label: {
            HStack(spacing: AppTheme.Spacing.xsmall) {
                Image(systemName: "chevron.right")
                    .imageScale(.small)
                    .rotationEffect(.degrees(isOpen ? 90 : 0))
                    .accessibilityHidden(true)
                Text(title)
                Spacer(minLength: 0)
            }
            .font(isOpen ? AppTheme.ScaledFont.captionSmallSemibold : AppTheme.ScaledFont.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, AppTheme.Spacing.small)
            .padding(.vertical, AppTheme.Spacing.xsmall)
            .padding(.top, AppTheme.Spacing.xsmall)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverableRow()
        .accessibilityLabel(
            count == 1 ? "1 more child, under a week" : "\(count) more children, under a week"
        )
        .accessibilityValue(isOpen ? "Shown" : "Hidden")
        .accessibilityHint(isOpen ? "Hides them" : "Shows them")
    }
}
