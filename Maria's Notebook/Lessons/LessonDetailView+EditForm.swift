import SwiftUI
import os

// MARK: - Edit Form

extension LessonDetailView {
    var editForm: some View {
        VStack(spacing: AppTheme.Spacing.compact + 2) {
            TextField("Lesson Name", text: $draftName)
                .textFieldStyle(.roundedBorder)
            HStack {
                TextField("Subject", text: $draftSubject)
                    .textFieldStyle(.roundedBorder)
                TextField("Group", text: $draftGroup)
                    .textFieldStyle(.roundedBorder)
            }
            TextField("Subheading", text: $draftSubheading)
                .textFieldStyle(.roundedBorder)

            Picker("Source", selection: $draftSource) {
                ForEach(LessonSource.allCases) { s in
                    Text(s.label).tag(s)
                }
            }
            if draftSource == .personal {
                Picker("Personal Type", selection: $draftPersonalKind) {
                    ForEach(PersonalLessonKind.allCases) { k in
                        Text(k.label).tag(k)
                    }
                }
            }

            TextField("Age Range (e.g., 6+, 3-6)", text: $draftAgeRange)
                .textFieldStyle(.roundedBorder)

            VStack(alignment: .leading, spacing: AppTheme.Spacing.verySmall) {
                Text("Purpose / Learning Objective")
                    .font(AppTheme.ScaledFont.calloutSemibold)
                    .foregroundStyle(.secondary)
                TextEditor(text: $draftPurpose)
                    .frame(minHeight: 60)
                    .overlay(
                        RoundedRectangle(cornerRadius: UIConstants.CornerRadius.medium)
                            .stroke(Color.primary.opacity(UIConstants.OpacityConstants.medium))
                    )
            }

            VStack(alignment: .leading, spacing: AppTheme.Spacing.verySmall) {
                Text("Materials")
                    .font(AppTheme.ScaledFont.calloutSemibold)
                    .foregroundStyle(.secondary)
                Text("Enter one material per line")
                    .font(AppTheme.ScaledFont.caption)
                    .foregroundStyle(.tertiary)
                TextEditor(text: $draftMaterials)
                    .frame(minHeight: 80)
                    .overlay(
                        RoundedRectangle(cornerRadius: UIConstants.CornerRadius.medium)
                            .stroke(Color.primary.opacity(UIConstants.OpacityConstants.medium))
                    )
            }

            VStack(alignment: .leading, spacing: AppTheme.Spacing.verySmall) {
                Text("Imported Pages File")
                    .font(AppTheme.ScaledFont.calloutSemibold)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
                    HStack(spacing: AppTheme.Spacing.small) {
                        if resolvedPagesURL != nil {
                            Button("Remove") {
                                if let url = resolvedPagesURL {
                                    do {
                                        try LessonFileStorage.deleteIfManaged(url)
                                    } catch {
                                        Self.logger.warning("Failed to delete managed file: \(error)")
                                    }
                                }
                                lesson.pagesFileBookmark = nil
                                lesson.pagesFileRelativePath = nil
                                resolvedPagesURL = nil
                                previousManagedURL = nil
                                _ = saveCoordinator.save(modelContext, reason: "Remove lesson Pages file")
                            }
                        }
                        Button("Import\u{2026}") { showingPagesImporter = true }
                    }
                    if let url = resolvedPagesURL {
                        OpenInPagesButton(title: "Open in Pages") { openInPages(url) }
                            .padding(.top, AppTheme.Spacing.xsmall)
                    } else {
                        Text("No file selected")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            VStack(alignment: .leading, spacing: AppTheme.Spacing.verySmall) {
                Text("Notes")
                    .font(AppTheme.ScaledFont.calloutSemibold)
                    .foregroundStyle(.secondary)
                TextEditor(text: $draftWriteUp)
                    .frame(minHeight: 160)
                    .overlay(
                        RoundedRectangle(cornerRadius: UIConstants.CornerRadius.medium)
                            .stroke(Color.primary.opacity(UIConstants.OpacityConstants.medium))
                    )
            }

            VStack(alignment: .leading, spacing: AppTheme.Spacing.verySmall) {
                Text("Teacher Notes")
                    .font(AppTheme.ScaledFont.calloutSemibold)
                    .foregroundStyle(.secondary)
                TextEditor(text: $draftTeacherNotes)
                    .frame(minHeight: 100)
                    .overlay(
                        RoundedRectangle(cornerRadius: UIConstants.CornerRadius.medium)
                            .stroke(Color.primary.opacity(UIConstants.OpacityConstants.medium))
                    )
            }

            VStack(alignment: .leading, spacing: AppTheme.Spacing.verySmall) {
                Text("Suggested Follow-Up Work")
                    .font(AppTheme.ScaledFont.calloutSemibold)
                    .foregroundStyle(.secondary)
                Text("Enter one suggestion per line")
                    .font(AppTheme.ScaledFont.caption)
                    .foregroundStyle(.tertiary)
                TextEditor(text: $draftSuggestedFollowUpWork)
                    .frame(minHeight: 120)
                    .overlay(
                        RoundedRectangle(cornerRadius: UIConstants.CornerRadius.medium)
                            .stroke(Color.primary.opacity(UIConstants.OpacityConstants.medium))
                    )
            }

            // Exercises Editor
            VStack(alignment: .leading, spacing: AppTheme.Spacing.verySmall) {
                HStack {
                    Text("Exercises")
                        .font(AppTheme.ScaledFont.calloutSemibold)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        editingExercise = nil
                        showingExerciseEditor = true
                    } label: {
                        Label("Add", systemImage: "plus.circle")
                    }
                    .buttonStyle(.bordered)
                }

                if lesson.sortedExercises.isEmpty {
                    Text("No exercises yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(lesson.sortedExercises) { exercise in
                        LessonExerciseRow(exercise: exercise)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                editingExercise = exercise
                                showingExerciseEditor = true
                            }
                    }
                }
            }
            .sheet(isPresented: $showingExerciseEditor) {
                LessonExerciseEditorSheet(
                    lesson: lesson,
                    existingExercise: editingExercise,
                    onSave: {}
                )
            }
        }
        .padding(.horizontal, AppTheme.Spacing.small)
    }
}
