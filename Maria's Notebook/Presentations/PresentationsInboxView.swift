// PresentationsInboxView.swift
// Inbox section extracted from PresentationsView

import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import OSLog

struct PresentationsInboxView: View {
    private static let logger = Logger.presentations
    let readyLessons: [LessonAssignment]
    let blockedLessons: [LessonAssignment]
    let getBlockingWork: (LessonAssignment) -> [UUID: WorkModel]
    let filteredSnapshot: (LessonAssignment) -> LessonAssignmentSnapshot
    let missWindow: PresentationsMissWindow
    @Binding var missWindowRaw: String
    
    // MODERN: Navigation coordinator replaces scattered @Binding vars
    let coordinator: PresentationsCoordinator

    // Pass cached data from parent to avoid duplicate queries
    let cachedLessons: [Lesson]
    let cachedStudents: [Student]

    // Days since last lesson for each student (for Students section)
    let daysSinceLastLessonByStudent: [UUID: Int]

    @Environment(\.modelContext) private var modelContext
    @Environment(\.calendar) private var calendar

    @Query private var lessonAssignments: [LessonAssignment]

    @State private var searchText: String = ""
    @State private var debouncedSearchText: String = ""
    @State private var searchDebounceTask: Task<Void, Never>? = nil
    @State private var showAIPlanning = false

    // Default sorting is by age
    private let sortMode: PresentationsSortMode = .age
    
    // OPTIMIZATION: Cache dictionary lookups to avoid rebuilding on every access
    // These are recomputed only when the underlying cached data changes
    @State private var cachedLessonsByID: [UUID: Lesson] = [:]
    @State private var cachedStudentsByID: [UUID: Student] = [:]
    
    // MODERN: Computed properties with automatic dependency tracking
    // SwiftUI automatically recomputes these when their dependencies change
    
    /// Fast lookup dictionary for lessons - uses cached value
    private var lessonsByID: [UUID: Lesson] {
        cachedLessonsByID
    }
    
    /// Fast lookup dictionary for students - uses cached value
    private var studentsByID: [UUID: Student] {
        cachedStudentsByID
    }
    
    /// Lessons filtered by selected student (if any) - automatically updates
    private var studentFilteredReadyLessons: [LessonAssignment] {
        guard let studentID = coordinator.selectedStudentFilter else { return readyLessons }
        let studentIDString = studentID.uuidString
        return readyLessons.filter { $0.studentIDs.contains(studentIDString) }
    }
    
    private var studentFilteredBlockedLessons: [LessonAssignment] {
        guard let studentID = coordinator.selectedStudentFilter else { return blockedLessons }
        let studentIDString = studentID.uuidString
        return blockedLessons.filter { $0.studentIDs.contains(studentIDString) }
    }

    private var aiSuggestButton: some View {
        Button(action: { showAIPlanning = true }) {
            Label("Suggest Next", systemImage: "sparkles")
                .font(.system(size: 12, weight: .medium, design: .rounded))
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.accentColor)
    }

    var body: some View {
        HStack(spacing: 0) {
            // Left side: Presentations inbox
            VStack(alignment: .leading, spacing: 0) {
                // Header
                VStack(spacing: AppTheme.Spacing.small) {
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
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
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
                                try await Task.sleep(for: .milliseconds(250)) // 250ms debounce
                            } catch {
                                Self.logger.debug("Search debounce interrupted: \(error)")
                            }
                            guard !Task.isCancelled else { return }
                            debouncedSearchText = newValue
                        }
                    }

                    // Active student filter chip
                    if let studentID = coordinator.selectedStudentFilter,
                       let student = cachedStudents.first(where: { $0.id == studentID }) {
                        HStack(spacing: AppTheme.Spacing.verySmall) {
                            Image(systemName: "person.fill")
                                .font(.caption2)
                            Text(StudentFormatter.displayName(for: student))
                                .font(.caption.weight(.medium))
                            Button {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    coordinator.clearStudentFilter()
                                }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.caption)
                            }
                        }
                        .foregroundStyle(.orange)
                        .padding(.horizontal, AppTheme.Spacing.small + AppTheme.Spacing.xxsmall)
                        .padding(.vertical, AppTheme.Spacing.verySmall)
                        .background(Color.orange.opacity(UIConstants.OpacityConstants.accent))
                        .clipShape(Capsule())
                        .padding(.horizontal, AppTheme.Spacing.medium)
                    }
                }
                .padding(.bottom, AppTheme.Spacing.small)
                .background(.regularMaterial)

                Divider()

                presentationsContent
            }

            // Right side: Students needing lessons
            Divider()
            studentsNeedingLessonsSidebar
        }
        .overlay {
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
        .onDrop(of: [.text], delegate: InboxDropDelegate(
            modelContext: modelContext,
            lessonAssignments: lessonAssignments,
            coordinator: coordinator
        ))
        .onChange(of: cachedLessons) { _, newLessons in
            cachedLessonsByID = Dictionary(newLessons.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        }
        .onChange(of: cachedStudents) { _, newStudents in
            cachedStudentsByID = Dictionary(newStudents.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        }
        .task {
            // Initialize cached dictionaries on first load
            cachedLessonsByID = Dictionary(cachedLessons.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            cachedStudentsByID = Dictionary(cachedStudents.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        }
        .sheet(isPresented: $showAIPlanning) {
            AIPlanningAssistantView(mode: .quickSuggest(cachedStudents.map { $0.id }))
        }
    }
    
    // MARK: - Filtering and Sorting

    private func lessonTitle(for la: LessonAssignment, using lookupCache: [UUID: Lesson]) -> String {
        if let lessonID = UUID(uuidString: la.lessonID), let lesson = lookupCache[lessonID] {
            let name = lesson.name.trimmed()
            if !name.isEmpty { return name }
        }
        return "Lesson \(String(la.lessonID.prefix(6)))"
    }

    private func studentNames(for la: LessonAssignment, using lookupCache: [UUID: Student]) -> String {
        let snapshot = filteredSnapshot(la)
        let names = snapshot.studentIDs.compactMap { id -> String? in
            guard let student = lookupCache[id] else { return nil }
            return StudentFormatter.displayName(for: student)
        }
        return names.joined(separator: ", ")
    }

    private func matchesSearch(_ la: LessonAssignment, query: String) -> Bool {
        guard !query.isEmpty else { return true }
        let lessonTitleLower = lessonTitle(for: la, using: lessonsByID).lowercased()
        let studentNamesLower = studentNames(for: la, using: studentsByID).lowercased()
        return lessonTitleLower.contains(query) || studentNamesLower.contains(query)
    }

    private func sortedLessons(_ lessons: [LessonAssignment], query: String) -> [LessonAssignment] {
        let matched = lessons.filter { matchesSearch($0, query: query) }

        switch sortMode {
        case .lesson:
            return matched.sorted { lessonTitle(for: $0, using: lessonsByID).localizedCaseInsensitiveCompare(lessonTitle(for: $1, using: lessonsByID)) == .orderedAscending }
        case .student:
            return matched.sorted { studentNames(for: $0, using: studentsByID).localizedCaseInsensitiveCompare(studentNames(for: $1, using: studentsByID)) == .orderedAscending }
        case .age:
            // Sort by creation date (older first)
            return matched.sorted { $0.createdAt < $1.createdAt }
        case .needsAttention:
            // Sort by creation date (older first, as older lessons need more attention)
            return matched.sorted { $0.createdAt < $1.createdAt }
        }
    }

    /// Filtered and sorted ready lessons - automatically recomputes when dependencies change
    private var filteredAndSortedReadyLessons: [LessonAssignment] {
        let trimmedSearch = debouncedSearchText.trimmed().lowercased()
        return sortedLessons(studentFilteredReadyLessons, query: trimmedSearch)
    }

    /// Filtered and sorted blocked lessons - automatically recomputes when dependencies change
    private var filteredAndSortedBlockedLessons: [LessonAssignment] {
        let trimmedSearch = debouncedSearchText.trimmed().lowercased()
        return sortedLessons(studentFilteredBlockedLessons, query: trimmedSearch)
    }

    @ViewBuilder
    private func inboxRow(_ la: LessonAssignment, blockingWork: [UUID: WorkModel] = [:]) -> some View {
        HStack(spacing: 0) {
            StudentLessonPill(
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
                let provider = NSItemProvider(object: NSString(string: la.id.uuidString))
                provider.suggestedName = (UUID(uuidString: la.lessonID).flatMap { lessonsByID[$0] })?.name ?? "Lesson"
                return provider
            }
        }
        .padding(AppTheme.Spacing.verySmall)
        .background(
            RoundedRectangle(cornerRadius: UIConstants.CornerRadius.medium, style: .continuous)
                .fill(Color.primary.opacity(UIConstants.OpacityConstants.veryFaint))
        )
    }

    // MARK: - Content Views

    @ViewBuilder
    private var presentationsContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {

                // 1. BLOCKED / WAITING SECTION
                if !filteredAndSortedBlockedLessons.isEmpty {
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
                        Label("On Deck (Waiting for Work)", systemImage: "hourglass")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, AppTheme.Spacing.compact)

                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(spacing: AppTheme.Spacing.small) {
                                ForEach(filteredAndSortedBlockedLessons, id: \.id) { la in
                                    inboxRow(la, blockingWork: getBlockingWork(la))
                                }
                            }
                            .padding(.horizontal, AppTheme.Spacing.compact)
                        }
                    }
                    .padding(.top, AppTheme.Spacing.compact)
                }

                // 2. READY SECTION
                if filteredAndSortedReadyLessons.isEmpty {
                    if filteredAndSortedBlockedLessons.isEmpty {
                        ContentUnavailableView("All Caught Up", systemImage: "checkmark.circle", description: Text("No unscheduled presentations."))
                            .padding(.top, AppTheme.Spacing.large + AppTheme.Spacing.medium)
                    } else {
                        Text("All planned presentations are waiting on work.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, AppTheme.Spacing.medium + AppTheme.Spacing.xsmall)
                    }
                } else {
                    LazyVGrid(columns: [
                        GridItem(.flexible(), spacing: AppTheme.Spacing.small),
                        GridItem(.flexible(), spacing: AppTheme.Spacing.small),
                        GridItem(.flexible(), spacing: AppTheme.Spacing.small)
                    ], alignment: .leading, spacing: AppTheme.Spacing.small) {
                        ForEach(filteredAndSortedReadyLessons, id: \.id) { la in
                            inboxRow(la)
                        }
                    }
                    .padding(.horizontal, AppTheme.Spacing.compact)
                }
            }
            .padding(.bottom, AppTheme.Spacing.medium + AppTheme.Spacing.xsmall)
        }
    }

    @ViewBuilder
    private var studentsNeedingLessonsSidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: AppTheme.Spacing.small) {
                Text("Students")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.orange)
                Spacer()
                if !studentsNeedingLessons.isEmpty {
                    Text("\(studentsNeedingLessons.count)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, AppTheme.Spacing.compact)
                        .padding(.vertical, AppTheme.Spacing.xsmall)
                        .background(Capsule().fill(.orange))
                }
            }
            .padding(.horizontal, AppTheme.Spacing.compact)
            .padding(.vertical, AppTheme.Spacing.compact)
            .background(.regularMaterial)

            Divider()

            // Student list
            ScrollView {
                if studentsNeedingLessons.isEmpty {
                    VStack(spacing: AppTheme.Spacing.small) {
                        Image(systemName: "checkmark.circle")
                            .font(.system(size: 32))
                            .foregroundStyle(.secondary)
                        Text("All scheduled")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, AppTheme.Spacing.xxlarge + AppTheme.Spacing.medium)
                } else {
                    LazyVStack(spacing: AppTheme.Spacing.xsmall) {
                        ForEach(studentsNeedingLessons, id: \.id) { student in
                            studentRow(student)
                        }
                    }
                    .padding(.horizontal, AppTheme.Spacing.small)
                    .padding(.top, AppTheme.Spacing.small)
                }
            }
        }
        .frame(width: 220)
    }

    // MARK: - Students Needing Lessons

    /// Students who don't have any scheduled presentations
    /// Sorted by days since last lesson, oldest first (students who haven't had a lesson longest come first)
    private var studentsNeedingLessons: [Student] {
        // Find all student IDs that have a scheduled lesson
        let scheduledStudentIDs: Set<UUID> = {
            var ids = Set<UUID>()
            for la in lessonAssignments where la.scheduledFor != nil && !la.isGiven {
                ids.formUnion(la.resolvedStudentIDs)
            }
            return ids
        }()

        // Filter search
        let trimmedSearch = debouncedSearchText.trimmed().lowercased()

        // Filter to students without scheduled lessons
        let unscheduledStudents = cachedStudents.filter { student in
            // Check if student has no scheduled lessons
            guard !scheduledStudentIDs.contains(student.id) else { return false }

            // Apply search filter
            if !trimmedSearch.isEmpty {
                let name = StudentFormatter.displayName(for: student).lowercased()
                if !name.contains(trimmedSearch) { return false }
            }

            return true
        }

        // Sort by days since last lesson (oldest first = highest days first, then Int.max for never)
        return unscheduledStudents.sorted { a, b in
            let daysA = daysSinceLastLessonByStudent[a.id] ?? Int.max
            let daysB = daysSinceLastLessonByStudent[b.id] ?? Int.max
            // Sort descending: students with more days since last lesson come first
            return daysA > daysB
        }
    }

    @ViewBuilder
    private func studentRow(_ student: Student) -> some View {
        let isSelected = coordinator.selectedStudentFilter == student.id

        HStack(spacing: AppTheme.Spacing.small) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xxsmall) {
                Text(StudentFormatter.displayName(for: student))
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)

                // Days since last lesson - compact format
                if let days = daysSinceLastLessonByStudent[student.id] {
                    if days == Int.max {
                        Text("No lessons")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    } else if days == 0 {
                        Text("Today")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("\(days)d ago")
                            .font(.caption2)
                            .foregroundStyle(days >= 3 ? .orange : .secondary)
                    }
                } else {
                    Text("No lessons")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }

            Spacer()

            // Days badge for quick scanning
            if let days = daysSinceLastLessonByStudent[student.id], days != Int.max && days > 0 {
                Text("\(days)")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(days >= 3 ? .white : .secondary)
                    .frame(width: AppTheme.Spacing.large, height: AppTheme.Spacing.medium + AppTheme.Spacing.xsmall)
                    .background {
                        if days >= 3 {
                            RoundedRectangle(cornerRadius: AppTheme.Spacing.xsmall)
                                .fill(.orange)
                        } else {
                            RoundedRectangle(cornerRadius: AppTheme.Spacing.xsmall)
                                .fill(Color.primary.opacity(UIConstants.OpacityConstants.light))
                        }
                    }
            }
        }
        .padding(.horizontal, AppTheme.Spacing.small + AppTheme.Spacing.xxsmall)
        .padding(.vertical, AppTheme.Spacing.small)
        .background(
            RoundedRectangle(cornerRadius: UIConstants.CornerRadius.medium, style: .continuous)
                .fill(isSelected ? Color.orange.opacity(UIConstants.OpacityConstants.accent + 0.05) : Color.primary.opacity(UIConstants.OpacityConstants.veryFaint))
        )
        .overlay(
            RoundedRectangle(cornerRadius: UIConstants.CornerRadius.medium, style: .continuous)
                .stroke(isSelected ? Color.orange : Color.clear, lineWidth: UIConstants.StrokeWidth.thick)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.15)) {
                if coordinator.selectedStudentFilter == student.id {
                    coordinator.clearStudentFilter()
                } else {
                    coordinator.filterByStudent(student.id)
                }
            }
        }
    }
}

// MARK: - Drop Delegate for Inbox
private struct InboxDropDelegate: DropDelegate {
    private static let logger = Logger.presentations
    let modelContext: ModelContext
    let lessonAssignments: [LessonAssignment]
    let coordinator: PresentationsCoordinator

    func dropEntered(info: DropInfo) {
        withAnimation { coordinator.setInboxTargeted(true) }
    }

    func dropExited(info: DropInfo) {
        withAnimation { coordinator.setInboxTargeted(false) }
    }

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [.text])
    }

    func performDrop(info: DropInfo) -> Bool {
        withAnimation { coordinator.setInboxTargeted(false) }
        let providers = info.itemProviders(for: [.text])
        guard let provider = providers.first else { return false }

        provider.loadObject(ofClass: NSString.self) { reading, _ in
            guard let str = reading as? String,
                  let payload = UnifiedCalendarDragPayload.parse(str),
                  case .studentLesson(let id) = payload else { return }

            Task { @MainActor in
                if let la = lessonAssignments.first(where: { $0.id == id }) {
                    if la.scheduledFor != nil {
                        la.unschedule()
                        do {
                            try modelContext.save()
                        } catch {
                            Self.logger.warning("Presentations inbox unschedule save failed: \(error)")
                        }
                    }
                }
            }
        }
        return true
    }
}
