// ThisWeeksParshaView.swift
// The parsha screen. Opens on this week's parsha: its name, Shabbat date, passages,
// topics, related lessons, previous presentations and the coming weeks. The year's
// Shabbatot (`ParshaYearList`) are its index: a column beside the week on a Mac or iPad,
// a list behind the toolbar button on a phone.

import SwiftUI
import CoreData

struct ThisWeeksParshaView: View {
    /// The Shabbat shown; nil is this week.
    @State private var selectedShabbat: Date?
    @State private var showingYearList: Bool

    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    /// `showsYearList` opens the year list over the week at first on a phone
    /// (the Parsha Calendar item).
    init(showsYearList: Bool = false) {
        _showingYearList = State(initialValue: showsYearList)
    }

    private var isCompact: Bool {
        #if os(iOS)
        horizontalSizeClass == .compact
        #else
        false
        #endif
    }

    var body: some View {
        if isCompact {
            phoneLayout
        } else {
            HStack(spacing: 0) {
                NavigationStack {
                    ParshaYearList(selection: $selectedShabbat)
                        .navigationTitle("Parsha Calendar")
                }
                .frame(width: 300)
                Divider()
                weekStack
            }
        }
    }

    /// The week in a stack of its own, rebuilt when another Shabbat is picked so
    /// a lesson left open from the last one doesn't stay on top.
    private var weekStack: some View {
        PageNavigationStack {
            ParshaWeekPage(forShabbat: selectedShabbat)
        }
        .id(selectedShabbat)
    }

    private var phoneLayout: some View {
        PageNavigationStack {
            ParshaWeekPage(forShabbat: selectedShabbat)
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            showingYearList = true
                        } label: {
                            Label("Year", systemImage: "list.bullet")
                        }
                        .accessibilityLabel("Choose a Shabbat from the year")
                    }
                }
        }
        .id(selectedShabbat)
        .sheet(isPresented: $showingYearList) {
            NavigationStack {
                ParshaYearList(selection: $selectedShabbat)
                    .navigationTitle("Parsha Calendar")
                    #if os(iOS)
                    .navigationBarTitleDisplayMode(.inline)
                    #endif
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showingYearList = false }
                        }
                    }
            }
            .onChange(of: selectedShabbat) { showingYearList = false }
        }
    }
}

/// One Shabbat's page: `forShabbat`, or this week's when nil.
private struct ParshaWeekPage: View {
    let forShabbat: Date?

    private var shabbat: Date {
        HebrewParshaService.shabbatOfWeek(containing: forShabbat ?? Date())
    }

    private var parshaKey: String? {
        HebrewParshaService.parshaKey(forShabbat: shabbat)
    }

    /// Whether this is the week the guide is in, however it was picked.
    private var isCurrentWeek: Bool {
        forShabbat == nil || HebrewParshaService.gregorian.isDate(
            shabbat, inSameDayAs: HebrewParshaService.shabbatOfWeek(containing: Date())
        )
    }

    private var navigationTitle: String {
        if isCurrentWeek {
            return "This Week’s Parsha"
        }
        return parshaKey.flatMap { HebrewParshaService.displayName(forKey: $0) } ?? "Parsha"
    }

    var body: some View {
        Group {
            if let key = parshaKey {
                ParshaContentList(parshaKey: key, shabbat: shabbat, isCurrentWeek: isCurrentWeek)
            } else {
                noParshaState
            }
        }
        .navigationTitle(navigationTitle)
        .navigationDestination(for: CDLesson.self) { lesson in
            LessonDetailView(lesson: lesson, onSave: { _ in })
        }
        .navigationDestination(for: Date.self) { date in
            ParshaWeekPage(forShabbat: date)
        }
        .navigationDestination(for: ParshaSuggestionsNav.self) { nav in
            ParshaSuggestionsDetailView(parshaKey: nav.parshaKey) { /* refresh handled by view */ }
        }
    }

    private var noParshaState: some View {
        let festival = HebrewParshaService.displacingFestivalName(forShabbat: shabbat)
        return ContentUnavailableView {
            Label(festival.map { "Shabbat \($0)" } ?? "Weekly reading not shown", systemImage: "book.closed")
        } description: {
            if let festival {
                Text(
                    "\(shabbat.formatted(date: .long, time: .omitted)) coincides with \(festival), " +
                    "so a festival reading replaces the weekly parsha."
                )
            } else {
                Text("The weekly reading for \(shabbat.formatted(date: .long, time: .omitted)) isn't shown here.")
            }
        }
    }
}

private struct ParshaContentList: View {
    let parshaKey: String
    let shabbat: Date
    let isCurrentWeek: Bool

    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dependencies) private var dependencies

    @FetchRequest private var lessons: FetchedResults<CDLesson>

    @State private var showingNewLesson = false
    @State private var showingTagPicker = false
    @State private var lessonToSchedule: CDLesson?
    @State private var cachedSuggestions: CachedParshaSuggestions?
    @State private var isGeneratingSuggestions = false
    @State private var suggestionError: String?

    init(parshaKey: String, shabbat: Date, isCurrentWeek: Bool) {
        self.parshaKey = parshaKey
        self.shabbat = shabbat
        self.isCurrentWeek = isCurrentWeek
        _lessons = FetchRequest(
            sortDescriptors: [NSSortDescriptor(keyPath: \CDLesson.name, ascending: true)],
            predicate: HebrewParshaService.lessonsPredicate(forParshaKey: parshaKey)
        )
    }

    private var displayName: String {
        HebrewParshaService.displayName(forKey: parshaKey)
    }

    private var metadata: ParshaMetadata? {
        ParshaMetadataService.metadata(forKey: parshaKey)
    }

    private var specialShabbat: SpecialShabbat? {
        SpecialShabbatService.specialShabbat(forShabbat: shabbat)
    }

    private var previousPresentations: [CDLessonAssignment] {
        lessons
            .flatMap { $0.lessonAssignments }
            .filter { $0.state == .presented && $0.presentedAt != nil }
            .sorted { ($0.presentedAt ?? .distantPast) > ($1.presentedAt ?? .distantPast) }
    }

    private var presentationsByYear: [(year: Int, items: [CDLessonAssignment])] {
        let grouped = Dictionary(grouping: previousPresentations) { assignment in
            AppCalendar.shared.component(.year, from: assignment.presentedAt ?? .distantPast)
        }
        return grouped
            .map { (year: $0.key, items: $0.value) }
            .sorted { $0.year > $1.year }
    }

    private struct UpcomingEntry: Identifiable {
        let date: Date
        let parshaKey: String?
        let festivalName: String?
        var id: Date { date }
    }

    private var upcomingShabbatot: [UpcomingEntry] {
        let calendar = HebrewParshaService.gregorian
        var result: [UpcomingEntry] = []
        for offset in 1...4 {
            guard let next = calendar.date(byAdding: .day, value: 7 * offset, to: shabbat) else {
                continue
            }
            let key = HebrewParshaService.parshaKey(forShabbat: next)
            let festival = HebrewParshaService.displacingFestivalName(forShabbat: next)
            result.append(UpcomingEntry(date: next, parshaKey: key, festivalName: festival))
        }
        return result
    }

    private func copyParshaName() {
        Pasteboard.copy(displayName)
    }

    var body: some View {
        List {
            if let special = specialShabbat {
                specialShabbatBanner(special: special)
            }
            headerSection
            if let metadata {
                passagesSection(metadata: metadata)
                topicsSection(metadata: metadata)
            }
            lessonsSection
            suggestionsSection
            if !previousPresentations.isEmpty {
                previousPresentationsSection
            }
            if isCurrentWeek && !upcomingShabbatot.isEmpty {
                upcomingSection
            }
        }
        .onAppear {
            cachedSuggestions = ParshaSuggestionService(mcpClient: dependencies.mcpClient, context: viewContext)
                .cachedSuggestions(forParshaKey: parshaKey)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        showingNewLesson = true
                    } label: {
                        Label("New Lesson for \(displayName)", systemImage: "plus")
                    }
                    Button {
                        showingTagPicker = true
                    } label: {
                        Label("Tag an Existing Lesson…", systemImage: "tag")
                    }
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingNewLesson) {
            ParshaLessonEditorSheet(parshaKey: parshaKey, existingLesson: nil)
        }
        .sheet(isPresented: $showingTagPicker) {
            TagLessonToParshaSheet(parshaKey: parshaKey) {
                showingTagPicker = false
            }
        }
        .sheet(item: $lessonToSchedule) { lesson in
            ScheduleParshaLessonSheet(lesson: lesson) {
                lessonToSchedule = nil
            }
        }
    }

    private func specialShabbatBanner(special: SpecialShabbat) -> some View {
        Section {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xsmall) {
                Label(special.displayName, systemImage: "star.circle.fill")
                    .font(AppTheme.ScaledFont.bodySemibold)
                    .foregroundStyle(Color.accentColor)
                if let reading = special.specialReading {
                    Text(reading)
                        .font(AppTheme.ScaledFont.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, AppTheme.Spacing.xxsmall)
        }
    }

    private var headerSection: some View {
        Section {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xsmall) {
                Text(displayName)
                    .font(AppTheme.ScaledFont.titleLarge)
                    .foregroundStyle(.primary)
                Text("Shabbat \(shabbat.formatted(date: .long, time: .omitted))")
                    .font(AppTheme.ScaledFont.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, AppTheme.Spacing.xsmall)
            .contextMenu {
                Button {
                    copyParshaName()
                } label: {
                    Label("Copy Name", systemImage: "doc.on.doc")
                }
            }
        }
    }

    private func passagesSection(metadata: ParshaMetadata) -> some View {
        Section("Passages") {
            Text("\(metadata.torahReference) (\(metadata.passageRange))")
                .font(AppTheme.ScaledFont.body)
                .foregroundStyle(.primary)
        }
    }

    @ViewBuilder
    private func topicsSection(metadata: ParshaMetadata) -> some View {
        if !metadata.topics.isEmpty {
            Section("Topics") {
                ForEach(metadata.topics, id: \.self) { topic in
                    Label(topic, systemImage: "circle.fill")
                        .labelStyle(TopicBulletLabelStyle())
                        .font(AppTheme.ScaledFont.body)
                }
            }
        }
    }

    @ViewBuilder
    private var lessonsSection: some View {
        Section("Related Lessons") {
            if lessons.isEmpty {
                emptyLessonsRow
            } else {
                ForEach(lessons, id: \.id) { lesson in
                    ParshaLessonRow(lesson: lesson) {
                        lessonToSchedule = lesson
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var suggestionsSection: some View {
        Section {
            if let cached = cachedSuggestions, !cached.suggestions.isEmpty {
                ForEach(cached.suggestions.prefix(3)) { suggestion in
                    InlineSuggestionRow(suggestion: suggestion, parshaKey: parshaKey)
                }
                NavigationLink(value: ParshaSuggestionsNav(parshaKey: parshaKey)) {
                    Text(cached.suggestions.count > 3
                         ? "View all \(cached.suggestions.count) matches"
                         : "Manage suggestions")
                        .font(AppTheme.ScaledFont.captionSemibold)
                        .foregroundStyle(Color.accentColor)
                }
            } else {
                generateSuggestionsRow
            }
        } header: {
            HStack {
                Label("Album Matches (AI)", systemImage: "sparkles")
                Spacer()
                if let cached = cachedSuggestions {
                    Text("Found \(cached.generatedAt.formatted(.relative(presentation: .named)))")
                        .font(AppTheme.ScaledFont.captionSmall)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var generateSuggestionsRow: some View {
        if AIClientRouter.isAvailable {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xsmall) {
                Text("Let AI find lessons in your albums that connect to \(displayName).")
                    .font(AppTheme.ScaledFont.caption)
                    .foregroundStyle(.secondary)
                Button {
                    Task { await generateSuggestions() }
                } label: {
                    if isGeneratingSuggestions {
                        ProgressView()
                    } else {
                        Label("Find AI Matches", systemImage: "sparkles")
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isGeneratingSuggestions)
                if let suggestionError {
                    Text(suggestionError)
                        .font(AppTheme.ScaledFont.caption)
                        .foregroundStyle(.red)
                }
            }
            .padding(.vertical, AppTheme.Spacing.xxsmall)
        } else {
            Label(
                AIClientRouter.unavailabilityNotice("suggestions are off"),
                systemImage: "exclamationmark.triangle.fill"
            )
                .font(AppTheme.ScaledFont.caption)
                .foregroundStyle(.orange)
        }
    }

    private func generateSuggestions() async {
        suggestionError = nil
        isGeneratingSuggestions = true
        defer { isGeneratingSuggestions = false }
        let service = ParshaSuggestionService(mcpClient: dependencies.mcpClient, context: viewContext)
        do {
            let result = try await service.generateSuggestions(forParshaKey: parshaKey)
            cachedSuggestions = result
        } catch {
            suggestionError = AppErrorMessages.aiMessage(
                for: error, fallback: "Couldn't find matching lessons. Try again."
            )
        }
    }

    private var emptyLessonsRow: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
            Text("No lessons tagged to \(displayName) yet.")
                .font(AppTheme.ScaledFont.body)
                .foregroundStyle(.secondary)
            HStack(spacing: AppTheme.Spacing.small) {
                Button {
                    showingNewLesson = true
                } label: {
                    Label("New Lesson", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Button {
                    showingTagPicker = true
                } label: {
                    Label("Tag Existing", systemImage: "tag")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.vertical, AppTheme.Spacing.xsmall)
    }

    private var previousPresentationsSection: some View {
        Section("Previous Presentations") {
            ForEach(presentationsByYear, id: \.year) { group in
                DisclosureGroup {
                    ForEach(group.items, id: \.id) { assignment in
                        PreviousPresentationRow(assignment: assignment)
                    }
                } label: {
                    HStack {
                        Text(String(group.year))
                            .font(AppTheme.ScaledFont.bodySemibold)
                        Spacer()
                        Text("\(group.items.count)")
                            .font(AppTheme.ScaledFont.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var upcomingSection: some View {
        Section("Upcoming") {
            ForEach(upcomingShabbatot) { entry in
                NavigationLink(value: entry.date) {
                    UpcomingParshaRow(
                        date: entry.date,
                        parshaKey: entry.parshaKey,
                        festivalName: entry.festivalName
                    )
                }
            }
        }
    }
}

private struct ParshaLessonRow: View {
    @ObservedObject var lesson: CDLesson
    let onSchedule: () -> Void

    private var subtitle: String {
        var parts: [String] = []
        let age = lesson.ageRange.trimmed()
        if !age.isEmpty {
            parts.append("Ages \(age)")
        }
        if let source = lesson.derivedFromLesson {
            parts.append("from \(source.name)")
        }
        return parts.joined(separator: " \u{00B7} ")
    }

    var body: some View {
        HStack(alignment: .center, spacing: AppTheme.Spacing.small) {
            NavigationLink(value: lesson) {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.xxsmall) {
                    Text(lesson.name.isEmpty ? "Untitled Lesson" : lesson.name)
                        .font(AppTheme.ScaledFont.bodySemibold)
                        .foregroundStyle(.primary)
                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .font(AppTheme.ScaledFont.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            Button(action: onSchedule) {
                Label("Add to Presentations", systemImage: "calendar.badge.plus")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("Add to Presentations")
        }
        .padding(.vertical, AppTheme.Spacing.xxsmall)
    }
}
