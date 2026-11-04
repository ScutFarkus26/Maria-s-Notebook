import SwiftUI
import CoreData
import Foundation
import TipKit

// MARK: - Helper Methods & General Sections

extension WorkDetailView {

    // MARK: - Header Section

    @ViewBuilder
    // swiftlint:disable:next function_body_length
    func headerSection() -> some View {
        VStack(spacing: 20) {
            // Hero section with student avatar and work kind badge
            VStack(spacing: 14) {
                // CDStudent avatar circle
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    viewModel.workKind.color.opacity(UIConstants.OpacityConstants.heavy),
                                    viewModel.workKind.color
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 80, height: 80)
                        .shadow(AppTheme.ShadowStyle.medium)

                    Image(systemName: viewModel.workKind.iconName)
                        .font(.system(size: 32, weight: .semibold))
                        .foregroundStyle(.white)
                }

                // CDStudent name
                Text(studentName())
                    .font(AppTheme.ScaledFont.titleLarge)

                // CDLesson info pill
                Label(lessonTitle(), systemImage: "book.closed.fill")
                    .font(AppTheme.ScaledFont.captionSemibold)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, AppTheme.Spacing.compact)
                    .padding(.vertical, AppTheme.Spacing.small)
                    .capsuleFill(Color.primary.opacity(UIConstants.OpacityConstants.subtle))
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 8)

            // Work title field
            VStack(alignment: .leading, spacing: 6) {
                Text("Title")
                    .font(AppTheme.ScaledFont.captionSemibold)
                    .foregroundStyle(.secondary)
                TextField("Work Title", text: $viewModel.workTitle)
                    .font(AppTheme.ScaledFont.bodySemibold)
                    .padding(AppTheme.Spacing.compact)
                    .surface(
                        UIConstants.CornerRadius.large,
                        fill: Color.primary.opacity(UIConstants.OpacityConstants.veryFaint),
                        stroke: Color.primary.opacity(UIConstants.OpacityConstants.faint),
                        lineWidth: UIConstants.StrokeWidth.thin
                    )
            }

            // Work kind segmented control
            VStack(alignment: .leading, spacing: 8) {
                Text("Type")
                    .font(AppTheme.ScaledFont.captionSemibold)
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    ForEach(WorkKind.allCases) { kind in
                        SelectablePillButton(
                            item: kind,
                            isSelected: viewModel.workKind == kind,
                            color: kind.color,
                            icon: kind.iconName,
                            label: kind.shortLabel
                        ) {
                            adaptiveWithAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                viewModel.workKind = kind
                            }
                        }
                    }
                }
            }

            // Status pills
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 4) {
                    Text("Status")
                        .font(AppTheme.ScaledFont.captionSemibold)
                        .foregroundStyle(.secondary)
                    #if os(macOS)
                    Text("")
                        .help(
                            "Working and Needs Review keep it open; Mastered, Finished, Keep Practicing and "
                                + "Incomplete log it and clear its check-ins from the calendar"
                        )
                    #endif
                }

                // Six pills wrap rather than clip in a narrow sheet.
                HStack(alignment: .top, spacing: 8) {
                    FlowLayout(spacing: 8) {
                        ForEach(viewModel.statusChoices) { s in
                            SelectablePillButton(
                                item: s,
                                isSelected: viewModel.status == s,
                                color: s.color,
                                icon: s.iconName,
                                label: s.displayName
                            ) {
                                adaptiveWithAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    viewModel.status = s

                                    // When marking as complete with good outcome, offer to unlock next lesson
                                    if s == .mastered {
                                        viewModel.offerUnlock()
                                    }
                                }
                                if s.isClosed {
                                    HapticService.shared.notification(.success)
                                } else {
                                    HapticService.shared.selection()
                                }
                            }
                        }
                    }

                    if viewModel.status.isOpen, likelyNextLesson != nil {
                        Button {
                            viewModel.offerUnlock()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "lock.open.fill")
                                Text("Unlock")
                                    .font(AppTheme.ScaledFont.captionSemibold)
                            }
                            .foregroundStyle(Color.accentColor)
                            .padding(.horizontal, AppTheme.Spacing.compact)
                            .padding(.vertical, AppTheme.Spacing.small)
                            .capsuleFill(Color.accentColor.opacity(UIConstants.OpacityConstants.medium))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .popoverTip(WorkLifecycleTip(), arrowEdge: .top)

                // Saved with the status on Save — "Keep Practicing, needs the
                // trinomial cube again" is one gesture, not two sections.
                TextField("Add a note with this status…", text: $viewModel.completionNote)
                    .font(AppTheme.ScaledFont.body)
                    .padding(AppTheme.Spacing.compact)
                    .surface(
                        UIConstants.CornerRadius.medium,
                        fill: Color.primary.opacity(UIConstants.OpacityConstants.veryFaint)
                    )
            }

            // Check-in style
            VStack(alignment: .leading, spacing: 8) {
                Text("Check-In Style")
                    .font(AppTheme.ScaledFont.captionSemibold)
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    ForEach(CheckInStyle.allCases) { style in
                        SelectablePillButton(
                            item: style,
                            isSelected: viewModel.checkInStyle == style,
                            color: style.color,
                            icon: style.iconName,
                            label: style.displayName
                        ) {
                            adaptiveWithAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                viewModel.checkInStyle = style
                            }
                        }
                    }
                }

                Text(viewModel.checkInStyle.shortDescription)
                    .font(AppTheme.ScaledFont.captionSmall)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - Notes Section

    @ViewBuilder
    func notesSection() -> some View {
        DetailSectionCard(
            title: "Notes",
            icon: "note.text",
            accentColor: .purple,
            trailing: {
                Button { activeSheet = .addNote } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.purple)
                }
                .accessibilityLabel("Add note")
                .buttonStyle(.plain)
            },
            content: {
                if viewModel.workModelNotes.isEmpty {
                    EmptyStateView(
                        icon: "note.text",
                        title: "No notes yet",
                        subtitle: "Add notes to track progress"
                    )
                } else {
                    VStack(spacing: 10) {
                        ForEach(
                        viewModel.workModelNotes
                            .sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) },
                        id: \.objectID
                    ) { note in
                            noteRow(note)
                        }
                    }
                }
            }
        )
    }

    @ViewBuilder
    func noteRow(_ note: CDNote) -> some View {
        // The trash button asks first: the note is also on her Notes tab.
        NoteRowView(
            note: note,
            onEdit: { activeSheet = .editNote(note) },
            onDelete: { viewModel.notePendingDelete = note }
        )
    }

    // MARK: - Action Methods

    func save() {
        guard viewModel.save(modelContext: modelContext, saveCoordinator: saveCoordinator) else { return }
        close()
    }

    func close() { onDone?() ?? dismiss() }

    func deleteWork() {
        viewModel.deleteWork(modelContext: modelContext, saveCoordinator: saveCoordinator) {
            // Closed on the next turn, not inside the alert's own action: a
            // dismissal issued while the alert is still tearing itself down is
            // swallowed, and the window this was deleted from stays open over a
            // work item that no longer exists.
            Task { close() }
        }
    }

    func deleteNote(_ note: CDNote) {
        modelContext.delete(note)
        saveCoordinator.save(modelContext, reason: "Deleting note")

        // The notes only: unsaved header edits stay as they are.
        viewModel.reloadNotes()
    }

    func studentName() -> String {
        viewModel.relatedStudent?.shortName ?? "Student"
    }

    func lessonTitle() -> String {
        return viewModel.relatedLesson?.name ?? "Lesson"
    }
}
