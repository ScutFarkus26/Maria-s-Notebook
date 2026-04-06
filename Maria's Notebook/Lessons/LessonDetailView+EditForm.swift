import SwiftUI
import CoreData
import os

// MARK: - Edit Form

extension LessonDetailView {
    var editForm: some View {
        VStack(spacing: AppTheme.Spacing.compact + 2) {
            TextField("CDLesson Name", text: $draftName)
                .textFieldStyle(.roundedBorder)
            HStack(alignment: .top) {
                ComboBoxField(title: "Subject", text: $draftSubject, options: existingSubjects)
                ComboBoxField(title: "Group", text: $draftGroup, options: existingGroups)
            }
            ComboBoxField(title: "Subheading", text: $draftSubheading, options: existingSubheadings)

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

            Picker("Format", selection: $draftLessonFormat) {
                ForEach(LessonFormat.allCases) { f in
                    Label(f.label, systemImage: f.icon).tag(f)
                }
            }

            if draftLessonFormat == .story {
                let storyLessons = allLessons.filter { $0.isStory && $0.id != lesson.id }
                Picker("Parent Story", selection: $draftParentStoryID) {
                    Text("None (Root Story)").tag(nil as UUID?)
                    ForEach(storyLessons) { story in
                        Text(story.name).tag(story.id as UUID?)
                    }
                }
            }

            // Progression rule overrides
            VStack(alignment: .leading, spacing: AppTheme.Spacing.verySmall) {
                Text("Progression Rules")
                    .font(AppTheme.ScaledFont.calloutSemibold)
                    .foregroundStyle(.secondary)
                Picker("Requires Practice", selection: $draftPracticeOverride) {
                    ForEach(ProgressionOverride.allCases) { o in
                        Text(o.label).tag(o)
                    }
                }
                Picker("Requires Confirmation", selection: $draftConfirmationOverride) {
                    ForEach(ProgressionOverride.allCases) { o in
                        Text(o.label).tag(o)
                    }
                }
                Text("\"From Group\" uses the group's default setting.")
                    .font(AppTheme.ScaledFont.caption)
                    .foregroundStyle(.tertiary)
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
                                saveCoordinator.save(viewContext, reason: "Remove lesson Pages file")
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

            // Suggested Follow-Up Work (unified)
            VStack(alignment: .leading, spacing: AppTheme.Spacing.verySmall) {
                HStack {
                    Text("Suggested Follow-Up Work")
                        .font(AppTheme.ScaledFont.calloutSemibold)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        editingSampleWork = nil
                        showingSampleWorkEditor = true
                    } label: {
                        Label("Add Work with Steps", systemImage: "plus.circle")
                    }
                    .buttonStyle(.bordered)
                }
                Text("Enter one suggestion per line")
                    .font(AppTheme.ScaledFont.caption)
                    .foregroundStyle(.tertiary)
                TextEditor(text: $draftSuggestedFollowUpWork)
                    .frame(minHeight: 80)
                    .overlay(
                        RoundedRectangle(cornerRadius: UIConstants.CornerRadius.medium)
                            .stroke(Color.primary.opacity(UIConstants.OpacityConstants.medium))
                    )

                // Structured sample works (with steps)
                ForEach(lesson.orderedSampleWorks) { sw in
                    SampleWorkRow(sampleWork: sw)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            editingSampleWork = sw
                            showingSampleWorkEditor = true
                        }
                }
            }
            .sheet(isPresented: $showingSampleWorkEditor) {
                SampleWorkEditorSheet(
                    lesson: lesson,
                    existingSampleWork: editingSampleWork,
                    onSave: {}
                )
            }
        }
        .padding(.horizontal, AppTheme.Spacing.small)
    }
}
