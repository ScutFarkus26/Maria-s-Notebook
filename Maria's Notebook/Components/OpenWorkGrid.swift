import SwiftUI
import CoreData

struct OpenWorkGrid: View {
    let works: [CDWorkModel]
    let lessonsByID: [UUID: CDLesson]
    let studentsByID: [UUID: CDStudent]
    /// Work the partition placed in `.attention`. Passed in rather than
    /// recomputed so the badge cannot disagree with the Attention list.
    let attentionWorkIDs: Set<UUID>
    let sortMode: WorkAgendaSortMode
    var focusedWorkID: UUID?
    /// Command-click selection. Optional so the grid keeps working on the
    /// surfaces that have no selection of their own (a student's overview).
    var selection: WorkspaceMultiSelection?

    let onOpen: (CDWorkModel) -> Void
    let onMarkCompleted: (CDWorkModel) -> Void
    /// Puts a work item on a day to be checked, wherever the card's Schedule
    /// menu got the day from.
    let onSchedule: (CDWorkModel, Date) -> Void
    /// Nil hides Delete from the card menus. A grid that only reports on work
    /// — a student's overview — is not where a record gets destroyed.
    var onDeleted: (() -> Void)?

    // Not private: the deletion helpers live in OpenWorkGrid+Deletion.swift.
    @Environment(\.managedObjectContext) var viewContext
    
    @State private var cachedAgeSchoolDays: [UUID: Int] = [:]

    /// Held here rather than on each card so one grid has one dialog: it keeps
    /// the right count, and it survives the card scrolling out from under it.
    @State var pendingDeletion: [CDWorkModel] = []

    // MARK: - Layout
    // Keep cards legible on compact devices and take advantage of Mac width
    // without squeezing the content into the previous fixed four columns.
    private func columns(for width: CGFloat) -> [GridItem] {
        let count: Int
        if width < 620 {
            count = 1
        } else if width < 1_050 {
            count = 2
        } else {
            count = 3
        }
        return Array(
            repeating: GridItem(.flexible(minimum: 260, maximum: .infinity), spacing: 12),
            count: count
        )
    }

    var body: some View {
        GeometryReader { proxy in
            ScrollViewReader { reader in
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
                                        selection: selection,
                                        menuTargets: { menuTargets(for: item.work) },
                                        onRequestDelete: onDeleted == nil
                                            ? nil
                                            : { pendingDeletion = $0 },
                                        onOpen: onOpen,
                                        onMarkCompleted: onMarkCompleted,
                                        onSchedule: onSchedule
                                    )
                                    .padding(2)
                                    .background(
                                        workID == focusedWorkID
                                            ? Color.accentColor.opacity(0.12)
                                            : Color.clear,
                                        in: RoundedRectangle(cornerRadius: 14)
                                    )
                                    .overlay {
                                        if workID == focusedWorkID {
                                            RoundedRectangle(cornerRadius: 14)
                                                .stroke(Color.accentColor, lineWidth: 2)
                                        }
                                    }
                                    .id(workID)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                }
                .task(id: focusedWorkID) {
                    guard let focusedWorkID else { return }
                    await Task.yield()
                    withAnimation { reader.scrollTo(focusedWorkID, anchor: .center) }
                }
            }
        }
        .workspaceDeletionConfirmation(
            pending: $pendingDeletion,
            title: deletionTitle,
            confirmTitle: deletionConfirmTitle,
            message: deletionMessage,
            onConfirm: performPendingDeletion
        )
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
        let cache = SchoolCalendarService.shared
        let today = Date()
        
        // Find date range for all works
        let allDates = works.map { work in
            let checkIns = (work.checkIns?.allObjects as? [CDWorkCheckIn]) ?? []
            let notes = (work.unifiedNotes?.allObjects as? [CDNote]) ?? []
            return WorkAgingPolicy.lastMeaningfulTouchDate(for: work, checkIns: checkIns, notes: notes)
        }
        
        guard let minDate = allDates.min(), allDates.max() != nil else { return }
        
        // Preload school days cache for entire range
        cache.preloadNonSchoolDays(from: minDate, to: today, using: viewContext)
        
        // Compute all age values using cached data
        var result: [UUID: Int] = [:]
        for work in works {
            let checkInsArray = (work.checkIns?.allObjects as? [CDWorkCheckIn]) ?? []
            let notesArray = (work.unifiedNotes?.allObjects as? [CDNote]) ?? []
            let lastTouch = WorkAgingPolicy.lastMeaningfulTouchDate(
                for: work, checkIns: checkInsArray, notes: notesArray
            )
            let age = cache.schoolDaysSinceCreation(
                createdAt: lastTouch, asOf: today, using: viewContext
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
        let id: NSManagedObjectID
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
            let key = sequenceKey(for: it)
            if buckets[key] == nil { order.append(key); buckets[key] = [] }
            buckets[key]?.append(it)
        }
        return order.map { key in (key: key, items: buckets[key] ?? []) }
    }

    private func sequenceKey(for item: WorkGridItem) -> String {
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
                id: w.objectID, workID: w.id ?? UUID(), work: w, title: title,
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
        return LessonFormatter.titleOrFallback(name, fallback: "Lesson \(String(lessonID.prefix(6)))")
    }

    private func studentName(for w: CDWorkModel) -> String {
        if let s = studentsByID[uuidString: w.studentID] {
            return StudentFormatter.displayName(for: s)
        }
        return "Student"
    }

    private func metadata(for w: CDWorkModel) -> String {
        var parts: [String] = []
        parts.append((w.kind ?? .research).displayName)
        let age = ageDays(for: w)
        parts.append("\(age)d")
        return parts.joined(separator: " • ")
    }

    private func ageDays(for w: CDWorkModel) -> Int {
        // Clamped to the school-year counter epoch (see `SchoolYearCounters`).
        let start = AppCalendar.startOfDay(SchoolYearCounters.countFrom(w.createdAt ?? .distantPast))
        let now = AppCalendar.startOfDay(Date())
        let comps = AppCalendar.shared.dateComponents([.day], from: start, to: now)
        return comps.day ?? 0
    }

    /// The badge reads the workspace's one triage pass rather than re-running
    /// the rule per card. It used to rebuild `WorkTriageInput` here from
    /// `cachedAgeSchoolDays`, which was a third copy of a question the Attention
    /// list was already answering over the same array.
    private func needsAttention(for w: CDWorkModel) -> Bool {
        w.id.map(attentionWorkIDs.contains) ?? false
    }

}

#Preview {
    OpenWorkGrid(
        works: [],
        lessonsByID: [:],
        studentsByID: [:],
        attentionWorkIDs: [],
        sortMode: .lesson,
        onOpen: { _ in },
        onMarkCompleted: { _ in },
        onSchedule: { _, _ in }
    )
    .previewEnvironment()
}
