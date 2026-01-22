import SwiftUI
import SwiftData

struct PresentationHistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.calendar) private var calendar

    // PAGINATION: Load presentations in batches instead of all at once
    private static let initialLoadCount = 50
    private static let loadMoreCount = 50
    
    @State private var loadedPresentations: [Presentation] = []
    @State private var hasLoadedMore = false
    // Fetch Lessons (for lookup)
    @Query private var lessons: [Lesson]
    // Fetch Students (for lookup)
    @Query private var studentsRaw: [Student]
    // DEDUPLICATION: CloudKit sync can create duplicate records with the same ID.
    private var students: [Student] { studentsRaw.uniqueByID }
    // Fetch Notes that are attached to a presentation
    @Query(sort: \Note.createdAt, order: .reverse) private var recentNotes: [Note]
    
    // Use @Query for change detection only
    @Query(sort: [SortDescriptor(\Presentation.presentedAt, order: .reverse)]) private var allPresentationsForChangeDetection: [Presentation]
    
    private var presentationIDs: [UUID] {
        allPresentationsForChangeDetection.map { $0.id }
    }

    @State private var selectedPresentation: Presentation? = nil
    @State private var notesCountCache: [String: Int] = [:]
    @State private var studentNameCache: [UUID: String] = [:]
    @State private var lessonTitleCache: [UUID: String] = [:]
    @State private var hasBuiltCachesOnce: Bool = false

    // Filter state
    @State private var selectedStudentIDs: Set<UUID> = []
    @State private var selectedSubjects: Set<String> = []
    @State private var searchText: String = ""

    @AppStorage("PresentationHistory.nameDisplayStyle") private var nameDisplayStyleRaw: String = "firstLastInitial"
    private enum NameDisplayStyle: String { case initials, firstLastInitial }
    private var nameDisplayStyle: NameDisplayStyle { NameDisplayStyle(rawValue: nameDisplayStyleRaw) ?? .firstLastInitial }

    private func displayName(for s: Student) -> String {
        let first = s.firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        let last = s.lastName.trimmingCharacters(in: .whitespacesAndNewlines)
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
        Dictionary(students.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    // Available subjects from lessons (sorted, non-empty only)
    private var availableSubjects: [String] {
        let subjects = Set(lessons.map { $0.subject.trimmingCharacters(in: .whitespacesAndNewlines) })
            .filter { !$0.isEmpty }
        return subjects.sorted()
    }

    // Filtered presentations
    private var filteredPresentations: [Presentation] {
        loadedPresentations.filter { p in
            // Student filter
            if !selectedStudentIDs.isEmpty {
                let presentationStudentIDs = Set(p.studentIDs.compactMap { UUID(uuidString: $0) })
                if presentationStudentIDs.isDisjoint(with: selectedStudentIDs) { return false }
            }

            // Subject filter
            if !selectedSubjects.isEmpty {
                if let lessonID = CloudKitUUID.uuid(from: p.lessonID),
                   let lesson = lessonsByID[lessonID] {
                    let subject = lesson.subject.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !selectedSubjects.contains(subject) { return false }
                } else {
                    // No lesson found, exclude if filtering by subject
                    return false
                }
            }

            // Search filter
            if !searchText.isEmpty {
                let titleText = title(for: p).lowercased()
                let query = searchText.lowercased()
                if !titleText.contains(query) { return false }
            }

            return true
        }
    }

    // Group presentations by day (start of day)
    private func dayKey(_ date: Date) -> Date {
        calendar.startOfDay(for: date)
    }

    private var groupedByDay: [(day: Date, items: [Presentation])] {
        let dict = Dictionary(grouping: filteredPresentations) { p in
            dayKey(p.presentedAt)
        }
        .mapValues { arr in arr.sorted { lhs, rhs in lhs.presentedAt > rhs.presentedAt } }
        let days = dict.keys.sorted(by: >)
        return days.map { ($0, dict[$0] ?? []) }
    }
    
    private func loadPresentations(limit: Int? = nil) {
        var descriptor = FetchDescriptor<Presentation>(
            sortBy: [
                SortDescriptor(\Presentation.presentedAt, order: .reverse),
                SortDescriptor(\Presentation.createdAt, order: .reverse)
            ]
        )
        if let limit = limit {
            descriptor.fetchLimit = limit
        }
        loadedPresentations = modelContext.safeFetch(descriptor)
        // If we requested a limit and got fewer results, we've loaded all available
        if let limit = limit {
            hasLoadedMore = loadedPresentations.count < limit
        } else {
            hasLoadedMore = false // No limit means we loaded everything
        }
    }
    
    private func loadMorePresentations() {
        guard !hasLoadedMore else { return }
        let currentCount = loadedPresentations.count
        var descriptor = FetchDescriptor<Presentation>(
            sortBy: [
                SortDescriptor(\Presentation.presentedAt, order: .reverse),
                SortDescriptor(\Presentation.createdAt, order: .reverse)
            ]
        )
        descriptor.fetchLimit = currentCount + Self.loadMoreCount
        let newResults = modelContext.safeFetch(descriptor)
        loadedPresentations = newResults
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

    private func buildCaches() {
        // Build notes count cache from recentNotes (filtered to presentation notes)
        var counts: [String: Int] = [:]
        
        // Count notes attached to presentations
        let presentationNotes = recentNotes.filter { $0.presentation != nil }
        for n in presentationNotes {
            if let p = n.presentation {
                counts[p.id.uuidString, default: 0] += 1
            }
        }
        
        notesCountCache = counts
        // Build student name cache
        var sNames: [UUID: String] = [:]
        for s in students {
            sNames[s.id] = displayName(for: s)
        }
        studentNameCache = sNames
        // Build lesson title cache (prefer name)
        var lTitles: [UUID: String] = [:]
        for l in lessons {
            lTitles[l.id] = LessonFormatter.titleOrFallback(l.name, fallback: "Lesson")
        }
        lessonTitleCache = lTitles
    }

    // Resolve title: prefer lessonTitleSnapshot else lookup lesson by ID
    private func title(for p: Presentation) -> String {
        if let snap = p.lessonTitleSnapshot?.trimmed(), !snap.isEmpty {
            return snap
        }
        if let lid = CloudKitUUID.uuid(from: p.lessonID), let t = lessonTitleCache[lid] {
            return LessonFormatter.titleOrFallback(t, fallback: "Lesson")
        }
        return "Lesson"
    }

    // Student names or count string
    private func studentNamesOrCount(for p: Presentation) -> String {
        let ids: [UUID] = p.studentIDs.compactMap { UUID(uuidString: $0) }
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
                  let student = students.first(where: { $0.id == id }) {
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
                ForEach(students) { student in
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
                if loadedPresentations.isEmpty {
                    ContentUnavailableView(
                        "No Presentations Yet",
                        systemImage: "clock.arrow.circlepath",
                        description: Text("Present lessons to see them here.")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if filteredPresentations.isEmpty {
                    ContentUnavailableView(
                        "No Matching Presentations",
                        systemImage: "magnifyingglass",
                        description: Text("Try adjusting your filters.")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    presentationsList
                }
            }
        }
    }
    
    private var presentationsList: some View {
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
    private func daySection(dayIndex: Int, entry: (day: Date, items: [Presentation])) -> some View {
        Section {
            ForEach(Array(entry.items.enumerated()), id: \.element.id) { itemIndex, p in
                row(for: p)
                    .onTapGesture { selectedPresentation = p }
                    .onAppear {
                        // Load more when near the end
                        if dayIndex == groupedByDay.count - 1,
                           itemIndex >= entry.items.count - 5 {
                            loadMorePresentations()
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
            .sheet(item: $selectedPresentation) { p in
                PresentationDetailSheet(presentationID: p.id) {
                    selectedPresentation = nil
                }
            }
            .task {
                loadPresentations(limit: Self.initialLoadCount)
                if !hasBuiltCachesOnce {
                    buildCaches()
                    hasBuiltCachesOnce = true
                }
            }
            .onChange(of: presentationIDs) { _, _ in
                // Reload when presentations change
                loadPresentations(limit: loadedPresentations.count >= Self.initialLoadCount ? nil : Self.initialLoadCount)
            }
            .onChange(of: recentNotes.map(\.id)) { _, _ in
                buildCaches()
            }
            .onChange(of: lessons.map(\.id)) { _, _ in
                buildCaches()
            }
            .onChange(of: students.map(\.id)) { _, _ in
                buildCaches()
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
    private func row(for p: Presentation) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title(for: p))
                    .font(.system(size: AppTheme.FontSize.body, weight: .semibold, design: .rounded))
                HStack(spacing: 6) {
                    Text(Self.timeFormatter.string(from: p.presentedAt))
                    Text("•")
                    Text(studentNamesOrCount(for: p))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            if notesCountCache[p.id.uuidString, default: 0] > 0 {
                Image(systemName: "note.text")
                    .foregroundStyle(.secondary)
            }
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
        .contextMenu {
            Button {
                selectedPresentation = p
            } label: {
                Label("View Details", systemImage: "eye")
            }

            if let lessonID = CloudKitUUID.uuid(from: p.lessonID) {
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
                deletePresentation(p)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private func deletePresentation(_ presentation: Presentation) {
        modelContext.delete(presentation)
        try? modelContext.save()
        // Reload to reflect deletion
        loadPresentations(limit: loadedPresentations.count >= Self.initialLoadCount ? nil : Self.initialLoadCount)
    }
}

#Preview {
    PresentationHistoryView()
}
