import SwiftUI
import CoreData
import os

extension LessonDetailCard {
    var editForm: some View {
        VStack(spacing: 12) {
            TextField("CDLesson Name", text: $draftName)
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

            Picker("Format", selection: $draftLessonFormat) {
                ForEach(LessonFormat.allCases) { f in
                    Label(f.label, systemImage: f.icon).tag(f)
                }
            }

            if draftLessonFormat == .story {
                let storyRaw = LessonFormat.story.rawValue
                let storyLessons: [CDLesson] = {
                    let descriptor: NSFetchRequest<CDLesson> = NSFetchRequest(entityName: "CDLesson")
        descriptor.predicate = NSPredicate(format: "lessonFormatRaw == %@", storyRaw as CVarArg)
                    return viewContext.safeFetch(descriptor).filter { $0.id != lesson.id }
                }()
                Picker("Parent Story", selection: $draftParentStoryID) {
                    Text("None (Root Story)").tag(nil as UUID?)
                    ForEach(storyLessons) { story in
                        Text(story.name).tag(story.id as UUID?)
                    }
                }
            }

            TextField("Age Range (e.g., 6+, 3-6)", text: $draftAgeRange)
                .textFieldStyle(.roundedBorder)

            VStack(alignment: .leading, spacing: 6) {
                Text("Purpose / Learning Objective")
                    .font(AppTheme.ScaledFont.calloutSemibold)
                    .foregroundStyle(.secondary)
                TextEditor(text: $draftPurpose)
                    .frame(minHeight: 60)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(UIConstants.OpacityConstants.medium)))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Materials")
                    .font(AppTheme.ScaledFont.calloutSemibold)
                    .foregroundStyle(.secondary)
                Text("Enter one material per line")
                    .font(AppTheme.ScaledFont.caption)
                    .foregroundStyle(.tertiary)
                TextEditor(text: $draftMaterials)
                    .frame(minHeight: 80)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(UIConstants.OpacityConstants.medium)))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Imported Pages File")
                    .font(AppTheme.ScaledFont.calloutSemibold)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
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
                                saveCoordinator.save(viewContext, reason: "Clear Pages link")
                            }
                        }
                        Button("Import\u{2026}") {
                            #if os(macOS)
                            presentMacOpenPanel()
                            #else
                            showingPagesImporter = true
                            #endif
                        }
                    }
                    if let url = resolvedPagesURL {
                        OpenInPagesButton(title: "Open in Pages") { openInPages(url) }
                            .padding(.top, 4)
                    } else {
                        Text("No file selected")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Presentation Notes")
                    .font(AppTheme.ScaledFont.calloutSemibold)
                    .foregroundStyle(.secondary)
                TextEditor(text: $draftWriteUp)
                    .frame(minHeight: 140)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(UIConstants.OpacityConstants.medium)))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Teacher Notes")
                    .font(AppTheme.ScaledFont.calloutSemibold)
                    .foregroundStyle(.secondary)
                TextEditor(text: $draftTeacherNotes)
                    .frame(minHeight: 100)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(UIConstants.OpacityConstants.medium)))
            }

            // Suggested Follow-Up Work (unified)
            VStack(alignment: .leading, spacing: 6) {
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
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(UIConstants.OpacityConstants.medium)))

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
    }
}
