import SwiftUI
import SwiftData
import Foundation

// MARK: - Helper Methods & General Sections

extension WorkDetailView {

    // MARK: - Header Section

    @ViewBuilder
    func headerSection() -> some View {
        VStack(spacing: 20) {
            // Hero section with student avatar and work kind badge
            VStack(spacing: 14) {
                // Student avatar circle
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [viewModel.workKind.color.opacity(0.8), viewModel.workKind.color],
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

                // Student name
                Text(studentName())
                    .font(AppTheme.ScaledFont.titleLarge)

                // Lesson info pill
                Label(lessonTitle(), systemImage: "book.closed.fill")
                    .font(AppTheme.ScaledFont.captionSemibold)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, AppTheme.Spacing.compact)
                    .padding(.vertical, AppTheme.Spacing.small)
                    .background(Capsule().fill(Color.primary.opacity(UIConstants.OpacityConstants.subtle)))
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
                    .background(
                        RoundedRectangle(cornerRadius: UIConstants.CornerRadius.large)
                            .fill(Color.primary.opacity(UIConstants.OpacityConstants.veryFaint))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: UIConstants.CornerRadius.large)
                            .stroke(Color.primary.opacity(UIConstants.OpacityConstants.faint), lineWidth: UIConstants.StrokeWidth.thin)
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
                        .help("Active = in progress, Review = checking work, Complete = finished")
                    #endif
                }

                HStack(spacing: 8) {
                    ForEach(WorkStatus.allCases) { s in
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
                                if let info = unlockInfo {
                                    checkAndOfferUnlock(lessonID: info.lessonID, studentID: info.studentID)
                                }
                            }
                            if s == .complete {
                                HapticService.shared.notification(.success)
                            } else {
                                HapticService.shared.selection()
                            }
                        }
                    }

                    Spacer()

                    if viewModel.status != .complete, likelyNextLesson != nil {
                        Button { viewModel.showScheduleSheet = true } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "lock.open.fill")
                                Text("Unlock")
                                    .font(AppTheme.ScaledFont.captionSemibold)
                            }
                            .foregroundStyle(Color.accentColor)
                            .padding(.horizontal, AppTheme.Spacing.compact)
                            .padding(.vertical, AppTheme.Spacing.small)
                            .background(
                                Capsule()
                                    .fill(Color.accentColor.opacity(UIConstants.OpacityConstants.medium))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
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
                Button { viewModel.showAddNoteSheet = true } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.purple)
                }
                .accessibilityLabel("Add note")
                .buttonStyle(.plain)
            }
        ) {
            if viewModel.workModelNotes.isEmpty {
                EmptyStateView(
                    icon: "note.text",
                    title: "No notes yet",
                    subtitle: "Add notes to track progress"
                )
            } else {
                VStack(spacing: 10) {
                    ForEach(viewModel.workModelNotes.sorted(by: { $0.createdAt > $1.createdAt }), id: \.id) { note in
                        noteRow(note)
                    }
                }
            }
        }
    }

    @ViewBuilder
    func noteRow(_ note: Note) -> some View {
        NoteRowView(note: note, onEdit: { viewModel.noteBeingEdited = note }, onDelete: { deleteNote(note) })
    }

    // MARK: - Action Methods

    func save() {
        viewModel.save(modelContext: modelContext, saveCoordinator: saveCoordinator)
        close()
    }

    func close() { onDone?() ?? dismiss() }

    func deleteWork() {
        viewModel.deleteWork(modelContext: modelContext, saveCoordinator: saveCoordinator) {
            close()
        }
    }

    func checkAndOfferUnlock(lessonID: UUID, studentID: UUID) {
        // Find current lesson
        guard let currentLesson = allLessons.first(where: { $0.id == lessonID }) else { return }

        // Find next lesson using PlanNextLessonService
        guard let nextLesson = PlanNextLessonService.findNextLesson(after: currentLesson, in: allLessons) else {
            return // No next lesson available
        }

        // Check if already unlocked
        let existingLAs = allLessonAssignments.filter { la in
            la.lessonIDUUID == nextLesson.id &&
            la.studentUUIDs.contains(studentID)
        }

        // If already manually unlocked, don't show prompt
        if existingLAs.contains(where: { $0.manuallyUnblocked }) {
            return
        }

        // Show unlock prompt
        viewModel.nextLessonToUnlock = nextLesson
        viewModel.showUnlockNextLessonAlert = true
    }

    func unlockNextLesson() {
        guard let info = unlockNextLessonInfo else { return }

        _ = UnlockNextLessonService.unlockNextLesson(
            after: info.lessonID,
            for: info.studentID,
            modelContext: modelContext,
            lessons: allLessons,
            lessonAssignments: allLessonAssignments
        )

        saveCoordinator.save(modelContext, reason: "Unlocking next lesson")
    }

    func deleteNote(_ note: Note) {
        modelContext.delete(note)
        saveCoordinator.save(modelContext, reason: "Deleting note")

        // Reload the work to refresh the notes list
        viewModel.loadWork(modelContext: modelContext, saveCoordinator: saveCoordinator)
    }

    func studentName() -> String {
        viewModel.relatedStudent?.firstName ?? "Student"
    }

    func lessonTitle() -> String {
        return viewModel.relatedLesson?.name ?? "Lesson"
    }
}
