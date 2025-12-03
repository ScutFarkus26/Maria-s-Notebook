import SwiftUI
import SwiftData

struct WorkView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var hSize

#if os(macOS)
    @Environment(\.openWindow) private var openWindow
#endif

    // Data sources
    @Query(sort: [
        SortDescriptor(\Student.lastName),
        SortDescriptor(\Student.firstName)
    ]) private var students: [Student]

    @Query(sort: \StudentLesson.createdAt, order: .forward) private var studentLessons: [StudentLesson]
    @Query(sort: \Lesson.name, order: .forward) private var lessons: [Lesson]
    @Query(sort: \WorkModel.createdAt, order: .reverse) private var workItems: [WorkModel]

    // Add Work sheet state
    @State private var isPresentingAddWork = false
    @State private var selectedWorkID: UUID? = nil

    @State private var isShowingStudentFilterPopover = false
    @State private var studentFilterSearchText: String = ""

    @SceneStorage("WorkView.selectedWorkType") private var workSelectedTypeRaw: String = ""
    @SceneStorage("WorkView.selectedSubject") private var workSelectedSubjectRaw: String = ""
    @SceneStorage("WorkView.selectedStudentIDs") private var workSelectedStudentIDsRaw: String = ""
    @SceneStorage("WorkView.dateFilter") private var workDateFilterRaw: String = "thisWeek"
    @SceneStorage("WorkView.searchText") private var workSearchTextRaw: String = ""
    @SceneStorage("WorkView.grouping") private var workGroupingRaw: String = "none"

    private enum DateFilter: String, CaseIterable {
        case all = "All Dates"
        case today = "Today"
        case thisWeek = "This Week"
        case lastTwoWeeks = "Last Two Weeks"
        case overTwoWeeks = "Over Two Weeks"

        var storageKey: String {
            switch self {
            case .all: return "all"
            case .today: return "today"
            case .thisWeek: return "thisWeek"
            case .lastTwoWeeks: return "lastTwoWeeks"
            case .overTwoWeeks: return "overTwoWeeks"
            }
        }
    }

    private enum Grouping: String {
        case none, type, date, checkIns
    }
    private var grouping: Grouping { Grouping(rawValue: workGroupingRaw) ?? .none }

    private var dateFilter: DateFilter {
        get {
            switch workDateFilterRaw {
            case "all": return .all
            case "today": return .today
            case "lastTwoWeeks": return .lastTwoWeeks
            case "overTwoWeeks": return .overTwoWeeks
            default: return .thisWeek
            }
        }
        set {
            switch newValue {
            case .all: workDateFilterRaw = "all"
            case .today: workDateFilterRaw = "today"
            case .thisWeek: workDateFilterRaw = "thisWeek"
            case .lastTwoWeeks: workDateFilterRaw = "lastTwoWeeks"
            case .overTwoWeeks: workDateFilterRaw = "overTwoWeeks"
            }
        }
    }

    private func displayName(for student: Student) -> String {
        let parts = student.fullName.split(separator: " ")
        guard let first = parts.first else { return student.fullName }
        let lastInitial = parts.dropFirst().first?.first.map { String($0) } ?? ""
        return lastInitial.isEmpty ? String(first) : "\(first) \(lastInitial)."
    }

    private var selectedWorkType: WorkModel.WorkType? {
        WorkModel.WorkType(rawValue: workSelectedTypeRaw)
    }

    private var selectedSubject: String? {
        workSelectedSubjectRaw.isEmpty ? nil : workSelectedSubjectRaw
    }

    private var subjects: [String] {
        let existing = Array(Set(lessons
            .map { $0.subject.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        )).sorted()
        return FilterOrderStore.loadSubjectOrder(existing: existing)
    }

    private func linkedDate(for work: WorkModel) -> Date {
        if let slID = work.studentLessonID, let sl = studentLessonsByID[slID] {
            if let given = sl.givenAt { return given }
            if let sched = sl.scheduledFor { return sched }
        }
        return work.createdAt
    }

    private var filteredWorks: [WorkModel] {
        var base = workItems

        // Removed Work type filter per instructions

        // Subject filter (via linked StudentLesson -> Lesson.subject)
        if let subject = selectedSubject {
            base = base.filter { work in
                guard let slID = work.studentLessonID, let sl = studentLessonsByID[slID], let lesson = lessonsByID[sl.lessonID] else { return false }
                return lesson.subject.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(subject) == .orderedSame
            }
        }

        // Student filter (works that include ANY of the selected students)
        let selectedIDs = selectedStudentIDsSet
        if !selectedIDs.isEmpty {
            base = base.filter { !Set($0.studentIDs).isDisjoint(with: selectedIDs) }
        }

        // Removed Date filter per instructions

        // Text search on notes, title and linked lesson name
        let query = workSearchTextRaw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !query.isEmpty {
            base = base.filter { work in
                let notesMatch = work.notes.lowercased().contains(query)
                let titleMatch = work.title.lowercased().contains(query)
                var lessonMatch = false
                if let slID = work.studentLessonID, let sl = studentLessonsByID[slID], let lesson = lessonsByID[sl.lessonID] {
                    lessonMatch = lesson.name.lowercased().contains(query)
                }
                return titleMatch || notesMatch || lessonMatch
            }
        }

        return base
    }

    // Helper maps for quick lookup
    private var studentsByID: [UUID: Student] { Dictionary(uniqueKeysWithValues: students.map { ($0.id, $0) }) }
    private var lessonsByID: [UUID: Lesson] { Dictionary(uniqueKeysWithValues: lessons.map { ($0.id, $0) }) }
    private var studentLessonsByID: [UUID: StudentLesson] { Dictionary(uniqueKeysWithValues: studentLessons.map { ($0.id, $0) }) }

    private var sectionsByType: [String: [WorkModel]] {
        Dictionary(grouping: filteredWorks, by: { $0.workType.rawValue })
    }
    private var sectionsByDate: [String: [WorkModel]] {
        let cal = Calendar.current
        let today = Date()
        return Dictionary(grouping: filteredWorks, by: { work in
            let d = linkedDate(for: work)
            if cal.isDateInToday(d) { return "Today" }
            if cal.isDate(d, equalTo: today, toGranularity: .weekOfYear) { return "This Week" }
            return "Earlier"
        })
    }
    
    private func nextIncompleteCheckIn(for work: WorkModel) -> WorkCheckIn? {
        let incomplete = work.checkIns.filter { $0.status != .completed && $0.status != .skipped }
        return incomplete.min(by: { $0.date < $1.date })
    }
    
    private var sectionsByCheckIns: [String: [WorkModel]] {
        let cal = Calendar.current
        let today = Date()
        return Dictionary(grouping: filteredWorks, by: { work in
            guard let checkIn = nextIncompleteCheckIn(for: work) else {
                return "No Check-Ins"
            }
            let d = checkIn.date
            if cal.isDateInToday(d) { return "Today" }
            if cal.isDateInTomorrow(d) { return "Tomorrow" }
            if cal.isDate(d, equalTo: today, toGranularity: .weekOfYear) { return "This Week" }
            if d < today { return "Overdue" }
            return "Future"
        })
    }
    
    private var sectionOrder: [String] {
        switch grouping {
        case .none: return []
        case .type: return [WorkModel.WorkType.research.rawValue, WorkModel.WorkType.followUp.rawValue, WorkModel.WorkType.practice.rawValue]
        case .date: return ["Today", "This Week", "Earlier"]
        case .checkIns: return ["Overdue", "Today", "Tomorrow", "This Week", "Future", "No Check-Ins"]
        }
    }
    
    private func itemsForSection(_ key: String) -> [WorkModel] {
        switch grouping {
        case .none: return []
        case .type: return sectionsByType[key] ?? []
        case .date: return sectionsByDate[key] ?? []
        case .checkIns: return sectionsByCheckIns[key] ?? []
        }
    }
    private func sectionIcon(for key: String) -> String {
        switch key {
        case WorkModel.WorkType.research.rawValue: return "magnifyingglass.circle.fill"
        case WorkModel.WorkType.followUp.rawValue: return "bolt.circle.fill"
        case WorkModel.WorkType.practice.rawValue: return "arrow.triangle.2.circlepath.circle.fill"
        case "Today": return "sun.max.fill"
        case "This Week": return "calendar"
        case "Tomorrow": return "sunrise.fill"
        case "Overdue": return "exclamationmark.triangle.fill"
        case "Future": return "calendar.badge.clock"
        case "No Check-Ins": return "calendar.badge.exclamationmark"
        default: return "clock"
        }
    }

    // Multi-select student filter storage and helpers
    private var selectedStudentIDsSet: Set<UUID> {
        get {
            let parts = workSelectedStudentIDsRaw.split(separator: ",").map { String($0) }
            let uuids = parts.compactMap { UUID(uuidString: $0) }
            return Set(uuids)
        }
        set {
            workSelectedStudentIDsRaw = newValue.map { $0.uuidString }.joined(separator: ",")
        }
    }

    private var filteredStudentsForFilter: [Student] {
        let q = studentFilterSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let base: [Student]
        if q.isEmpty {
            base = students
        } else {
            base = students.filter { s in
                let f = s.firstName.lowercased()
                let l = s.lastName.lowercased()
                let full = s.fullName.lowercased()
                return f.contains(q) || l.contains(q) || full.contains(q)
            }
        }
        return base.sorted { lhs, rhs in
            let lf = lhs.firstName.localizedCaseInsensitiveCompare(rhs.firstName)
            if lf == .orderedSame {
                return lhs.lastName.localizedCaseInsensitiveCompare(rhs.lastName) == .orderedAscending
            }
            return lf == .orderedAscending
        }
    }

    private var studentFilterPopover: some View {
        VStack(spacing: 10) {
            // Search field
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search students", text: $studentFilterSearchText)
                    .textFieldStyle(.plain)
                if !studentFilterSearchText.isEmpty {
                    Button {
                        studentFilterSearchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
            )

            Divider().padding(.top, 2)

            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(filteredStudentsForFilter, id: \.id) { s in
                        Button {
                            var set = selectedStudentIDsSet
                            if set.contains(s.id) {
                                set.remove(s.id)
                            } else {
                                set.insert(s.id)
                            }
                            workSelectedStudentIDsRaw = set.map { $0.uuidString }.joined(separator: ",")
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: selectedStudentIDsSet.contains(s.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selectedStudentIDsSet.contains(s.id) ? Color.accentColor : Color.secondary)
                                Text(displayName(for: s))
                                    .foregroundStyle(.primary)
                                Spacer(minLength: 0)
                            }
                            .contentShape(Rectangle())
                            .padding(.vertical, 6)
                            .padding(.horizontal, 6)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 4)
            }
            .frame(maxHeight: 280)

            Divider()

            HStack {
                Button {
                    workSelectedStudentIDsRaw = ""
                } label: {
                    Text("Clear")
                }
                .buttonStyle(.borderless)

                Spacer()

                Button("Done") {
                    isShowingStudentFilterPopover = false
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(12)
        .frame(minWidth: 320)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Students")
                .font(.system(size: AppTheme.FontSize.caption, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)

            Button {
                isShowingStudentFilterPopover = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "person.2")
                    Text(selectedStudentIDsSet.isEmpty ? "All Students" : "\(selectedStudentIDsSet.count) selected")
                }
                .font(.system(size: AppTheme.FontSize.body, weight: .semibold, design: .rounded))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.primary.opacity(0.08), in: Capsule())
            }
            .buttonStyle(.plain)
            .popover(isPresented: $isShowingStudentFilterPopover, arrowEdge: .top) {
                studentFilterPopover
            }

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search notes or lesson names", text: $workSearchTextRaw)
                if !workSearchTextRaw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Button {
                        workSearchTextRaw = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
            )
            .padding(.trailing, 16)

            // Insert Group By section here per instructions
            Text("Group By")
                .font(.system(size: AppTheme.FontSize.caption, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.top, 8)

            SidebarFilterButton(
                icon: "rectangle.3.group",
                title: "None",
                color: .accentColor,
                isSelected: grouping == .none
            ) {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85, blendDuration: 0.1)) {
                    workGroupingRaw = "none"
                }
            }

            SidebarFilterButton(
                icon: "square.grid.2x2",
                title: "Type",
                color: .accentColor,
                isSelected: grouping == .type
            ) {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85, blendDuration: 0.1)) {
                    workGroupingRaw = "type"
                }
            }

            SidebarFilterButton(
                icon: "calendar",
                title: "Date",
                color: .accentColor,
                isSelected: grouping == .date
            ) {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85, blendDuration: 0.1)) {
                    workGroupingRaw = "date"
                }
            }

            SidebarFilterButton(
                icon: "checklist",
                title: "Check Ins",
                color: .accentColor,
                isSelected: grouping == .checkIns
            ) {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85, blendDuration: 0.1)) {
                    workGroupingRaw = "checkIns"
                }
            }

            Text("Subject")
                .font(.system(size: AppTheme.FontSize.caption, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.top, 8)

            SidebarFilterButton(
                icon: "rectangle.3.group",
                title: "All Subjects",
                color: .accentColor,
                isSelected: selectedSubject == nil
            ) {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85, blendDuration: 0.1)) {
                    workSelectedSubjectRaw = ""
                }
            }

            ForEach(subjects, id: \.self) { subject in
                SidebarFilterButton(
                    icon: "folder.fill",
                    title: subject,
                    color: AppColors.color(forSubject: subject),
                    isSelected: selectedSubject?.caseInsensitiveCompare(subject) == .orderedSame
                ) {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85, blendDuration: 0.1)) {
                        workSelectedSubjectRaw = subject
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 16)
        .padding(.leading, 16)
        .frame(width: 200, alignment: .topLeading)
        .background(Color.gray.opacity(0.08))
    }

#if !os(macOS)
    private var compactWorkLayout: some View {
        VStack(spacing: 0) {
            // Inline search
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search notes or lesson names", text: $workSearchTextRaw)
                if !workSearchTextRaw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Button { workSearchTextRaw = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
            )
            .padding(.horizontal)
            .padding(.top, 8)

            // Removed Grouping picker HStack here per instructions

            Divider()

            // Content area mirrors desktop logic
            Group {
                if workItems.isEmpty {
                    VStack(spacing: 8) {
                        Text("No work yet")
                            .font(.system(size: AppTheme.FontSize.titleMedium, weight: .semibold, design: .rounded))
                        Text("Tap the plus to add work.")
                            .font(.system(size: AppTheme.FontSize.body, weight: .regular, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if filteredWorks.isEmpty {
                    VStack(spacing: 8) {
                        Text("No work matches your filters")
                            .font(.system(size: AppTheme.FontSize.titleMedium, weight: .semibold, design: .rounded))
                        Text("Adjust filters from the toolbar.")
                            .font(.system(size: AppTheme.FontSize.body, weight: .regular, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    if grouping == .none {
                        WorkCardsGridView(
                            works: filteredWorks,
                            studentsByID: studentsByID,
                            lessonsByID: lessonsByID,
                            studentLessonsByID: studentLessonsByID,
                            onTapWork: { work in selectedWorkID = work.id },
                            onToggleComplete: { work in
                                work.completedAt = work.isCompleted ? nil : Date()
                                do { try modelContext.save() } catch { }
                            }
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 24) {
                                ForEach(sectionOrder, id: \.self) { key in
                                    let items = itemsForSection(key)
                                    if !items.isEmpty {
                                        HStack(spacing: 10) {
                                            Image(systemName: sectionIcon(for: key))
                                                .foregroundStyle(.secondary)
                                            Text(key)
                                                .font(.system(size: AppTheme.FontSize.caption, weight: .semibold, design: .rounded))
                                                .foregroundStyle(.secondary)
                                        }
                                        WorkCardsGridView(
                                            works: items,
                                            studentsByID: studentsByID,
                                            lessonsByID: lessonsByID,
                                            studentLessonsByID: studentLessonsByID,
                                            onTapWork: { work in selectedWorkID = work.id },
                                            onToggleComplete: { work in
                                                work.completedAt = work.isCompleted ? nil : Date()
                                                do { try modelContext.save() } catch { }
                                            },
                                            embedInScrollView: false,
                                            hideTypeBadge: (grouping == .type)
                                        )
                                    }
                                }
                            }
                            .padding(24)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
        }
        // Anchor for student filter popover on compact
        .popover(isPresented: $isShowingStudentFilterPopover, arrowEdge: .top) {
            studentFilterPopover
        }
    }

    private var filtersMenu: some View {
        Menu {
            Section("Students") {
                Button("Select Students…") { isShowingStudentFilterPopover = true }
                Button("Clear Selected") { workSelectedStudentIDsRaw = "" }
            }
            Section("Subject") {
                Button("All Subjects") { workSelectedSubjectRaw = "" }
                ForEach(subjects, id: \.self) { subject in
                    Button(subject) { workSelectedSubjectRaw = subject }
                }
            }
            Section("Group By") {
                Button("None") { workGroupingRaw = "none" }
                Button("Type") { workGroupingRaw = "type" }
                Button("Date") { workGroupingRaw = "date" }
                Button("Check Ins") { workGroupingRaw = "checkIns" }
            }
        } label: {
            Image(systemName: "line.3.horizontal.decrease.circle")
        }
    }
#endif

    var body: some View {
        NavigationStack {
            Group {
                if hSize == .compact {
                    compactWorkLayout
                } else {
                    HStack(spacing: 0) {
                        sidebar

                        Divider()

                        VStack(spacing: 0) {
                            // Removed Grouping picker HStack here per instructions

                            Group {
                                if workItems.isEmpty {
                                    VStack(spacing: 8) {
                                        Text("No work yet")
                                            .font(.system(size: AppTheme.FontSize.titleMedium, weight: .semibold, design: .rounded))
                                        Text("Click the plus button to add work.")
                                            .font(.system(size: AppTheme.FontSize.body, weight: .regular, design: .rounded))
                                            .foregroundStyle(.secondary)
                                    }
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                } else if filteredWorks.isEmpty {
                                    VStack(spacing: 8) {
                                        Text("No work matches your filters")
                                            .font(.system(size: AppTheme.FontSize.titleMedium, weight: .semibold, design: .rounded))
                                        Text("Try adjusting the filters on the left.")
                                            .font(.system(size: AppTheme.FontSize.body, weight: .regular, design: .rounded))
                                            .foregroundStyle(.secondary)
                                    }
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                } else {
#if os(macOS)
                                    if grouping == .none {
                                        WorkCardsGridView(
                                            works: filteredWorks,
                                            studentsByID: studentsByID,
                                            lessonsByID: lessonsByID,
                                            studentLessonsByID: studentLessonsByID,
                                            onTapWork: { work in
                                                openWindow(id: "WorkDetailWindow", value: work.id)
                                            },
                                            onToggleComplete: { work in
                                                work.completedAt = work.isCompleted ? nil : Date()
                                                do { try modelContext.save() } catch { }
                                            }
                                        )
                                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    } else {
                                        ScrollView {
                                            VStack(alignment: .leading, spacing: 24) {
                                                ForEach(sectionOrder, id: \.self) { key in
                                                    let items = itemsForSection(key)
                                                    if !items.isEmpty {
                                                        HStack(spacing: 10) {
                                                            Image(systemName: sectionIcon(for: key))
                                                                .foregroundStyle(.secondary)
                                                            Text(key)
                                                                .font(.system(size: AppTheme.FontSize.caption, weight: .semibold, design: .rounded))
                                                                .foregroundStyle(.secondary)
                                                        }
                                                        WorkCardsGridView(
                                                            works: items,
                                                            studentsByID: studentsByID,
                                                            lessonsByID: lessonsByID,
                                                            studentLessonsByID: studentLessonsByID,
                                                            onTapWork: { work in openWindow(id: "WorkDetailWindow", value: work.id) },
                                                            onToggleComplete: { work in
                                                                work.completedAt = work.isCompleted ? nil : Date()
                                                                do { try modelContext.save() } catch { }
                                                            },
                                                            embedInScrollView: false,
                                                            hideTypeBadge: (grouping == .type)
                                                        )
                                                    }
                                                }
                                            }
                                            .padding(24)
                                        }
                                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    }
#else
                                    if grouping == .none {
                                        WorkCardsGridView(
                                            works: filteredWorks,
                                            studentsByID: studentsByID,
                                            lessonsByID: lessonsByID,
                                            studentLessonsByID: studentLessonsByID,
                                            onTapWork: { work in
                                                selectedWorkID = work.id
                                            },
                                            onToggleComplete: { work in
                                                work.completedAt = work.isCompleted ? nil : Date()
                                                do { try modelContext.save() } catch { }
                                            }
                                        )
                                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    } else {
                                        ScrollView {
                                            VStack(alignment: .leading, spacing: 24) {
                                                ForEach(sectionOrder, id: \.self) { key in
                                                    let items = itemsForSection(key)
                                                    if !items.isEmpty {
                                                        HStack(spacing: 10) {
                                                            Image(systemName: sectionIcon(for: key))
                                                                .foregroundStyle(.secondary)
                                                            Text(key)
                                                                .font(.system(size: AppTheme.FontSize.caption, weight: .semibold, design: .rounded))
                                                                .foregroundStyle(.secondary)
                                                        }
                                                        WorkCardsGridView(
                                                            works: items,
                                                            studentsByID: studentsByID,
                                                            lessonsByID: lessonsByID,
                                                            studentLessonsByID: studentLessonsByID,
                                                            onTapWork: { work in selectedWorkID = work.id },
                                                            onToggleComplete: { work in
                                                                work.completedAt = work.isCompleted ? nil : Date()
                                                                do { try modelContext.save() } catch { }
                                                            },
                                                            embedInScrollView: false,
                                                            hideTypeBadge: (grouping == .type)
                                                        )
                                                    }
                                                }
                                            }
                                            .padding(24)
                                        }
                                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    }
#endif
                                }
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .overlay(alignment: .topTrailing) {
                                Button {
                                    isPresentingAddWork = true
                                } label: {
                                    Image(systemName: "plus.circle.fill")
                                        .font(.system(size: AppTheme.FontSize.titleXLarge))
                                        .foregroundStyle(.green)
                                }
                                .buttonStyle(.plain)
                                .padding()
                            }
                        }
                    }
                }
            }
        }
#if !os(macOS)
        .toolbar {
            if hSize == .compact {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isPresentingAddWork = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    filtersMenu
                }
            }
        }
#endif
        .sheet(isPresented: $isPresentingAddWork) {
            AddWorkView {
                isPresentingAddWork = false
            }
        }
#if !os(macOS)
        .sheet(isPresented: Binding(get: { selectedWorkID != nil }, set: { if !$0 { selectedWorkID = nil } })) {
            if let id = selectedWorkID, let work = workItems.first(where: { $0.id == id }) {
                WorkDetailView(work: work) {
                    selectedWorkID = nil
                }
            } else {
                EmptyView()
            }
        }
#endif
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("NewWorkRequested"))) { _ in
            isPresentingAddWork = true
        }
    }
}

fileprivate struct MultipleSelectionRow: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .foregroundStyle(.primary)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                }
            }
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }
}
