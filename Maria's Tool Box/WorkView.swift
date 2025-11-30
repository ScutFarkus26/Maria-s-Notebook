import SwiftUI
import SwiftData

struct WorkView: View {
    @Environment(\.modelContext) private var modelContext

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

    @AppStorage("WorkView.selectedWorkType") private var workSelectedTypeRaw: String = ""
    @AppStorage("WorkView.selectedSubject") private var workSelectedSubjectRaw: String = ""
    @AppStorage("WorkView.selectedStudentIDs") private var workSelectedStudentIDsRaw: String = ""
    @AppStorage("WorkView.dateFilter") private var workDateFilterRaw: String = "thisWeek"
    @AppStorage("WorkView.searchText") private var workSearchTextRaw: String = ""

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

    private var filteredWorks: [WorkModel] {
        var base = workItems

        // Work type filter
        if let type = selectedWorkType {
            base = base.filter { $0.workType == type }
        }

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

        // Date filter using linked lesson date when available (givenAt > scheduledFor), otherwise fall back to work.createdAt
        let cal = Calendar.current
        let now = Date()
        let startOfToday = cal.startOfDay(for: now)
        let twoWeeksAgo = cal.date(byAdding: .day, value: -14, to: startOfToday) ?? now

        func linkedDate(for work: WorkModel) -> Date {
            if let slID = work.studentLessonID, let sl = studentLessonsByID[slID] {
                if let given = sl.givenAt { return given }
                if let sched = sl.scheduledFor { return sched }
            }
            return work.createdAt
        }

        if dateFilter != .all {
            base = base.filter { work in
                let d = linkedDate(for: work)
                switch dateFilter {
                case .today:
                    return cal.isDateInToday(d)
                case .thisWeek:
                    if let interval = cal.dateInterval(of: .weekOfYear, for: now) {
                        return interval.contains(d)
                    }
                    return false
                case .lastTwoWeeks:
                    return d >= twoWeeksAgo
                case .overTwoWeeks:
                    return d < twoWeeksAgo
                case .all:
                    return true
                }
            }
        }

        // Text search on notes and linked lesson name
        let query = workSearchTextRaw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !query.isEmpty {
            base = base.filter { work in
                let notesMatch = work.notes.lowercased().contains(query)
                var lessonMatch = false
                if let slID = work.studentLessonID, let sl = studentLessonsByID[slID], let lesson = lessonsByID[sl.lessonID] {
                    lessonMatch = lesson.name.lowercased().contains(query)
                }
                return notesMatch || lessonMatch
            }
        }

        return base
    }

    // Helper maps for quick lookup
    private var studentsByID: [UUID: Student] { Dictionary(uniqueKeysWithValues: students.map { ($0.id, $0) }) }
    private var lessonsByID: [UUID: Lesson] { Dictionary(uniqueKeysWithValues: lessons.map { ($0.id, $0) }) }
    private var studentLessonsByID: [UUID: StudentLesson] { Dictionary(uniqueKeysWithValues: studentLessons.map { ($0.id, $0) }) }

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

            Text("Work Type")
                .font(.system(size: AppTheme.FontSize.caption, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)

            SidebarFilterButton(
                icon: "square.grid.2x2",
                title: "All Types",
                color: .accentColor,
                isSelected: selectedWorkType == nil
            ) {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85, blendDuration: 0.1)) {
                    workSelectedTypeRaw = ""
                }
            }

            SidebarFilterButton(
                icon: "magnifyingglass.circle.fill",
                title: WorkModel.WorkType.research.rawValue,
                color: .teal,
                isSelected: selectedWorkType == .research
            ) {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85, blendDuration: 0.1)) {
                    workSelectedTypeRaw = WorkModel.WorkType.research.rawValue
                }
            }

            SidebarFilterButton(
                icon: "arrow.triangle.2.circlepath.circle.fill",
                title: WorkModel.WorkType.followUp.rawValue,
                color: .orange,
                isSelected: selectedWorkType == .followUp
            ) {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85, blendDuration: 0.1)) {
                    workSelectedTypeRaw = WorkModel.WorkType.followUp.rawValue
                }
            }

            SidebarFilterButton(
                icon: "hammer.fill",
                title: WorkModel.WorkType.practice.rawValue,
                color: .purple,
                isSelected: selectedWorkType == .practice
            ) {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85, blendDuration: 0.1)) {
                    workSelectedTypeRaw = WorkModel.WorkType.practice.rawValue
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

            Text("Date")
                .font(.system(size: AppTheme.FontSize.caption, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.top, 8)

            SidebarFilterButton(
                icon: "calendar.badge.clock",
                title: "All Dates",
                color: .accentColor,
                isSelected: dateFilter == .all
            ) {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85, blendDuration: 0.1)) {
                    workDateFilterRaw = DateFilter.all.storageKey
                }
            }

            SidebarFilterButton(
                icon: "sun.max.fill",
                title: DateFilter.today.rawValue,
                color: .yellow,
                isSelected: dateFilter == .today
            ) {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85, blendDuration: 0.1)) {
                    workDateFilterRaw = DateFilter.today.storageKey
                }
            }

            SidebarFilterButton(
                icon: "calendar",
                title: DateFilter.thisWeek.rawValue,
                color: .blue,
                isSelected: dateFilter == .thisWeek
            ) {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85, blendDuration: 0.1)) {
                    workDateFilterRaw = DateFilter.thisWeek.storageKey
                }
            }

            SidebarFilterButton(
                icon: "arrow.counterclockwise.circle.fill",
                title: DateFilter.lastTwoWeeks.rawValue,
                color: .orange,
                isSelected: dateFilter == .lastTwoWeeks
            ) {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85, blendDuration: 0.1)) {
                    workDateFilterRaw = DateFilter.lastTwoWeeks.storageKey
                }
            }

            SidebarFilterButton(
                icon: "hourglass",
                title: DateFilter.overTwoWeeks.rawValue,
                color: .red,
                isSelected: dateFilter == .overTwoWeeks
            ) {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85, blendDuration: 0.1)) {
                    workDateFilterRaw = DateFilter.overTwoWeeks.storageKey
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 16)
        .padding(.leading, 16)
        .frame(width: 200, alignment: .topLeading)
        .background(Color.gray.opacity(0.08))
    }

    var body: some View {
        NavigationStack {
            HStack(spacing: 0) {
                sidebar

                Divider()

                VStack(spacing: 0) {
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
                            WorkCardsGridView(
                                works: filteredWorks,
                                studentsByID: studentsByID,
                                lessonsByID: lessonsByID,
                                studentLessonsByID: studentLessonsByID,
                                onTapWork: { work in
                                    openWindow(id: "WorkDetailWindow", value: work.id)
                                }
                            )
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
    #else
                            WorkCardsGridView(
                                works: filteredWorks,
                                studentsByID: studentsByID,
                                lessonsByID: lessonsByID,
                                studentLessonsByID: studentLessonsByID,
                                onTapWork: { work in
                                    selectedWorkID = work.id
                                }
                            )
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            .navigationTitle("Work")
        }
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

