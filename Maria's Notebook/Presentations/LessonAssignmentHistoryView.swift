//
//  LessonAssignmentHistoryView.swift
//  Maria's Notebook
//
//  History view for presented LessonAssignments.
//  Phase 5 migration: This view reads from LessonAssignment instead of Presentation.
//

import SwiftUI
import SwiftData
import OSLog

struct LessonAssignmentHistoryView: View {
    private static let logger = Logger.presentations
    @Environment(\.modelContext) private var modelContext
    @Environment(\.calendar) private var calendar

    // Test student filtering
    @AppStorage("General.showTestStudents") private var showTestStudents: Bool = false
    @AppStorage("General.testStudentNames") private var testStudentNamesRaw: String = "Danny De Berry,Lil Dan D"

    // PAGINATION: Load assignments in batches instead of all at once
    private static let initialLoadCount = 50
    private static let loadMoreCount = 50

    @State private var loadedAssignments: [LessonAssignment] = []
    @State private var hasLoadedMore = false

    // Fetch Lessons (for lookup)
    @Query private var lessons: [Lesson]
    // Fetch Students (for lookup)
    @Query private var studentsRaw: [Student]

    // DEDUPLICATION: CloudKit sync can create duplicate records with the same ID.
    // Filter out test students when setting is disabled
    private var students: [Student] {
        TestStudentsFilter.filterVisible(studentsRaw.uniqueByID, show: showTestStudents, namesRaw: testStudentNamesRaw)
    }

    // Double deduplication ensures no crashes even with CloudKit sync race conditions
    private var safeStudents: [Student] {
        students.uniqueByID
    }

    // Fetch Notes that are attached to a lesson assignment
    @Query(sort: \Note.createdAt, order: .reverse) private var recentNotes: [Note]

    // Use @Query for change detection only - track count for efficient change detection
    @Query(filter: #Predicate<LessonAssignment> { $0.stateRaw == "presented" },
           sort: [SortDescriptor(\LessonAssignment.presentedAt, order: .reverse)])
    private var allAssignmentsForChangeDetection: [LessonAssignment]

    @State private var selectedAssignment: LessonAssignment? = nil
    @State private var notesCountCache: [String: Int] = [:]
    @State private var studentNameCache: [UUID: String] = [:]
    @State private var lessonTitleCache: [UUID: String] = [:]
    @State private var hasBuiltCachesOnce: Bool = false

    // Track counts for efficient change detection (avoids expensive .map operations)
    @State private var lastAssignmentCount: Int = 0
    @State private var lastNotesCount: Int = 0
    @State private var lastLessonsCount: Int = 0
    @State private var lastStudentsCount: Int = 0

    // Filter state
    @State private var selectedStudentIDs: Set<UUID> = []
    @State private var selectedSubjects: Set<String> = []
    @State private var searchText: String = ""

    @AppStorage("PresentationHistory.nameDisplayStyle") private var nameDisplayStyleRaw: String = "firstLastInitial"
    private enum NameDisplayStyle: String, Sendable { case initials, firstLastInitial }
    private var nameDisplayStyle: NameDisplayStyle { NameDisplayStyle(rawValue: nameDisplayStyleRaw) ?? .firstLastInitial }

    private func displayName(for s: Student) -> String {
        let first = s.firstName.trimmed()
        let last = s.lastName.trimmed()
        switch nameDisplayStyle {
        case .initials:
            let fi = first.first.map { String($0).uppercased() } ?? ""
            let li = last.first.map { String($0).uppercased() } ?? ""
            return fi + li
        case .firstLastInitial:
            let li = last.first.map { String($0).uppercased() } ?? ""
            return li.isEmpty ? first : "\(first) \(li)."
        }
    }

    // Maps for quick lookup
    // Use uniquingKeysWith to handle CloudKit sync duplicates
    private var lessonsByID: [UUID: Lesson] {
        Dictionary(lessons.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }
    private var studentsByID: [UUID: Student] {
        Dictionary(safeStudents.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    // Available subjects from lessons (sorted, non-empty only)
    private var availableSubjects: [String] {
        let subjects = Set(lessons.map { $0.subject.trimmed() })
            .filter { !$0.isEmpty }
        return subjects.sorted()
    }

    // Filtered assignments
    // DEDUPLICATION: CloudKit sync can create duplicate records with the same ID.
    private var filteredAssignments: [LessonAssignment] {
        loadedAssignments.uniqueByID.filter { la in
            // Student filter
            if !selectedStudentIDs.isEmpty {
                let assignmentStudentIDs = Set(la.studentUUIDs)
                if assignmentStudentIDs.isDisjoint(with: selectedStudentIDs) { return false }
            }

            // Subject filter
            if !selectedSubjects.isEmpty {
                if let lessonID = la.lessonIDUUID,
                   let lesson = lessonsByID[lessonID] {
                    let subject = lesson.subject.trimmed()
                    if !selectedSubjects.contains(subject) { return false }
                } else {
                    // No lesson found, exclude if filtering by subject
                    return false
                }
            }

            // Search filter
            if !searchText.isEmpty {
                let titleText = title(for: la).lowercased()
                let query = searchText.lowercased()
                if !titleText.contains(query) { return false }
            }

            return true
        }
    }

    // Group assignments by day (start of day)
    private func dayKey(_ date: Date) -> Date {
        calendar.startOfDay(for: date)
    }

    private var groupedByDay: [(day: Date, items: [LessonAssignment])] {
        let dict = filteredAssignments
            .compactMap { la -> (Date, LessonAssignment)? in
                guard let presentedAt = la.presentedAt else { return nil }
                return (dayKey(presentedAt), la)
            }
            .reduce(into: [Date: [LessonAssignment]]()) { result, pair in
                result[pair.0, default: []].append(pair.1)
            }
            .mapValues { arr in
                // DEDUPLICATION: Ensure no duplicate IDs within each day group
                arr.uniqueByID.sorted { ($0.presentedAt ?? .distantPast) > ($1.presentedAt ?? .distantPast) }
            }
        let days = dict.keys.sorted(by: >)
        return days.map { ($0, dict[$0] ?? []) }
    }

    private func loadAssignments(limit: Int? = nil) {
        let presentedState = LessonAssignmentState.presented.rawValue
        var descriptor = FetchDescriptor<LessonAssignment>(
            predicate: #Predicate { $0.stateRaw == presentedState },
            sortBy: [
                SortDescriptor(\LessonAssignment.presentedAt, order: .reverse),
                SortDescriptor(\LessonAssignment.createdAt, order: .reverse)
            ]
        )
        if let limit = limit {
            descriptor.fetchLimit = limit
        }
        loadedAssignments = modelContext.safeFetch(descriptor)
        // If we requested a limit and got fewer results, we've loaded all available
        if let limit = limit {
            hasLoadedMore = loadedAssignments.count < limit
        } else {
            hasLoadedMore = false // No limit means we loaded everything
        }
    }

    private func loadMoreAssignments() {
        guard !hasLoadedMore else { return }
        let currentCount = loadedAssignments.count
        let presentedState = LessonAssignmentState.presented.rawValue
        var descriptor = FetchDescriptor<LessonAssignment>(
            predicate: #Predicate { $0.stateRaw == presentedState },
            sortBy: [
                SortDescriptor(\LessonAssignment.presentedAt, order: .reverse),
                SortDescriptor(\LessonAssignment.createdAt, order: .reverse)
            ]
        )
        descriptor.fetchLimit = currentCount + Self.loadMoreCount
        let newResults = modelContext.safeFetch(descriptor)
        loadedAssignments = newResults
        // If we got fewer results than requested, we've loaded all available
        hasLoadedMore = newResults.count < currentCount + Self.loadMoreCount
    }

    // Date formatters
    private static let dayFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .none
        return df
    }()

    private static let timeFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateStyle = .none
        df.timeStyle = .short
        return df
    }()

    /// Builds caches asynchronously to avoid blocking the main thread.
    /// Extracts primitive values on the main thread, then processes on background.
    @MainActor
    private func buildCachesAsync() async {
        // Extract primitive/Sendable values on main thread before background processing
        // This avoids passing SwiftData model objects across actor boundaries
        let assignmentIDs: [String] = recentNotes.compactMap { $0.lessonAssignment?.id.uuidString }
        let studentData: [(UUID, String, String)] = safeStudents.map { ($0.id, $0.firstName, $0.lastName) }
        let lessonData: [(UUID, String)] = lessons.map { ($0.id, $0.name) }

        // Build caches on background thread using only Sendable data
        let (counts, sNames, lTitles) = await Task.detached(priority: .userInitiated) {
            // Build notes count cache
            var counts: [String: Int] = [:]
            for assignmentID in assignmentIDs {
                counts[assignmentID, default: 0] += 1
            }

            // Build student name cache
            var sNames: [UUID: String] = [:]
            for (id, firstName, lastName) in studentData {
                let first = firstName.trimmed()
                let last = lastName.trimmed()
                let li = last.first.map { String($0).uppercased() } ?? ""
                sNames[id] = li.isEmpty ? first : "\(first) \(li)."
            }

            // Build lesson title cache
            var lTitles: [UUID: String] = [:]
            for (id, name) in lessonData {
                lTitles[id] = LessonFormatter.titleOrFallback(name, fallback: "Lesson")
            }

            return (counts, sNames, lTitles)
        }.value

        // Assign on main thread
        notesCountCache = counts
        studentNameCache = sNames
        lessonTitleCache = lTitles
    }

    // Resolve title: prefer snapshot else lookup lesson by ID
    private func title(for la: LessonAssignment) -> String {
        if let snap = la.lessonTitleSnapshot?.trimmed(), !snap.isEmpty {
            return snap
        }
        if let lid = la.lessonIDUUID, let t = lessonTitleCache[lid] {
            return LessonFormatter.titleOrFallback(t, fallback: "Lesson")
        }
        return "Lesson"
    }

    // Student names or count string
    private func studentNamesOrCount(for la: LessonAssignment) -> String {
        let ids = la.studentUUIDs
        let names: [String] = ids.compactMap { studentNameCache[$0] }
        if names.isEmpty { return "0 students" }
        if names.count <= 3 {
            return names.joined(separator: ", ")
        } else {
            return "\(names.count) students"
        }
    }

    // MARK: - Filter Labels

    private var selectedStudentLabel: String {
        if selectedStudentIDs.isEmpty {
            return "All Students"
        } else if selectedStudentIDs.count == 1, let id = selectedStudentIDs.first,
                  let student = safeStudents.first(where: { $0.id == id }) {
            return displayName(for: student)
        } else {
            return "\(selectedStudentIDs.count) Students"
        }
    }

    private var selectedSubjectLabel: String {
        if selectedSubjects.isEmpty {
            return "All Subjects"
        } else if selectedSubjects.count == 1, let subject = selectedSubjects.first {
            return subject
        } else {
            return "\(selectedSubjects.count) Subjects"
        }
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        HStack(spacing: 12) {
            // Student Menu (multi-select)
            Menu {
                Button("All Students") { selectedStudentIDs.removeAll() }
                Divider()
                ForEach(safeStudents) { student in
                    Button(action: {
                        if selectedStudentIDs.contains(student.id) {
                            selectedStudentIDs.remove(student.id)
                        } else {
                            selectedStudentIDs.insert(student.id)
                        }
                    }) {
                        HStack {
                            if selectedStudentIDs.contains(student.id) {
                                Image(systemName: "checkmark")
                            }
                            Text(displayName(for: student))
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "person.3")
                    Text(selectedStudentLabel)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.05)))
            }

            // Subject Menu (multi-select)
            Menu {
                Button("All Subjects") { selectedSubjects.removeAll() }
                Divider()
                ForEach(availableSubjects, id: \.self) { subject in
                    Button(action: {
                        if selectedSubjects.contains(subject) {
                            selectedSubjects.remove(subject)
                        } else {
                            selectedSubjects.insert(subject)
                        }
                    }) {
                        HStack {
                            if selectedSubjects.contains(subject) {
                                Image(systemName: "checkmark")
                            }
                            Text(subject)
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                    Text(selectedSubjectLabel)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.05)))
            }

            Spacer()
        }
        .padding(.horizontal, 12)
    }

    // MARK: - Main Content

    private var mainContent: some View {
        VStack(spacing: 8) {
            filterBar

            Group {
                if loadedAssignments.isEmpty {
                    ContentUnavailableView(
                        "No Presentations Yet",
                        systemImage: "clock.arrow.circlepath",
                        description: Text("Present lessons to see them here.")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if filteredAssignments.isEmpty {
                    ContentUnavailableView(
                        "No Matching Presentations",
                        systemImage: "magnifyingglass",
                        description: Text("Try adjusting your filters.")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    assignmentsList
                }
            }
        }
    }

    private var assignmentsList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                ForEach(Array(groupedByDay.enumerated()), id: \.element.day) { dayIndex, entry in
                    daySection(dayIndex: dayIndex, entry: entry)
                }
            }
            .padding(16)
        }
    }

    @ViewBuilder
    private func daySection(dayIndex: Int, entry: (day: Date, items: [LessonAssignment])) -> some View {
        Section {
            ForEach(Array(entry.items.enumerated()), id: \.element.id) { itemIndex, la in
                row(for: la)
                    .onTapGesture { selectedAssignment = la }
                    .onAppear {
                        // Load more when near the end
                        if dayIndex == groupedByDay.count - 1,
                           itemIndex >= entry.items.count - 5 {
                            loadMoreAssignments()
                        }
                    }
            }
        } header: {
            Text(Self.dayFormatter.string(from: entry.day))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.top, 12)
        }
    }

    var body: some View {
        mainContent
            .searchable(text: $searchText)
            .sheet(item: $selectedAssignment) { la in
                LessonAssignmentDetailSheet(assignmentID: la.id) {
                    selectedAssignment = nil
                }
            }
            .task {
                loadAssignments(limit: Self.initialLoadCount)
                if !hasBuiltCachesOnce {
                    await buildCachesAsync()
                    hasBuiltCachesOnce = true
                }
                // Initialize counts for change detection
                lastAssignmentCount = allAssignmentsForChangeDetection.count
                lastNotesCount = recentNotes.count
                lastLessonsCount = lessons.count
                lastStudentsCount = safeStudents.count
            }
            .onChange(of: allAssignmentsForChangeDetection.count) { _, newCount in
                // Only reload when count actually changes
                guard newCount != lastAssignmentCount else { return }
                lastAssignmentCount = newCount
                loadAssignments(limit: loadedAssignments.count >= Self.initialLoadCount ? nil : Self.initialLoadCount)
            }
            .onChange(of: recentNotes.count) { _, newCount in
                guard newCount != lastNotesCount else { return }
                lastNotesCount = newCount
                Task { await buildCachesAsync() }
            }
            .onChange(of: lessons.count) { _, newCount in
                guard newCount != lastLessonsCount else { return }
                lastLessonsCount = newCount
                Task { await buildCachesAsync() }
            }
            .onChange(of: safeStudents.count) { _, newCount in
                guard newCount != lastStudentsCount else { return }
                lastStudentsCount = newCount
                Task { await buildCachesAsync() }
            }
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Menu {
                        Button {
                            nameDisplayStyleRaw = NameDisplayStyle.firstLastInitial.rawValue
                        } label: {
                            HStack {
                                if nameDisplayStyle == .firstLastInitial {
                                    Image(systemName: "checkmark")
                                }
                                Text("First name + Last initial")
                            }
                        }
                        Button {
                            nameDisplayStyleRaw = NameDisplayStyle.initials.rawValue
                        } label: {
                            HStack {
                                if nameDisplayStyle == .initials {
                                    Image(systemName: "checkmark")
                                }
                                Text("Initials (AB)")
                            }
                        }
                    } label: {
                        Label("Names", systemImage: "textformat.abc")
                    }
                }
            }
    }

    @ViewBuilder
    private func row(for la: LessonAssignment) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title(for: la))
                        .font(.system(size: AppTheme.FontSize.body, weight: .semibold, design: .rounded))
                    HStack(spacing: 6) {
                        if let presentedAt = la.presentedAt {
                            Text(Self.timeFormatter.string(from: presentedAt))
                        }
                        Text("•")
                        Text(studentNamesOrCount(for: la))
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            // Display notes inline if present
            if let notes = la.unifiedNotes, !notes.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(notes.sorted(by: { $0.createdAt > $1.createdAt }), id: \.id) { note in
                        noteRow(note)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 10)
            }
        }
        .contentShape(Rectangle())
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
        .contextMenu {
            Button {
                selectedAssignment = la
            } label: {
                Label("View Details", systemImage: "eye")
            }

            if let lessonID = la.lessonIDUUID {
                #if os(macOS)
                Button {
                    openLessonInNewWindow(lessonID)
                } label: {
                    Label("View Lesson", systemImage: "book")
                }
                #endif
            }

            Divider()

            Button(role: .destructive) {
                deleteAssignment(la)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    @ViewBuilder
    private func noteRow(_ note: Note) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(note.body)
                .font(.system(size: AppTheme.FontSize.caption, design: .rounded))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 6) {
                // Tag badges
                if !note.tags.isEmpty {
                    ForEach(note.tags.prefix(2), id: \.self) { tag in
                        TagBadge(tag: tag, compact: true)
                    }
                }

                // Image indicator
                if note.imagePath != nil {
                    Image(systemName: "photo")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.primary.opacity(0.03))
        )
    }

    private func deleteAssignment(_ assignment: LessonAssignment) {
        modelContext.delete(assignment)
        do {
            try modelContext.save()
        } catch {
            Self.logger.warning("Failed to save assignment deletion: \(error)")
        }
        // Reload to reflect deletion
        loadAssignments(limit: loadedAssignments.count >= Self.initialLoadCount ? nil : Self.initialLoadCount)
    }
}

#Preview {
    LessonAssignmentHistoryView()
}
