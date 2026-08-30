// WaitingStudentsColumn.swift
// The column of children down the left of the workspace.
//
// Both halves of Lessons & Work ask the same question in the same corner of the
// screen — who has gone longest without me — and answer it beside the cards you
// would act on. Presentations asks it about lessons, Work asks it about work.
// One view draws both, so the two halves cannot drift into looking like
// different features: the same heading and count, the same scope control, the
// same rows, the same empty state in the same place.
//
// What varies is passed in: the wording (`StudentWaitVocabulary`), the two
// controls that only make sense to one half (its scope picker and its empty
// state), and what tapping a child does.

import CoreData
import SwiftUI

/// Sizing shared by both columns.
enum StudentColumn {
    /// Wide enough for a full name over "115 school days ago" beside an avatar,
    /// narrow enough to leave the cards next to it usable.
    static let preferredWidth: CGFloat = 240
}

/// The age thresholds and colours, resolved once for a whole list.
struct StudentAgePalette {
    let warningDays: Int
    let overdueDays: Int
    let fresh: Color
    let warning: Color
    let overdue: Color

    /// A child there is nothing to measure for is the most overdue thing on the
    /// list, not an unknown.
    func status(forDays days: Int?) -> LessonAgeStatus {
        guard let days else { return .overdue }
        if days >= max(0, overdueDays) { return .overdue }
        if days >= max(0, warningDays) { return .warning }
        return .fresh
    }

    func color(forDays days: Int?) -> Color {
        switch status(forDays: days) {
        case .fresh: fresh
        case .warning: warning
        case .overdue: overdue
        }
    }

    /// The metadata line stays secondary until the child is actually late, so
    /// the colour means something when it arrives.
    func detailTint(forDays days: Int?) -> Color {
        switch status(forDays: days) {
        case .fresh: .secondary
        case .warning, .overdue: color(forDays: days)
        }
    }
}

struct WaitingStudentsColumn<Scope: View, Empty: View>: View {
    let vocabulary: StudentWaitVocabulary
    let entries: [WaitingStudent]
    let selectedStudentID: UUID?
    let onSelect: (CDStudent) -> Void
    private let scopePicker: Scope
    private let emptyState: Empty

    // Read here, once per list, rather than in each row. The keys come from the
    // vocabulary, so the bar down a row is coloured by the same settings as the
    // cards beside it.
    @SyncedAppStorage private var ageWarningDays: Int
    @SyncedAppStorage private var ageOverdueDays: Int
    @SyncedAppStorage private var ageFreshColorHex: String
    @SyncedAppStorage private var ageWarningColorHex: String
    @SyncedAppStorage private var ageOverdueColorHex: String

    init(
        vocabulary: StudentWaitVocabulary,
        entries: [WaitingStudent],
        selectedStudentID: UUID?,
        onSelect: @escaping (CDStudent) -> Void,
        @ViewBuilder scopePicker: () -> Scope,
        @ViewBuilder emptyState: () -> Empty
    ) {
        self.vocabulary = vocabulary
        self.entries = entries
        self.selectedStudentID = selectedStudentID
        self.onSelect = onSelect
        self.scopePicker = scopePicker()
        self.emptyState = emptyState()

        let keys = vocabulary.ageKeys
        _ageWarningDays = SyncedAppStorage(wrappedValue: LessonAgeDefaults.warningDays, keys.warningDays)
        _ageOverdueDays = SyncedAppStorage(wrappedValue: LessonAgeDefaults.overdueDays, keys.overdueDays)
        _ageFreshColorHex = SyncedAppStorage(wrappedValue: LessonAgeDefaults.freshColorHex, keys.freshColorHex)
        _ageWarningColorHex = SyncedAppStorage(wrappedValue: LessonAgeDefaults.warningColorHex, keys.warningColorHex)
        _ageOverdueColorHex = SyncedAppStorage(wrappedValue: LessonAgeDefaults.overdueColorHex, keys.overdueColorHex)
    }

    private var palette: StudentAgePalette {
        StudentAgePalette(
            warningDays: ageWarningDays,
            overdueDays: ageOverdueDays,
            fresh: ColorUtils.color(from: ageFreshColorHex),
            warning: ColorUtils.color(from: ageWarningColorHex),
            overdue: ColorUtils.color(from: ageOverdueColorHex)
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            scopePicker
                .padding(.horizontal, AppTheme.Spacing.small)
                .padding(.vertical, AppTheme.Spacing.verySmall)
            Divider()
            content
        }
        // The column sits in an HStack that would otherwise centre a short list,
        // so an empty one must not float the header down the page.
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color.primary.opacity(UIConstants.OpacityConstants.trace))
    }

    private var header: some View {
        HStack(spacing: AppTheme.Spacing.small) {
            Label(vocabulary.title, systemImage: vocabulary.systemImage)
                .font(.headline)
                .labelStyle(.titleAndIcon)
            Spacer()
            Text("\(entries.count)")
                .font(AppTheme.SemanticFont.metadata)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.horizontal, AppTheme.Spacing.compact)
        .padding(.vertical, AppTheme.Spacing.small)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(vocabulary.title), \(entries.count) children")
    }

    @ViewBuilder
    private var content: some View {
        if entries.isEmpty {
            emptyState
                // Claim the height the list would have had, so the header and
                // the scope picker stay pinned where they were a moment ago.
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            // Resolved once for the whole list, not once per row.
            let palette = palette
            ScrollView {
                LazyVStack(spacing: AppTheme.Spacing.xxsmall) {
                    ForEach(entries) { entry in
                        row(entry, palette: palette)
                    }
                }
                .padding(.horizontal, AppTheme.Spacing.small)
                .padding(.top, AppTheme.Spacing.small)
                .padding(.bottom, AppTheme.Spacing.medium)
            }
        }
    }

    private func row(_ entry: WaitingStudent, palette: StudentAgePalette) -> some View {
        WaitingStudentRow(
            entry: entry,
            ageColor: palette.color(forDays: entry.daysWaiting),
            detail: vocabulary.detail(forDays: entry.daysWaiting),
            detailTint: palette.detailTint(forDays: entry.daysWaiting),
            selectionHint: vocabulary.selectionHint,
            isSelected: selectedStudentID == entry.student.id,
            onTap: { onSelect(entry.student) }
        )
    }
}
