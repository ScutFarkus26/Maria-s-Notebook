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
    @Query private var students: [Student]
    // Fetch all ScopedNotes with non-nil presentationID (for counts)
    @Query(filter: #Predicate<ScopedNote> { $0.presentationID != nil }) private var allPresentationNotes: [ScopedNote]
    
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

    // Maps for quick lookup
    private var lessonsByID: [UUID: Lesson] {
        Dictionary(uniqueKeysWithValues: lessons.map { ($0.id, $0) })
    }
    private var studentsByID: [UUID: Student] {
        Dictionary(uniqueKeysWithValues: students.map { ($0.id, $0) })
    }

    // Group presentations by day (start of day)
    private func dayKey(_ date: Date) -> Date {
        calendar.startOfDay(for: date)
    }

    private var groupedByDay: [(day: Date, items: [Presentation])] {
        let dict = Dictionary(grouping: loadedPresentations) { p in
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
        #if DEBUG
        let t0 = Date()
        #endif
        // Build notes count cache from allPresentationNotes
        var counts: [String: Int] = [:]
        for n in allPresentationNotes {
            if let pid = n.presentationID { counts[pid, default: 0] += 1 }
        }
        notesCountCache = counts
        // Build student name cache
        var sNames: [UUID: String] = [:]
        for s in students {
            sNames[s.id] = StudentFormatter.displayName(for: s)
        }
        studentNameCache = sNames
        // Build lesson title cache (prefer name)
        var lTitles: [UUID: String] = [:]
        for l in lessons {
            lTitles[l.id] = LessonFormatter.titleOrFallback(l.name, fallback: "Lesson")
        }
        lessonTitleCache = lTitles
        #if DEBUG
        let dt = Date().timeIntervalSince(t0) * 1000
        print("[DEBUG] PresentationHistoryView caches build took \(Int(dt)) ms")
        #endif
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

    var body: some View {
        Group {
            if loadedPresentations.isEmpty {
                ContentUnavailableView(
                    "No Presentations Yet",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("Present lessons to see them here.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(Array(groupedByDay.enumerated()), id: \.element.day) { dayIndex, entry in
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
                    }
                    .padding(16)
                }
            }
        }
        .sheet(item: $selectedPresentation) { p in
            PresentationDetailSheet(presentationID: p.id) {
                selectedPresentation = nil
            }
        }
        .task {
            #if DEBUG
            let t0 = Date()
            #endif
            loadPresentations(limit: Self.initialLoadCount)
            if !hasBuiltCachesOnce {
                buildCaches()
                hasBuiltCachesOnce = true
            }
            #if DEBUG
            let dt = Date().timeIntervalSince(t0) * 1000
            print("[DEBUG] PresentationHistoryView initial load took \(Int(dt)) ms")
            #endif
        }
        .onChange(of: presentationIDs) { _, _ in
            // Reload when presentations change
            loadPresentations(limit: loadedPresentations.count >= Self.initialLoadCount ? nil : Self.initialLoadCount)
        }
        .onChange(of: allPresentationNotes.map(\.id)) { _, _ in
            buildCaches()
        }
        .onChange(of: lessons.map(\.id)) { _, _ in
            buildCaches()
        }
        .onChange(of: students.map(\.id)) { _, _ in
            buildCaches()
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
    }
}

#Preview {
    PresentationHistoryView()
}
