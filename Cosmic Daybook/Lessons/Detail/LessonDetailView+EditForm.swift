import SwiftUI
import CoreData
import os

// MARK: - Edit Form

extension LessonDetailView {
    var editForm: some View {
        VStack(spacing: AppTheme.Spacing.compact + 2) {
            TextField("Lesson Name", text: $draft.name)
                .textFieldStyle(.roundedBorder)
            HStack(alignment: .top) {
                ComboBoxField(title: "Area", text: $draft.area, options: existingAreas)
                ComboBoxField(title: "Sequence", text: $draft.sequence, options: existingSequences)
            }
            ComboBoxField(title: "Section", text: $draft.section, options: existingSections)

            Picker("Source", selection: $draft.source) {
                ForEach(LessonSource.allCases) { s in
                    Text(s.label).tag(s)
                }
            }
            if draft.source == .personal {
                Picker("Personal Type", selection: $draft.personalKind) {
                    ForEach(PersonalLessonKind.allCases) { k in
                        Text(k.label).tag(k)
                    }
                }
            }

            Picker("Format", selection: $draft.lessonFormat) {
                ForEach(LessonFormat.allCases) { f in
                    Label(f.label, systemImage: f.icon).tag(f)
                }
            }

            if draft.lessonFormat == .story {
                let storyLessons = allLessons.filter { $0.isStory && $0.id != lesson.id }
                Picker("Parent Story", selection: $draft.parentStoryID) {
                    Text("None (this is a main story)").tag(nil as UUID?)
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
                Picker("Requires Practice", selection: $draft.practiceOverride) {
                    ForEach(ProgressionOverride.allCases) { o in
                        Text(o.label).tag(o)
                    }
                }
                Picker("Requires Confirmation", selection: $draft.confirmationOverride) {
                    ForEach(ProgressionOverride.allCases) { o in
                        Text(o.label).tag(o)
                    }
                }
                Text("\"From Group\" uses the sequence's default setting.")
                    .font(AppTheme.ScaledFont.caption)
                    .foregroundStyle(.tertiary)
            }

            // Three-Year View milestone flag
            VStack(alignment: .leading, spacing: AppTheme.Spacing.verySmall) {
                Toggle("Key lesson", isOn: $draft.isKeyLesson)
                Text("Key lessons are the milestones a child's Three-Year View shows by default. "
                     + "The first lesson of every sequence counts as one without being marked.")
                    .font(AppTheme.ScaledFont.caption)
                    .foregroundStyle(.tertiary)
            }

            TextField("Age Range (e.g., 6+, 3-6)", text: $draft.ageRange)
                .textFieldStyle(.roundedBorder)

            VStack(alignment: .leading, spacing: AppTheme.Spacing.verySmall) {
                Text("Purpose / Learning Objective")
                    .font(AppTheme.ScaledFont.calloutSemibold)
                    .foregroundStyle(.secondary)
                TextEditor(text: $draft.purpose)
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
                TextEditor(text: $draft.materials)
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
                            Button("Remove") { removePagesFile() }
                        }
                        Button("Import\u{2026}") { beginPagesImport() }
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
                TextEditor(text: $draft.writeUp)
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
                TextEditor(text: $draft.teacherNotes)
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
                TextEditor(text: $draft.suggestedFollowUpWork)
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
