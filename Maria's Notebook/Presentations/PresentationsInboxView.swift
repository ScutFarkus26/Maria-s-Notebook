// PresentationsInboxView.swift
// Inbox section extracted from PresentationsView

import SwiftUI
import CoreData
import UniformTypeIdentifiers
import OSLog

struct PresentationsInboxView: View {
    private static let logger = Logger.presentations
    let readyLessons: [CDLessonAssignment]
    let blockedLessons: [CDLessonAssignment]
    /// Per-assignment blocking results with per-student readiness.
    let blockingResults: [UUID: BlockingAlgorithmEngine.BlockingCheckResult]
    let getBlockingWork: (CDLessonAssignment) -> [UUID: CDWorkModel]
    let filteredSnapshot: (CDLessonAssignment) -> LessonAssignmentSnapshot
    let missWindow: PresentationsMissWindow
    @Binding var missWindowRaw: String
    
    // MODERN: Navigation coordinator replaces scattered @Binding vars
    let coordinator: PresentationsCoordinator

    // Pass cached data from parent to avoid duplicate queries
    let cachedLessons: [CDLesson]
    let cachedStudents: [CDStudent]

    // Days since last lesson for each student (for Students section)
    let daysSinceLastLessonByStudent: [UUID: Int]

    // Most recent lesson subject per student (for suggest-next diversity)
    let lastSubjectByStudent: [UUID: String]

    // Open work count per student (fewer = needs a presentation sooner)
    let openWorkCountByStudent: [UUID: Int]

    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.calendar) private var calendar

    @FetchRequest(sortDescriptors: []) var lessonAssignments: FetchedResults<CDLessonAssignment>

    @State var searchText: String = ""
    @State var debouncedSearchText: String = ""
    @State private var searchDebounceTask: Task<Void, Never>?
    @State var suggestedLessonID: UUID?
    @State var suggestDismissTask: Task<Void, Never>?

    // Default sorting is by age
    let sortMode: PresentationsSortMode = .age

    // OPTIMIZATION: Cache dictionary lookups to avoid rebuilding on every access
    // These are recomputed only when the underlying cached data changes
    @State var cachedLessonsByID: [UUID: CDLesson] = [:]
    @State var cachedStudentsByID: [UUID: CDStudent] = [:]
    
    // MODERN: Computed properties with automatic dependency tracking
    // SwiftUI automatically recomputes these when their dependencies change
    
    /// Fast lookup dictionary for lessons - uses cached value
    var lessonsByID: [UUID: CDLesson] {
        cachedLessonsByID
    }

    /// Fast lookup dictionary for students - uses cached value
    var studentsByID: [UUID: CDStudent] {
        cachedStudentsByID
    }

    /// Lessons filtered by selected student (if any) - automatically updates
    var studentFilteredReadyLessons: [CDLessonAssignment] {
        guard let studentID = coordinator.selectedStudentFilter else { return readyLessons }
        let studentIDString = studentID.uuidString
        return readyLessons.filter { $0.studentIDs.contains(studentIDString) }
    }
    
    var studentFilteredBlockedLessons: [CDLessonAssignment] {
        guard let studentID = coordinator.selectedStudentFilter else { return blockedLessons }
        let studentIDString = studentID.uuidString
        return blockedLessons.filter { $0.studentIDs.contains(studentIDString) }
    }

    private var aiSuggestButton: some View {
        Button(action: {
            if let suggested = suggestedNextLesson {
                suggestDismissTask?.cancel()
                adaptiveWithAnimation(.easeInOut(duration: 0.3)) {
                    suggestedLessonID = suggested.id
                }
                suggestDismissTask = Task { @MainActor in
                    try? await Task.sleep(for: .seconds(3))
                    guard !Task.isCancelled else { return }
                    adaptiveWithAnimation(.easeOut(duration: 0.5)) {
                        suggestedLessonID = nil
                    }
                }
            }
        }, label: {
            Label("Suggest Next", systemImage: "sparkles")
                .font(AppTheme.ScaledFont.captionSemibold)
        })
        .buttonStyle(.plain)
        .foregroundStyle(Color.accentColor)
        .disabled(filteredAndSortedReadyLessons.isEmpty)
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                inboxHeader
                Divider()
                presentationsContent
            }

            Divider()
            studentsNeedingLessonsSidebar
        }
        .overlay { dropTargetOverlay }
        .dropDestination(for: String.self, action: handleDrop, isTargeted: { targeted in
            adaptiveWithAnimation { coordinator.setInboxTargeted(targeted) }
        })
        .onChange(of: cachedLessons) { _, newLessons in
            cachedLessonsByID = buildLessonLookup(newLessons)
        }
        .onChange(of: cachedStudents) { _, newStudents in
            cachedStudentsByID = buildStudentLookup(newStudents)
        }
        .task {
            cachedLessonsByID = buildLessonLookup(cachedLessons)
            cachedStudentsByID = buildStudentLookup(cachedStudents)
        }
        .onDisappear {
            suggestDismissTask?.cancel()
        }
    }

    private var inboxHeader: some View {
        VStack(spacing: AppTheme.Spacing.small) {
            inboxTitleBar
            inboxSearchBar
            activeStudentFilterChip
        }
        .padding(.bottom, AppTheme.Spacing.small)
        .background(.regularMaterial)
    }

    private var inboxTitleBar: some View {
        HStack(spacing: AppTheme.Spacing.compact) {
            Image(systemName: "tray")
                .imageScale(.large)
                .foregroundStyle(Color.accentColor)
            Text("Presentations")
                .font(.title3.weight(.semibold))

            aiSuggestButton

            Spacer()

            #if os(iOS)
            Button {
                adaptiveWithAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    coordinator.toggleCalendar()
                }
            } label: {
                Image(systemName: coordinator.isCalendarMinimized ? "calendar" : "calendar.badge.minus")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(AppTheme.Spacing.small)
                    .background(Color.primary.opacity(UIConstants.OpacityConstants.light))
                    .clipShape(Circle())
            }
            #endif
        }
        .padding(.horizontal, AppTheme.Spacing.medium)
        .padding(.top, AppTheme.Spacing.small)
    }

    private var inboxSearchBar: some View {
        HStack(spacing: AppTheme.Spacing.compact) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search students or lessons", text: $searchText)
                .textFieldStyle(.plain)
                .onSubmit {
                    searchDebounceTask?.cancel()
                    debouncedSearchText = searchText
                }
        }
        .padding(.horizontal, AppTheme.Spacing.medium)
        .padding(.vertical, AppTheme.Spacing.small)
        .background(Color.primary.opacity(UIConstants.OpacityConstants.veryFaint))
        .clipShape(RoundedRectangle(cornerRadius: UIConstants.CornerRadius.medium))
        .padding(.horizontal, AppTheme.Spacing.medium)
        .onChange(of: searchText) { _, newValue in
            searchDebounceTask?.cancel()
            searchDebounceTask = Task { @MainActor in
                do {
                    try await Task.sleep(for: .milliseconds(250))
                } catch {
                    Self.logger.debug("Search debounce interrupted: \(error)")
                }
                guard !Task.isCancelled else { return }
                debouncedSearchText = newValue
            }
        }
    }

    @ViewBuilder
    private var activeStudentFilterChip: some View {
        if let studentID = coordinator.selectedStudentFilter,
           let student = cachedStudents.first(where: { $0.id == studentID }) {
            studentFilterChipContent(student)
        }
    }

    private func studentFilterChipContent(_ student: CDStudent) -> some View {
        HStack(spacing: AppTheme.Spacing.verySmall) {
            Image(systemName: "person.fill")
                .font(.caption2)
            Text(StudentFormatter.displayName(for: student))
                .font(.caption.weight(.medium))
            Button {
                adaptiveWithAnimation(.easeInOut(duration: 0.15)) {
                    coordinator.clearStudentFilter()
                }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
            }
        }
        .foregroundStyle(AppColors.warning)
        .padding(.horizontal, AppTheme.Spacing.small + AppTheme.Spacing.xxsmall)
        .padding(.vertical, AppTheme.Spacing.verySmall)
        .background(AppColors.warning.opacity(UIConstants.OpacityConstants.accent))
        .clipShape(Capsule())
        .padding(.horizontal, AppTheme.Spacing.medium)
    }

    @ViewBuilder
    private var dropTargetOverlay: some View {
        if coordinator.isInboxTargeted {
            Color.accentColor.opacity(UIConstants.OpacityConstants.accent)
                .allowsHitTesting(false)

            RoundedRectangle(cornerRadius: UIConstants.CornerRadius.large)
                .stroke(Color.accentColor, lineWidth: UIConstants.StrokeWidth.extraThick)
                .padding(AppTheme.Spacing.xxsmall)
                .allowsHitTesting(false)

            VStack {
                Image(systemName: "arrow.down.doc.fill")
                    .font(.system(size: 50))
                    .foregroundStyle(Color.accentColor)
                Text("Drop to Unschedule")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(Color.accentColor)
            }
            .allowsHitTesting(false)
        }
    }
    private func handleDrop(_ items: [String], _ location: CGPoint) -> Bool {
        guard let str = items.first,
              let payload = UnifiedCalendarDragPayload.parse(str),
              case .presentation(let id) = payload,
              let la = lessonAssignments.first(where: { $0.id == id }),
              la.scheduledFor != nil else { return false }
        la.unschedule()
        viewContext.safeSave()
        return true
    }

    private func buildLessonLookup(_ lessons: some Collection<CDLesson>) -> [UUID: CDLesson] {
        Dictionary(lessons.compactMap { guard let id = $0.id else { return nil }; return (id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private func buildStudentLookup(_ students: some Collection<CDStudent>) -> [UUID: CDStudent] {
        Dictionary(students.compactMap { guard let id = $0.id else { return nil }; return (id, $0) }, uniquingKeysWith: { first, _ in first })
    }
}

// MARK: - Filtering, Sorting, and Suggest Next

extension PresentationsInboxView {

    func lessonTitle(for la: CDLessonAssignment, using lookupCache: [UUID: CDLesson]) -> String {
        if let lesson = lookupCache[uuidString: la.lessonID] {
            let name = lesson.name.trimmed()
            if !name.isEmpty { return name }
        }
        return "Lesson \(String(la.lessonID.prefix(6)))"
    }

    func studentNames(for la: CDLessonAssignment, using lookupCache: [UUID: CDStudent]) -> String {
        let snapshot = filteredSnapshot(la)
        let names = snapshot.studentIDs.compactMap { id -> String? in
            guard let student = lookupCache[id] else { return nil }
            return StudentFormatter.displayName(for: student)
        }
        return names.joined(separator: ", ")
    }

    func matchesSearch(_ la: CDLessonAssignment, query: String) -> Bool {
        guard !query.isEmpty else { return true }
        let lessonTitleLower = lessonTitle(for: la, using: lessonsByID).lowercased()
        let studentNamesLower = studentNames(for: la, using: studentsByID).lowercased()
        return lessonTitleLower.contains(query) || studentNamesLower.contains(query)
    }

    func sortedLessons(_ lessons: [CDLessonAssignment], query: String) -> [CDLessonAssignment] {
        let matched = lessons.filter { matchesSearch($0, query: query) }

        switch sortMode {
        case .lesson:
            return matched.sorted {
                lessonTitle(for: $0, using: lessonsByID)
                    .localizedCaseInsensitiveCompare(lessonTitle(for: $1, using: lessonsByID)) == .orderedAscending
            }
        case .student:
            return matched.sorted {
                studentNames(for: $0, using: studentsByID)
                    .localizedCaseInsensitiveCompare(studentNames(for: $1, using: studentsByID)) == .orderedAscending
            }
        case .age:
            // Sort by creation date (older first)
            return matched.sorted { ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) }
        case .needsAttention:
            // Sort by creation date (older first, as older lessons need more attention)
            return matched.sorted { ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) }
        }
    }

    // MARK: - Suggest Next

    /// Picks the highest-priority ready lesson based on student need and lesson age.
    var suggestedNextLesson: CDLessonAssignment? {
        let lessons = filteredAndSortedReadyLessons
        guard !lessons.isEmpty else { return nil }
        return lessons.max { suggestScore(for: $0) < suggestScore(for: $1) }
    }

    /// CDStudent IDs that already have a scheduled (but not yet given) lesson
    private var scheduledStudentIDs: Set<UUID> {
        var ids = Set<UUID>()
        for la in lessonAssignments where la.scheduledFor != nil && !la.isGiven {
            ids.formUnion(la.resolvedStudentIDs)
        }
        return ids
    }

    private func suggestScore(for la: CDLessonAssignment) -> Double {
        let scheduled = scheduledStudentIDs

        // Factor 1: Max days since last lesson, only counting students
        // who don't already have a scheduled lesson
        let relevantStudents = la.resolvedStudentIDs.filter { !scheduled.contains($0) }
        let maxStudentDays = relevantStudents
            .compactMap { daysSinceLastLessonByStudent[$0] }
            .max() ?? 0
        let studentScore = Double(min(maxStudentDays, 999))

        // Factor 2: CDLesson age in inbox (school days, not calendar days)
        let ageInSchoolDays = Double(LessonAgeHelper.schoolDaysSinceCreation(
            createdAt: la.createdAt ?? Date(), asOf: Date(),
            using: viewContext, calendar: calendar
        ))

        // Factor 3: Open work — boost lessons for students with less open work
        // Students with 0 open work need a presentation most urgently
        let minOpenWork = relevantStudents
            .map { openWorkCountByStudent[$0] ?? 0 }
            .min() ?? 0
        let openWorkBoost = max(0.0, 20.0 - Double(minOpenWork) * 5.0)

        // Factor 4: Subject diversity — penalize if a student's last lesson
        // was the same subject, to encourage variety
        let lessonSubject = lessonsByID[la.resolvedLessonID]?.subject
            .trimmed().lowercased() ?? ""
        var diversityPenalty = 0.0
        if !lessonSubject.isEmpty {
            for sid in relevantStudents where lastSubjectByStudent[sid]?.trimmed().lowercased() == lessonSubject {
                diversityPenalty += 5.0
            }
        }

        return studentScore * 10.0 + ageInSchoolDays + openWorkBoost - diversityPenalty
    }

    /// Filtered and sorted ready lessons - automatically recomputes when dependencies change
    var filteredAndSortedReadyLessons: [CDLessonAssignment] {
        let trimmedSearch = debouncedSearchText.trimmed().lowercased()
        return sortedLessons(studentFilteredReadyLessons, query: trimmedSearch)
    }

    /// Filtered and sorted blocked lessons - automatically recomputes when dependencies change
    var filteredAndSortedBlockedLessons: [CDLessonAssignment] {
        let trimmedSearch = debouncedSearchText.trimmed().lowercased()
        return sortedLessons(studentFilteredBlockedLessons, query: trimmedSearch)
    }

    @ViewBuilder
    func inboxRow(_ la: CDLessonAssignment, blockingWork: [UUID: CDWorkModel] = [:]) -> some View {
        HStack(spacing: 0) {
            PresentationPill(
                snapshot: filteredSnapshot(la),
                day: Date(),
                targetLessonAssignmentID: la.id,
                enableMissHighlight: true,
                enableMergeDrop: true,
                blockingWork: blockingWork,
                cachedLessons: cachedLessons,
                cachedStudents: cachedStudents
            )
            .onTapGesture { coordinator.showLessonAssignmentDetail(la) }
            .onDrag {
                let provider = NSItemProvider(object: NSString(string: (la.id ?? UUID()).uuidString))
                provider.suggestedName = lessonsByID[uuidString: la.lessonID]?.name ?? "Lesson"
                return provider
            }
        }
        .padding(AppTheme.Spacing.verySmall)
        .background(
            RoundedRectangle(cornerRadius: UIConstants.CornerRadius.medium, style: .continuous)
                .fill(Color.primary.opacity(UIConstants.OpacityConstants.veryFaint))
        )
    }

}
