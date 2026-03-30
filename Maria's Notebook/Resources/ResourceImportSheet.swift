import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import OSLog

/// Sheet for importing a PDF into the Resource Library.
struct ResourceImportSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(sort: [SortDescriptor(\Lesson.name)]) private var allLessons: [Lesson]

    @State private var title = ""
    @State private var selectedCategory: ResourceCategory = .other
    @State private var descriptionText = ""
    @State private var selectedTags: [String] = []
    @State private var selectedLessonIDs: Set<UUID> = []
    @State private var selectedSubjects: Set<String> = []
    @State private var selectedFileURL: URL?
    @State private var isShowingFilePicker = false
    @State private var importError: String?

    private static let logger = Logger.resources

    private var availableSubjects: [String] {
        let unique = Set(allLessons.map { $0.subject.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
        return Array(unique).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("File") {
                    if let url = selectedFileURL {
                        HStack {
                            Image(systemName: "doc.fill")
                                .foregroundStyle(Color.accentColor)
                            Text(url.lastPathComponent)
                                .lineLimit(1)
                            Spacer()
                            Button("Change") {
                                isShowingFilePicker = true
                            }
                            .font(.caption)
                        }
                    } else {
                        Button {
                            isShowingFilePicker = true
                        } label: {
                            Label("Choose PDF File", systemImage: "doc.badge.plus")
                        }
                    }
                }

                Section("Details") {
                    TextField("Title", text: $title)

                    Picker("Category", selection: $selectedCategory) {
                        ForEach(ResourceCategory.allCases) { category in
                            Label(category.rawValue, systemImage: category.icon)
                                .tag(category)
                        }
                    }
                }

                Section("Notes") {
                    TextField("Description or usage notes", text: $descriptionText, axis: .vertical)
                        .lineLimit(3...6)
                }

                Section("Organization") {
                    NavigationLink {
                        ResourceTagPicker(selectedTags: $selectedTags)
                    } label: {
                        HStack {
                            Label("Tags", systemImage: "tag")
                            Spacer()
                            if selectedTags.isEmpty {
                                Text("None")
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("\(selectedTags.count) tag\(selectedTags.count == 1 ? "" : "s")")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    NavigationLink {
                        ResourceSubjectPicker(
                            availableSubjects: availableSubjects,
                            selectedSubjects: $selectedSubjects
                        )
                    } label: {
                        HStack {
                            Label("Subjects", systemImage: "graduationcap")
                            Spacer()
                            if selectedSubjects.isEmpty {
                                Text("None")
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("\(selectedSubjects.count)")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    NavigationLink {
                        ResourceLessonPicker(
                            allLessons: allLessons,
                            selectedLessonIDs: $selectedLessonIDs
                        )
                    } label: {
                        HStack {
                            Label("Lessons", systemImage: "book")
                            Spacer()
                            if selectedLessonIDs.isEmpty {
                                Text("None")
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("\(selectedLessonIDs.count) linked")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                if let importError {
                    Section {
                        Text(importError)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("Add Resource")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveResource()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || selectedFileURL == nil)
                }
            }
            .fileImporter(
                isPresented: $isShowingFilePicker,
                allowedContentTypes: [UTType.pdf],
                allowsMultipleSelection: false
            ) { result in
                handleFileSelection(result)
            }
        }
        #if os(macOS)
        .frame(minWidth: 450, minHeight: 400)
        #endif
    }

    // MARK: - File Handling

    private func handleFileSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }

            let didStartAccessing = url.startAccessingSecurityScopedResource()
            defer {
                if didStartAccessing {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            selectedFileURL = url

            // Auto-fill title from filename if empty
            if title.isEmpty {
                let stem = url.deletingPathExtension().lastPathComponent
                title = stem
            }

        case .failure(let error):
            Self.logger.warning("File picker failed: \(error, privacy: .public)")
            importError = "Failed to select file: \(error.localizedDescription)"
        }
    }

    // MARK: - Save

    private func saveResource() {
        guard let sourceURL = selectedFileURL else { return }
        let trimmedTitle = title.trimmingCharacters(in: .whitespaces)
        guard !trimmedTitle.isEmpty else { return }

        let didStartAccessing = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let resourceID = UUID()

            // Import file to managed storage
            let (destURL, relativePath) = try ResourceFileStorage.importFile(
                from: sourceURL,
                resourceID: resourceID,
                title: trimmedTitle,
                category: selectedCategory
            )

            // Get file size
            let fileAttributes = try FileManager.default.attributesOfItem(atPath: destURL.path)
            let fileSize = (fileAttributes[.size] as? Int64) ?? 0

            // Create bookmark
            let bookmark = try ResourceFileStorage.makeBookmark(for: destURL)

            // Generate thumbnail
            let thumbnail = ResourceThumbnailGenerator.generateThumbnail(from: destURL)

            // Build linked IDs
            let lessonIDsString = selectedLessonIDs.map(\.uuidString).sorted().joined(separator: ",")
            let subjectsString = selectedSubjects.sorted().joined(separator: ",")

            // Create resource
            let repo = ResourceRepository(context: modelContext)
            repo.createResource(
                title: trimmedTitle,
                category: selectedCategory,
                descriptionText: descriptionText.trimmingCharacters(in: .whitespaces),
                fileBookmark: bookmark,
                fileRelativePath: relativePath,
                fileSizeBytes: fileSize,
                thumbnailData: thumbnail,
                tags: selectedTags,
                linkedLessonIDs: lessonIDsString,
                linkedSubjects: subjectsString
            )
            modelContext.safeSave()

            dismiss()
        } catch {
            Self.logger.error("Failed to import resource: \(error, privacy: .public)")
            importError = "Import failed: \(error.localizedDescription)"
        }
    }
}

#Preview {
    ResourceImportSheet()
        .previewEnvironment()
}
