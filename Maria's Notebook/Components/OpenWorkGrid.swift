import SwiftUI
import CoreData

struct OpenWorkGrid: View {
    let works: [CDWorkModel]
    let lessonsByID: [UUID: CDLesson]
    let studentsByID: [UUID: CDStudent]
    let sortMode: WorkAgendaSortMode

    let onOpen: (CDWorkModel) -> Void
    let onMarkCompleted: (CDWorkModel) -> Void
    let onScheduleToday: (CDWorkModel) -> Void

    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.calendar) private var calendar
    
    @State private var cachedAgeSchoolDays: [UUID: Int] = [:]

    // MARK: - Layout
    // Choose 1 or 2 columns based on available width; never create 3+
    private func columns(for width: CGFloat) -> [GridItem] {
        return Array(repeating: GridItem(.flexible(minimum: 180, maximum: .infinity), spacing: 12), count: 4)
    }

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                LazyVGrid(
                    columns: columns(for: proxy.size.width),
                    alignment: .leading,
                    spacing: 8,
                    pinnedViews: [.sectionHeaders]
                ) {
                    ForEach(groupedSections, id: \.key) { section in
                        Section(header: groupHeader(title: section.key, count: section.items.count)) {
                            ForEach(section.items, id: \.id) { item in
                                let workID = item.work.id ?? UUID()
                                let ageSchoolDays = cachedAgeSchoolDays[workID] ?? 0
                                WorkCard.grid(
                                    work: item.work,
                                    lessonTitle: item.title,
                                    studentDisplay: item.student,
                                    needsAttention: item.needsAttention,
                                    ageSchoolDays: ageSchoolDays,
                                    onOpen: onOpen,
                                    onMarkCompleted: onMarkCompleted,
                                    onScheduleToday: onScheduleToday
                                )
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
            }
        }
        .task {
            await precomputeAgeValues()
        }
        .onChange(of: works.map(\.id)) { _, _ in
            Task {
                await precomputeAgeValues()
            }
        }
    }
    
    // MARK: - Performance Optimization
    
    /// Precompute age values once for all works to avoid repeated calculations during rendering
    private func precomputeAgeValues() async {
        let cache = SchoolDayCalculationCache.shared
        let today = Date()
        
        // Find date range for all works
        let allDates = works.map { work in
            let checkIns = (work.checkIns?.allObjects as? [CDWorkCheckIn]) ?? []
            let notes = (work.unifiedNotes?.allObjects as? [CDNote]) ?? []
            return WorkAgingPolicy.lastMeaningfulTouchDate(for: work, checkIns: checkIns, notes: notes)
        }
        
        guard let minDate = allDates.min(), allDates.max() != nil else { return }
        
        // Preload school days cache for entire range
        cache.preloadNonSchoolDays(from: minDate, to: today, using: viewContext, calendar: calendar)
        
        // Compute all age values using cached data
        var result: [UUID: Int] = [:]
        for work in works {
            let checkInsArray = (work.checkIns?.allObjects as? [CDWorkCheckIn]) ?? []
            let notesArray = (work.unifiedNotes?.allObjects as? [CDNote]) ?? []
            let lastTouch = WorkAgingPolicy.lastMeaningfulTouchDate(
                for: work, checkIns: checkInsArray, notes: notesArray
            )
            let age = cache.schoolDaysSinceCreation(
                createdAt: lastTouch, asOf: today, using: viewContext, calendar: calendar
            )
            if let workID = work.id {
                result[workID] = age
            }
        }
        
        cachedAgeSchoolDays = result
    }

    private func groupHeader(title: String, count: Int) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.headline.weight(.semibold))
            Spacer()
            Text("\(count)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.gray.opacity(UIConstants.OpacityConstants.moderate))
                )
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 6)
        .background(.bar)
    }

    // MARK: - Derived items
    private struct WorkGridItem: Identifiable {
        let id = UUID()
        let workID: UUID
        let work: CDWorkModel
        let title: String
        let student: String
        let needsAttention: Bool
        let metadata: String
    }

    // Group items by current sort mode; preserve overall order by grouping in the order items first appear
    private var groupedSections: [(key: String, items: [WorkGridItem])] {
        let items = sortedWorks
        var order: [String] = []
        var buckets: [String: [WorkGridItem]] = [:]
        for it in items {
            let key = groupKey(for: it)
            if buckets[key] == nil { order.append(key); buckets[key] = [] }
            buckets[key]?.append(it)
        }
        return order.map { key in (key: key, items: buckets[key] ?? []) }
    }

    private func groupKey(for item: WorkGridItem) -> String {
        switch sortMode {
        case .lesson:
            return item.title
        case .student:
            return item.student
        case .age:
            let days = ageDays(for: item.work)
            return ageBucketLabel(forDays: days)
        case .needsAttention:
            return item.needsAttention ? "Needs Attention" : "Other"
        }
    }

    private func ageBucketLabel(forDays days: Int) -> String {
        if days <= 0 {
            return "Today"
        } else if days <= 3 {
            return "1–3 days"
        } else if days <= 7 {
            return "4–7 days"
        } else if days <= 14 {
            return "8–14 days"
        } else if days <= 30 {
            return "15–30 days"
        } else {
            return "30+ days"
        }
    }

    private var sortedWorks: [WorkGridItem] {
        let mapped: [WorkGridItem] = works.map { w in
            let title = lessonTitle(forLessonID: w.lessonID)
            let student = studentName(for: w)
            let meta = metadata(for: w)
            let attention = needsAttention(for: w)
            return WorkGridItem(
                workID: w.id ?? UUID(), work: w, title: title,
                student: student, needsAttention: attention, metadata: meta
            )
        }
        switch sortMode {
        case .lesson:
            return mapped.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .student:
            return mapped.sorted { $0.student.localizedCaseInsensitiveCompare($1.student) == .orderedAscending }
        case .age:
            return mapped.sorted { ageDays(for: $0.work) > ageDays(for: $1.work) }
        case .needsAttention:
            return mapped.sorted { lhs, rhs in
                if lhs.needsAttention != rhs.needsAttention { return lhs.needsAttention && !rhs.needsAttention }
                // If both same attention, older first
                return ageDays(for: lhs.work) > ageDays(for: rhs.work)
            }
        }
    }

    // MARK: - Helpers
    private func lessonTitle(forLessonID lessonID: String) -> String {
        let name = lessonsByID[uuidString: lessonID]?.name ?? ""
        return LessonFormatter.titleOrFallback(name, fallback: "CDLesson \(String(lessonID.prefix(6)))")
    }

    private func studentName(for w: CDWorkModel) -> String {
        if let s = studentsByID[uuidString: w.studentID] {
            return StudentFormatter.displayName(for: s)
        }
        return "CDStudent"
    }

    private func metadata(for w: CDWorkModel) -> String {
        var parts: [String] = []
        parts.append((w.kind ?? .research).displayName)
        let age = ageDays(for: w)
        parts.append("\(age)d")
        return parts.joined(separator: " • ")
    }

    private func ageDays(for w: CDWorkModel) -> Int {
        let start = AppCalendar.startOfDay(w.createdAt ?? .distantPast)
        let now = AppCalendar.startOfDay(Date())
        let comps = AppCalendar.shared.dateComponents([.day], from: start, to: now)
        return comps.day ?? 0
    }

    private func needsAttention(for w: CDWorkModel) -> Bool {
        // Needs attention if overdue by due date, or last note is 10+ days old.
        if let due = w.dueAt {
            let today = AppCalendar.startOfDay(Date())
            if AppCalendar.startOfDay(due) < today { return true }
        }
        if let lastNoteDate = latestNoteDate(for: w) {
            return daysSince(lastNoteDate) >= 10
        }
        // Use cached age value instead of recalculating
        let schoolDaysSinceCreated: Int
        if let wID = w.id {
            schoolDaysSinceCreated = cachedAgeSchoolDays[wID] ?? 0
        } else {
            schoolDaysSinceCreated = 0
        }
        return schoolDaysSinceCreated >= 10
    }

    private func latestNoteDate(for w: CDWorkModel) -> Date? {
        let notes = (w.unifiedNotes?.allObjects as? [CDNote]) ?? []
        return notes.compactMap { note -> Date? in
            let updated = note.updatedAt ?? .distantPast
            let created = note.createdAt ?? .distantPast
            return max(updated, created)
        }.max()
    }

    private func daysSince(_ date: Date) -> Int {
        let start = AppCalendar.startOfDay(date)
        let now = AppCalendar.startOfDay(Date())
        let comps = AppCalendar.shared.dateComponents([.day], from: start, to: now)
        return comps.day ?? 0
    }
}

#Preview {
    OpenWorkGrid(
        works: [],
        lessonsByID: [:],
        studentsByID: [:],
        sortMode: .lesson,
        onOpen: { _ in },
        onMarkCompleted: { _ in },
        onScheduleToday: { _ in }
    )
    .previewEnvironment()
}
