// ParshaSuggestionsDetailView.swift
// Detail view for managing AI-generated album-lesson suggestions for a single parsha.
// Used by This Week's Parsha to drill into the cached suggestions list.

import SwiftUI
import CoreData

struct ParshaSuggestionsDetailView: View {
    let parshaKey: String
    let onChange: () -> Void

    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dependencies) private var dependencies

    @State private var cached: CachedParshaSuggestions?
    @State private var isLoading = false
    @State private var errorMessage: String?

    private var service: ParshaSuggestionService {
        ParshaSuggestionService(mcpClient: dependencies.mcpClient, context: viewContext)
    }

    var body: some View {
        List {
            headerSection
            if let cached, !cached.suggestions.isEmpty {
                Section {
                    ForEach(cached.suggestions) { suggestion in
                        SuggestionRow(
                            suggestion: suggestion,
                            parshaKey: parshaKey,
                            onTagged: handleTagged
                        )
                    }
                } header: {
                    HStack {
                        Text("Suggestions")
                        Spacer()
                        Text("Found \(cached.generatedAt.formatted(.relative(presentation: .named)))")
                            .font(AppTheme.ScaledFont.captionSmall)
                            .foregroundStyle(.secondary)
                    }
                }
            } else if !isLoading && cached != nil {
                Section {
                    Text("No album lessons stood out for this parsha.")
                        .font(AppTheme.ScaledFont.body)
                        .foregroundStyle(.secondary)
                }
            }
            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .font(AppTheme.ScaledFont.body)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle(HebrewParshaService.displayName(forKey: parshaKey))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await generate() }
                } label: {
                    if isLoading {
                        ProgressView()
                    } else {
                        Label(cached == nil ? "Generate" : "Refresh", systemImage: "sparkles")
                    }
                }
                .disabled(isLoading || !AIClientRouter.isAvailable)
            }
        }
        .onAppear { cached = service.cachedSuggestions(forParshaKey: parshaKey) }
    }

    @ViewBuilder
    private var headerSection: some View {
        if let metadata = ParshaMetadataService.metadata(forKey: parshaKey) {
            Section {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.xxsmall) {
                    Text("\(metadata.torahReference) (\(metadata.passageRange))")
                        .font(AppTheme.ScaledFont.body)
                        .foregroundStyle(.primary)
                    Text(metadata.topics.joined(separator: " · "))
                        .font(AppTheme.ScaledFont.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, AppTheme.Spacing.xxsmall)
            }
        }
        if !AIClientRouter.isAvailable {
            Section {
                Label(
                    "Apple Intelligence isn't available on this device, so suggestions are off.",
                    systemImage: "exclamationmark.triangle.fill"
                )
                    .font(AppTheme.ScaledFont.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    private func generate() async {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }
        do {
            let result = try await service.generateSuggestions(forParshaKey: parshaKey)
            cached = result
            onChange()
        } catch {
            errorMessage = AppErrorMessages.aiMessage(
                for: error, fallback: "Couldn't find matching lessons. Try again."
            )
        }
    }

    private func handleTagged() {
        cached = service.cachedSuggestions(forParshaKey: parshaKey)
        onChange()
    }
}

private struct SuggestionRow: View {
    let suggestion: ParshaSuggestion
    let parshaKey: String
    let onTagged: () -> Void

    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dependencies) private var dependencies
    @Environment(SaveCoordinator.self) private var saveCoordinator

    @State private var didTag = false

    /// From the workspace's live lesson catalog: a lookup, not a fetch.
    private var lesson: CDLesson? {
        dependencies.lessonCatalog.lesson(id: suggestion.lessonID, in: viewContext)
    }

    var body: some View {
        // Looked up once per pass rather than once per use below.
        let lesson = self.lesson
        let isAlreadyTagged = lesson?.parshaKey == parshaKey
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xsmall) {
            HStack {
                if let lesson {
                    NavigationLink(value: lesson) {
                        Text(lesson.name.isEmpty ? "Untitled Lesson" : lesson.name)
                            .font(AppTheme.ScaledFont.bodySemibold)
                            .foregroundStyle(Color.accentColor)
                    }
                    .buttonStyle(.plain)
                } else {
                    Text("Lesson no longer exists")
                        .font(AppTheme.ScaledFont.bodySemibold)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if isAlreadyTagged || didTag {
                    Label("Tagged", systemImage: "checkmark.circle.fill")
                        .labelStyle(.iconOnly)
                        .foregroundStyle(Color.green)
                } else if lesson != nil {
                    Button {
                        tagLesson()
                    } label: {
                        Label("Tag", systemImage: "tag")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            Text(suggestion.reasoning)
                .font(AppTheme.ScaledFont.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, AppTheme.Spacing.xxsmall)
    }

    private func tagLesson() {
        guard let lesson else { return }
        lesson.parshaKey = parshaKey
        let repo = LessonRepository(context: viewContext, saveCoordinator: saveCoordinator)
        _ = repo.save(reason: "Tag AI-suggested parsha lesson")
        didTag = true
        onTagged()
    }
}
