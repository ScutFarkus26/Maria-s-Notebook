// WaitingStudentsBar.swift
// The workspace's left-hand column on a phone: one scrolling row of names above
// the cards.
//
// A 240pt column is impossible here, but making it a separate tab would be
// worse — the whole point is seeing who has gone without *while* looking at
// what you could give them. So the same list, same order, laid on its side,
// costing one row of height.
//
// A long roster becomes a long swipe, so the scope control and an "All" button
// are pinned outside the scroll and always reachable; "All" opens the full
// column in a sheet.
//
// Shared by both halves for the same reason `WaitingStudentsColumn` is: the two
// bars have to stay the same control, and they only will if there is one of
// them.

import CoreData
import SwiftUI

struct WaitingStudentsBar<ScopeMenu: View, Expanded: View>: View {
    let vocabulary: StudentWaitVocabulary
    let entries: [WaitingStudent]
    let selectedStudentID: UUID?
    /// Shown in place of the chips when nobody is on the list.
    let emptyMessage: String
    let onSelect: (CDStudent) -> Void
    private let scopeMenu: ScopeMenu
    /// The full column, for the sheet behind "All".
    private let expanded: Expanded

    @State private var isShowingAll = false

    // One read for the whole bar. The chips used to be coloured from the shipped
    // defaults rather than the guide's settings, because five store lookups per
    // chip was too much to spend here — reading them once means the phone's dots
    // and the Mac's bars can finally agree.
    @SyncedAppStorage private var ageWarningDays: Int
    @SyncedAppStorage private var ageOverdueDays: Int
    @SyncedAppStorage private var ageFreshColorHex: String
    @SyncedAppStorage private var ageWarningColorHex: String
    @SyncedAppStorage private var ageOverdueColorHex: String

    init(
        vocabulary: StudentWaitVocabulary,
        entries: [WaitingStudent],
        selectedStudentID: UUID?,
        emptyMessage: String,
        onSelect: @escaping (CDStudent) -> Void,
        @ViewBuilder scopeMenu: () -> ScopeMenu,
        @ViewBuilder expanded: () -> Expanded
    ) {
        self.vocabulary = vocabulary
        self.entries = entries
        self.selectedStudentID = selectedStudentID
        self.emptyMessage = emptyMessage
        self.onSelect = onSelect
        self.scopeMenu = scopeMenu()
        self.expanded = expanded()

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
        HStack(spacing: AppTheme.Spacing.small) {
            scopeMenu
                .fixedSize()

            if entries.isEmpty {
                Text(emptyMessage)
                    .font(AppTheme.ScaledFont.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            } else {
                let palette = palette
                ScrollView(.horizontal) {
                    HStack(spacing: AppTheme.Spacing.verySmall) {
                        ForEach(entries) { entry in
                            chip(entry, palette: palette)
                        }
                    }
                    .padding(.trailing, AppTheme.Spacing.small)
                }
                .scrollIndicators(.hidden)

                allStudentsButton
            }
        }
        .padding(.horizontal, AppTheme.Spacing.medium)
        .padding(.vertical, AppTheme.Spacing.verySmall)
        .background(Color.primary.opacity(UIConstants.OpacityConstants.trace))
        .sheet(isPresented: $isShowingAll) {
            NavigationStack {
                expanded
                    .navigationTitle(vocabulary.title)
                    .inlineNavigationTitle()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { isShowingAll = false }
                        }
                    }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    /// The escape from a thirty-child swipe.
    private var allStudentsButton: some View {
        Button {
            isShowingAll = true
        } label: {
            Text("All")
                .font(AppTheme.ScaledFont.captionSemibold)
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.accentColor)
        .fixedSize()
        .accessibilityLabel("Show every child on this list")
    }

    private func chip(_ entry: WaitingStudent, palette: StudentAgePalette) -> some View {
        let isSelected = selectedStudentID == entry.student.id
        return Button {
            onSelect(entry.student)
        } label: {
            HStack(spacing: AppTheme.Spacing.verySmall) {
                // A capsule has no leading edge to run a bar down, so the same
                // urgency colour becomes a dot.
                Circle()
                    .fill(palette.color(forDays: entry.daysWaiting))
                    .frame(width: 6, height: 6)
                Text(StudentFormatter.firstName(for: entry.student))
                    .font(AppTheme.ScaledFont.caption)
                    .fontWeight(isSelected ? .semibold : .regular)
                Text(entry.daysWaiting.map { "\($0)d" } ?? "—")
                    .font(AppTheme.ScaledFont.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .padding(.horizontal, AppTheme.Spacing.compact)
            .padding(.vertical, AppTheme.Spacing.verySmall)
            .background(
                Capsule().fill(
                    isSelected
                        ? Color.accentColor.opacity(UIConstants.OpacityConstants.accent)
                        : Color.primary.opacity(UIConstants.OpacityConstants.veryFaint)
                )
            )
            .overlay {
                if isSelected {
                    Capsule().stroke(
                        Color.accentColor.opacity(UIConstants.OpacityConstants.half),
                        lineWidth: UIConstants.StrokeWidth.thin
                    )
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            "\(StudentFormatter.displayName(for: entry.student)), "
                + vocabulary.spokenDetail(forDays: entry.daysWaiting)
        )
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}
