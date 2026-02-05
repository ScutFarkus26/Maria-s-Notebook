// PresentationsInboxView.swift
// Inbox section extracted from PresentationsView

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct PresentationsInboxView: View {
    let readyLessons: [StudentLesson]
    let blockedLessons: [StudentLesson]
    let getBlockingWork: (StudentLesson) -> [UUID: WorkModel]
    let filteredSnapshot: (StudentLesson) -> StudentLessonSnapshot
    let missWindow: PresentationsMissWindow
    @Binding var missWindowRaw: String
    @Binding var selectedStudentLessonForDetail: StudentLesson?
    @Binding var isInboxTargeted: Bool
    @Binding var isCalendarMinimized: Bool
    @Binding var selectedStudentFilter: UUID?

    // Pass cached data from parent to avoid duplicate queries
    let cachedLessons: [Lesson]
    let cachedStudents: [Student]

    // Days since last lesson for each student (for Students section)
    let daysSinceLastLessonByStudent: [UUID: Int]

    @Environment(\.modelContext) private var modelContext
    @Environment(\.calendar) private var calendar

    @Query private var studentLessons: [StudentLesson]

    @State private var searchText: String = ""
    @State private var debouncedSearchText: String = ""
    @State private var searchDebounceTask: Task<Void, Never>? = nil

    // Cached filtered/sorted results to avoid recomputation during scroll
    @State private var cachedReadyLessons: [StudentLesson] = []
    @State private var cachedBlockedLessons: [StudentLesson] = []
    @State private var lastSearchText: String = ""
    @State private var lastReadyLessonsCount: Int = 0
    @State private var lastBlockedLessonsCount: Int = 0
    @State private var lastStudentFilter: UUID? = nil

    // Cached dictionaries for fast lookups
    @State private var lessonsByIDCache: [UUID: Lesson] = [:]
    @State private var studentsByIDCache: [UUID: Student] = [:]

    // Default sorting is by age
    private let sortMode: PresentationsSortMode = .age
    
    // Combined change detection key to consolidate onChange handlers
    private struct CacheInvalidationKey: Equatable {
        let searchText: String
        let readyCount: Int
        let blockedCount: Int
        let filterID: UUID?
    }
    
    private var cacheInvalidationKey: CacheInvalidationKey {
        CacheInvalidationKey(
            searchText: debouncedSearchText,
            readyCount: readyLessons.count,
            blockedCount: blockedLessons.count,
            filterID: selectedStudentFilter
        )
    }

    var body: some View {
        HStack(spacing: 0) {
            // Left side: Presentations inbox
            VStack(alignment: .leading, spacing: 0) {
                // Header
                VStack(spacing: 8) {
                    HStack(spacing: 12) {
                        Image(systemName: "tray")
                            .imageScale(.large)
                            .foregroundStyle(Color.accentColor)
                        Text("Presentations")
                            .font(.title3.weight(.semibold))
                        Spacer()

                        #if os(iOS)
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                isCalendarMinimized.toggle()
                            }
                        } label: {
                            Image(systemName: isCalendarMinimized ? "calendar" : "calendar.badge.minus")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .padding(8)
                                .background(Color.primary.opacity(0.1))
                                .clipShape(Circle())
                        }
                        #endif
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                    HStack(spacing: 12) {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField("Search students or lessons", text: $searchText)
                            .textFieldStyle(.plain)
                            .onSubmit {
                                searchDebounceTask?.cancel()
                                debouncedSearchText = searchText
                            }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.primary.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .padding(.horizontal, 16)
                    .onChange(of: searchText) { _, newValue in
                        searchDebounceTask?.cancel()
                        searchDebounceTask = Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 250_000_000) // 250ms debounce
                            guard !Task.isCancelled else { return }
                            debouncedSearchText = newValue
                        }
                    }

                    // Active student filter chip
                    if let studentID = selectedStudentFilter,
                       let student = cachedStudents.first(where: { $0.id == studentID }) {
                        HStack(spacing: 6) {
                            Image(systemName: "person.fill")
                                .font(.caption2)
                            Text(StudentFormatter.displayName(for: student))
                                .font(.caption.weight(.medium))
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    selectedStudentFilter = nil
                                }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.caption)
                            }
                        }
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.orange.opacity(0.15))
                        .clipShape(Capsule())
                        .padding(.horizontal, 16)
                    }
                }
                .padding(.bottom, 8)
                .background(.regularMaterial)

                Divider()

                presentationsContent
            }

            // Right side: Students needing lessons
            Divider()
            studentsNeedingLessonsSidebar
        }
        .overlay {
            if isInboxTargeted {
                Color.accentColor.opacity(0.15)
                    .allowsHitTesting(false)
                
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.accentColor, lineWidth: 3)
                    .padding(2)
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
            studentLessons: studentLessons,
            isTargeted: $isInboxTargeted
        ))
        .onAppear { updateCachesIfNeeded() }
        .onChange(of: cacheInvalidationKey) { _, _ in updateCachesIfNeeded() }
    }
    
    // MARK: - Filtering and Sorting

    private func lessonTitle(for sl: StudentLesson, using lookupCache: [UUID: Lesson]) -> String {
        if let lessonID = UUID(uuidString: sl.lessonID), let lesson = lookupCache[lessonID] {
            let name = lesson.name.trimmed()
            if !name.isEmpty { return name }
        }
        return "Lesson \(String(sl.lessonID.prefix(6)))"
    }

    private func studentNames(for sl: StudentLesson, using lookupCache: [UUID: Student]) -> String {
        let snapshot = filteredSnapshot(sl)
        let names = snapshot.studentIDs.compactMap { id -> String? in
            guard let student = lookupCache[id] else { return nil }
            return StudentFormatter.displayName(for: student)
        }
        return names.joined(separator: ", ")
    }

    private func matchesSearch(_ sl: StudentLesson, query: String, lessonCache: [UUID: Lesson], studentCache: [UUID: Student]) -> Bool {
        guard !query.isEmpty else { return true }
        let lessonTitleLower = lessonTitle(for: sl, using: lessonCache).lowercased()
        let studentNamesLower = studentNames(for: sl, using: studentCache).lowercased()
        return lessonTitleLower.contains(query) || studentNamesLower.contains(query)
    }

    private func sortedLessons(_ lessons: [StudentLesson], query: String, lessonCache: [UUID: Lesson], studentCache: [UUID: Student]) -> [StudentLesson] {
        let matched = lessons.filter { matchesSearch($0, query: query, lessonCache: lessonCache, studentCache: studentCache) }

        switch sortMode {
        case .lesson:
            return matched.sorted { lessonTitle(for: $0, using: lessonCache).localizedCaseInsensitiveCompare(lessonTitle(for: $1, using: lessonCache)) == .orderedAscending }
        case .student:
            return matched.sorted { studentNames(for: $0, using: studentCache).localizedCaseInsensitiveCompare(studentNames(for: $1, using: studentCache)) == .orderedAscending }
        case .age:
            // Sort by creation date (older first)
            return matched.sorted { $0.createdAt < $1.createdAt }
        case .needsAttention:
            // Sort by creation date (older first, as older lessons need more attention)
            return matched.sorted { $0.createdAt < $1.createdAt }
        }
    }

    private func updateCachesIfNeeded() {
        let trimmedSearch = debouncedSearchText.trimmed().lowercased()

        // Check if we need to rebuild caches
        let needsRebuild = trimmedSearch != lastSearchText
            || readyLessons.count != lastReadyLessonsCount
            || blockedLessons.count != lastBlockedLessonsCount
            || selectedStudentFilter != lastStudentFilter

        guard needsRebuild else { return }

        // Rebuild dictionary caches if lessons/students changed
        if lessonsByIDCache.count != cachedLessons.count {
            lessonsByIDCache = Dictionary(cachedLessons.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        }
        if studentsByIDCache.count != cachedStudents.count {
            studentsByIDCache = Dictionary(cachedStudents.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        }

        // Filter by selected student if any
        let filteredReady: [StudentLesson]
        let filteredBlocked: [StudentLesson]

        if let studentID = selectedStudentFilter {
            let studentIDString = studentID.uuidString
            filteredReady = readyLessons.filter { $0.studentIDs.contains(studentIDString) }
            filteredBlocked = blockedLessons.filter { $0.studentIDs.contains(studentIDString) }
        } else {
            filteredReady = readyLessons
            filteredBlocked = blockedLessons
        }

        // Rebuild filtered/sorted caches
        cachedReadyLessons = sortedLessons(filteredReady, query: trimmedSearch, lessonCache: lessonsByIDCache, studentCache: studentsByIDCache)
        cachedBlockedLessons = sortedLessons(filteredBlocked, query: trimmedSearch, lessonCache: lessonsByIDCache, studentCache: studentsByIDCache)

        lastSearchText = trimmedSearch
        lastReadyLessonsCount = readyLessons.count
        lastBlockedLessonsCount = blockedLessons.count
        lastStudentFilter = selectedStudentFilter
    }

    private var filteredAndSortedReadyLessons: [StudentLesson] {
        cachedReadyLessons
    }

    private var filteredAndSortedBlockedLessons: [StudentLesson] {
        cachedBlockedLessons
    }

    @ViewBuilder
    private func inboxRow(_ sl: StudentLesson, blockingWork: [UUID: WorkModel] = [:]) -> some View {
        HStack(spacing: 0) {
            StudentLessonPill(
                snapshot: filteredSnapshot(sl),
                day: Date(),
                targetStudentLessonID: sl.id,
                enableMissHighlight: true,
                enableMergeDrop: true,
                blockingWork: blockingWork,
                cachedLessons: cachedLessons,
                cachedStudents: cachedStudents
            )
            .onTapGesture { selectedStudentLessonForDetail = sl }
            .onDrag {
                let provider = NSItemProvider(object: NSString(string: sl.id.uuidString))
                provider.suggestedName = sl.lesson?.name ?? "Lesson"
                return provider
            }
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
    }

    // MARK: - Content Views

    @ViewBuilder
    private var presentationsContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {

                // 1. BLOCKED / WAITING SECTION
                if !filteredAndSortedBlockedLessons.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("On Deck (Waiting for Work)", systemImage: "hourglass")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 12)

                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(spacing: 8) {
                                ForEach(filteredAndSortedBlockedLessons, id: \.id) { sl in
                                    inboxRow(sl, blockingWork: getBlockingWork(sl))
                                }
                            }
                            .padding(.horizontal, 12)
                        }
                    }
                    .padding(.top, 12)
                }

                // 2. READY SECTION
                if filteredAndSortedReadyLessons.isEmpty {
                    if filteredAndSortedBlockedLessons.isEmpty {
                        ContentUnavailableView("All Caught Up", systemImage: "checkmark.circle", description: Text("No unscheduled presentations."))
                            .padding(.top, 40)
                    } else {
                        Text("All planned presentations are waiting on work.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, 20)
                    }
                } else {
                    LazyVGrid(columns: [
                        GridItem(.flexible(), spacing: 8),
                        GridItem(.flexible(), spacing: 8),
                        GridItem(.flexible(), spacing: 8)
                    ], alignment: .leading, spacing: 8) {
                        ForEach(filteredAndSortedReadyLessons, id: \.id) { sl in
                            inboxRow(sl)
                        }
                    }
                    .padding(.horizontal, 12)
                }
            }
            .padding(.bottom, 20)
        }
    }

    @ViewBuilder
    private var studentsNeedingLessonsSidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 8) {
                Text("Students")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.orange)
                Spacer()
                if !studentsNeedingLessons.isEmpty {
                    Text("\(studentsNeedingLessons.count)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(.orange))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .background(.regularMaterial)

            Divider()

            // Student list
            ScrollView {
                if studentsNeedingLessons.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "checkmark.circle")
                            .font(.system(size: 32))
                            .foregroundStyle(.secondary)
                        Text("All scheduled")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)
                } else {
                    LazyVStack(spacing: 4) {
                        ForEach(studentsNeedingLessons, id: \.id) { student in
                            studentRow(student)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.top, 8)
                }
            }
        }
        .frame(width: 220)
    }

    // MARK: - Students Needing Lessons

    /// Students who don't have any scheduled presentations (no StudentLesson with scheduledFor != nil)
    /// Sorted by days since last lesson, oldest first (students who haven't had a lesson longest come first)
    private var studentsNeedingLessons: [Student] {
        // Find all student IDs that have a scheduled lesson
        let scheduledStudentIDs: Set<UUID> = {
            var ids = Set<UUID>()
            for sl in studentLessons where sl.scheduledFor != nil && !sl.isGiven {
                ids.formUnion(sl.resolvedStudentIDs)
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
        let isSelected = selectedStudentFilter == student.id

        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
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
                    .frame(width: 24, height: 20)
                    .background {
                        if days >= 3 {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(.orange)
                        } else {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.primary.opacity(0.1))
                        }
                    }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? Color.orange.opacity(0.2) : Color.primary.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(isSelected ? Color.orange : Color.clear, lineWidth: 2)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.2)) {
                if selectedStudentFilter == student.id {
                    selectedStudentFilter = nil
                } else {
                    selectedStudentFilter = student.id
                }
            }
        }
    }
}

// MARK: - Drop Delegate for Inbox
private struct InboxDropDelegate: DropDelegate {
    let modelContext: ModelContext
    let studentLessons: [StudentLesson]
    @Binding var isTargeted: Bool
    
    func dropEntered(info: DropInfo) {
        withAnimation { isTargeted = true }
    }
    
    func dropExited(info: DropInfo) {
        withAnimation { isTargeted = false }
    }
    
    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [.text])
    }
    
    func performDrop(info: DropInfo) -> Bool {
        withAnimation { isTargeted = false }
        let providers = info.itemProviders(for: [.text])
        guard let provider = providers.first else { return false }
        
        provider.loadObject(ofClass: NSString.self) { reading, _ in
            guard let str = reading as? String, let id = UUID(uuidString: str) else { return }
            
            Task { @MainActor in
                if let sl = studentLessons.first(where: { $0.id == id }) {
                    // Only process if it actually has a schedule to clear
                    if sl.scheduledFor != nil {
                        sl.scheduledFor = nil
                        #if DEBUG
                        sl.checkInboxInvariant()
                        #endif
                        do {
                            try modelContext.save()
                        } catch {
                            #if DEBUG
                            print("Presentations inbox unschedule save failed: \(error)")
                            #endif
                        }
                    }
                }
            }
        }
        return true
    }
}
