// ParshaAlbumSuggestionsView.swift
// Top-level browser for AI-suggested album-lesson matches across all parshas.
// Each parsha shows whether suggestions are cached; tapping opens a detail view
// where you can generate (or refresh) and tag matches inline.

import SwiftUI
import CoreData

struct ParshaAlbumSuggestionsView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dependencies) private var dependencies

    @State private var cachedSuggestionsByKey: [String: CachedParshaSuggestions] = [:]
    @State private var selectedParshaKey: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if !AnthropicAPIClient.hasAPIKey() {
                        apiKeyMissingNotice
                    }
                    Text("AI scans your album lessons and suggests which ones thematically connect to each parsha — useful for finding non-obvious links beyond manual tagging.")
                        .font(AppTheme.ScaledFont.caption)
                        .foregroundStyle(.secondary)
                }
                Section {
                    ForEach(HebrewParshaService.allParshaKeys, id: \.self) { key in
                        NavigationLink(value: key) {
                            ParshaSuggestionsListRow(
                                parshaKey: key,
                                suggestionCount: cachedSuggestionsByKey[key]?.suggestions.count ?? 0,
                                generatedAt: cachedSuggestionsByKey[key]?.generatedAt
                            )
                        }
                    }
                }
            }
            .navigationTitle("Album Matches")
            .onAppear { reloadCache() }
            .navigationDestination(for: String.self) { key in
                ParshaSuggestionsDetailView(parshaKey: key) {
                    reloadCache()
                }
            }
            .navigationDestination(for: CDLesson.self) { lesson in
                LessonDetailView(lesson: lesson, onSave: { _ in })
            }
        }
    }

    private var apiKeyMissingNotice: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xsmall) {
            Label("AI not configured", systemImage: "exclamationmark.triangle.fill")
                .font(AppTheme.ScaledFont.bodySemibold)
                .foregroundStyle(.orange)
            Text("Add an Anthropic API key in Settings → AI to enable suggestions.")
                .font(AppTheme.ScaledFont.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, AppTheme.Spacing.xxsmall)
    }

    private func reloadCache() {
        cachedSuggestionsByKey = ParshaSuggestionService.allCachedSuggestions()
    }
}

private struct ParshaSuggestionsListRow: View {
    let parshaKey: String
    let suggestionCount: Int
    let generatedAt: Date?

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xxsmall) {
                Text(HebrewParshaService.displayName(forKey: parshaKey))
                    .font(AppTheme.ScaledFont.bodySemibold)
                    .foregroundStyle(.primary)
                if let generatedAt {
                    Text("\(suggestionCount) suggestion\(suggestionCount == 1 ? "" : "s") · \(generatedAt.formatted(date: .abbreviated, time: .omitted))")
                        .font(AppTheme.ScaledFont.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("No suggestions yet")
                        .font(AppTheme.ScaledFont.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if suggestionCount > 0 {
                Image(systemName: "sparkles")
                    .foregroundStyle(Color.accentColor)
            }
        }
        .padding(.vertical, AppTheme.Spacing.xxsmall)
    }
}

struct ParshaSuggestionsDetailView: View {
    let parshaKey: String
    let onChange: () -> Void

    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dependencies) private var dependencies
    @Environment(SaveCoordinator.self) private var saveCoordinator

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
                        Text("Generated \(cached.generatedAt.formatted(.relative(presentation: .named)))")
                            .font(AppTheme.ScaledFont.captionSmall)
                            .foregroundStyle(.secondary)
                    }
                }
            } else if !isLoading && cached != nil {
                Section {
                    Text("AI did not find any strong album-lesson matches for this parsha.")
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
                .disabled(isLoading || !AnthropicAPIClient.hasAPIKey())
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
        if !AnthropicAPIClient.hasAPIKey() {
            Section {
                Label("Add an Anthropic API key in Settings → AI to enable suggestions.", systemImage: "exclamationmark.triangle.fill")
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
            errorMessage = error.localizedDescription
        }
    }

    private func handleTagged() {
        // Re-read cache and refresh
        cached = service.cachedSuggestions(forParshaKey: parshaKey)
        onChange()
    }
}

struct SuggestionRow: View {
    let suggestion: ParshaSuggestion
    let parshaKey: String
    let onTagged: () -> Void

    @Environment(\.managedObjectContext) private var viewContext
    @Environment(SaveCoordinator.self) private var saveCoordinator

    @State private var didTag = false

    private var lesson: CDLesson? {
        let req = CDFetchRequest(CDLesson.self)
        req.predicate = NSPredicate(format: "id == %@", suggestion.lessonID.uuidString)
        req.fetchLimit = 1
        return viewContext.safeFetchFirst(req)
    }

    private var isAlreadyTagged: Bool {
        lesson?.parshaKey == parshaKey
    }

    var body: some View {
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
