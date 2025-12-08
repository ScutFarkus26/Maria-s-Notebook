import SwiftUI
import SwiftData

/// Top-level view for managing and browsing students.
/// Shows a filter sidebar and a grid of student cards.
struct StudentsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.calendar) private var calendar
    @Query private var students: [Student]
    @Query private var attendanceRecords: [AttendanceRecord]
    @Query private var studentLessons: [StudentLesson]
    @Query private var lessons: [Lesson]
    
    private let viewModel = StudentsViewModel()

    @AppStorage("StudentsView.sortOrder") private var studentsSortOrderRaw: String = "alphabetical"
    @AppStorage("StudentsView.selectedFilter") private var studentsFilterRaw: String = "all"
    @AppStorage("StudentsView.presentNow.excludedNames") private var presentNowExcludedNamesRaw: String = "danny de berry,lil dan d"

    private var sortOrder: SortOrder {
        switch studentsSortOrderRaw {
        case "manual": return .manual
        case "age": return .age
        case "birthday": return .birthday
        case "lastLesson": return .lastLesson
        default: return .alphabetical
        }
    }

    private var selectedFilter: StudentsFilter {
        switch studentsFilterRaw {
        case "upper": return .upper
        case "lower": return .lower
        case "presentNow": return .presentNow
        case "presentToday": return .presentNow
        default: return .all
        }
    }

    @State private var showingAddStudent = false
    @State private var selectedStudentID: UUID? = nil
    
    @State private var isShowingSaveError: Bool = false
    @State private var saveErrorMessage: String = ""

    private var excludedPresentNowNames: Set<String> {
        let lower = presentNowExcludedNamesRaw.lowercased()
        let parts = lower.split(whereSeparator: { ch in ch == "," || ch == ";" || ch.isNewline })
        let tokens = parts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        return Set(tokens)
    }

    private var excludedPresentNowIDs: Set<UUID> {
        let names = excludedPresentNowNames
        let ids = students.compactMap { s -> UUID? in
            let name = s.fullName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return names.contains(name) ? s.id : nil
        }
        return Set(ids)
    }

    private var presentNowIDs: Set<UUID> {
        let cal = Calendar.current
        let now = Date()
        let today = cal.startOfDay(for: now)
        let todays = attendanceRecords.filter { rec in
            cal.isDate(rec.date, inSameDayAs: today) && (rec.status == .present || rec.status == .tardy)
        }
        var ids = Set(todays.map { $0.studentID })
        ids.subtract(excludedPresentNowIDs)
        return ids
    }
    
    private var presentNowCount: Int { presentNowIDs.count }

    private var daysSinceLastLessonByStudent: [UUID: Int] {
        var result: [UUID: Int] = [:]

        // Build excluded lesson IDs where subject or group is "Parsha" (case-insensitive, trimmed)
        let excludedLessonIDs: Set<UUID> = {
            func norm(_ s: String) -> String { s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            let ids = lessons.filter { l in
                let s = norm(l.subject)
                let g = norm(l.group)
                return s == "parsha" || g == "parsha"
            }.map { $0.id }
            return Set(ids)
        }()

        // Given lessons excluding Parsha
        let given = studentLessons.filter { $0.isGiven && !excludedLessonIDs.contains($0.resolvedLessonID) }

        // Compute most recent date per student
        var lastDateByStudent: [UUID: Date] = [:]
        for sl in given {
            let when = sl.givenAt ?? sl.scheduledFor ?? sl.createdAt
            for sid in sl.resolvedStudentIDs {
                if let existing = lastDateByStudent[sid] {
                    if when > existing { lastDateByStudent[sid] = when }
                } else {
                    lastDateByStudent[sid] = when
                }
            }
        }

        for s in students {
            if let last = lastDateByStudent[s.id] {
                let days = LessonAgeHelper.schoolDaysSinceCreation(createdAt: last, asOf: Date(), using: modelContext, calendar: calendar)
                result[s.id] = days
            } else {
                result[s.id] = -1
            }
        }
        return result
    }

    /// Returns students ordered by the persisted manual order, with any missing/extra appended.
    private func applyManualOrder(to students: [Student]) -> [Student] {
        return students.sorted { (lhs: Student, rhs: Student) -> Bool in
            lhs.manualOrder < rhs.manualOrder
        }
    }

    /// Assigns sequential manualOrder values based on the provided ordered IDs.
    private func assignManualOrder(from orderedIDs: [UUID]) {
        for (idx, id) in orderedIDs.enumerated() {
            if let s = students.first(where: { $0.id == id }) {
                s.manualOrder = idx
            }
        }
    }

    /// If no manual order has been assigned yet, seed it alphabetically.
    private func ensureInitialManualOrderIfNeeded() {
        if viewModel.ensureInitialManualOrderIfNeeded(students) {
            do {
                try modelContext.save()
            } catch {
                saveErrorMessage = error.localizedDescription
                isShowingSaveError = true
            }
        }
    }

    /// Returns the next occurrence of a birthday (month/day) relative to `today`.
    private func nextBirthday(from birthday: Date, relativeTo today: Date = Date()) -> Date {
        let cal = Calendar.current
        let todayStart = cal.startOfDay(for: today)
        let comps = cal.dateComponents([.month, .day], from: birthday)
        guard let month = comps.month, let day = comps.day else { return .distantFuture }

        var year = cal.component(.year, from: todayStart)
        var thisYearComponents = DateComponents(year: year, month: month, day: day)
        var thisYearDate = cal.date(from: thisYearComponents)
        // Handle Feb 29 on non-leap years by using Feb 28
        if thisYearDate == nil && month == 2 && day == 29 {
            thisYearComponents.day = 28
            thisYearDate = cal.date(from: thisYearComponents)
        }
        guard let thisYear = thisYearDate else { return .distantFuture }

        if thisYear >= todayStart {
            return thisYear
        } else {
            year += 1
            var nextComponents = DateComponents(year: year, month: month, day: day)
            var nextDate = cal.date(from: nextComponents)
            if nextDate == nil && month == 2 && day == 29 {
                nextComponents.day = 28
                nextDate = cal.date(from: nextComponents)
            }
            return nextDate ?? thisYear
        }
    }

    /// Students after applying the current filter and sort order.
    private var filteredStudents: [Student] {
        if sortOrder == .lastLesson {
            // Start from filtered base using alphabetical to keep deterministic base ordering
            let base = viewModel.filteredStudents(students: students, filter: selectedFilter, sortOrder: .alphabetical, presentNowIDs: presentNowIDs)
            // Build a map of studentID -> days since last lesson (school days), defaulting to 0 when none
            let daysMap = daysSinceLastLessonByStudent
            return base.sorted { lhs, rhs in
                let l = daysMap[lhs.id] ?? -1
                let r = daysMap[rhs.id] ?? -1

                // No lessons first (we use -1 to indicate none)
                let lNo = l < 0
                let rNo = r < 0
                if lNo != rNo { return lNo && !rNo }

                // Both have or both don't have lessons: sort by days descending
                if l != r { return l > r }

                // Tie-breakers
                let nameOrder = lhs.fullName.localizedCaseInsensitiveCompare(rhs.fullName)
                if nameOrder == .orderedSame { return lhs.manualOrder < rhs.manualOrder }
                return nameOrder == .orderedAscending
            }
        } else {
            return viewModel.filteredStudents(students: students, filter: selectedFilter, sortOrder: sortOrder, presentNowIDs: presentNowIDs)
        }
    }

    /// Available level filters.
    private var levelFilters: [StudentsFilter] {
        [.upper, .lower]
    }

    private func selectedFilterRawAssignment(for filter: StudentsFilter) {
        switch filter {
        case .upper:
            studentsFilterRaw = "upper"
        case .lower:
            studentsFilterRaw = "lower"
        case .presentNow:
            studentsFilterRaw = "presentNow"
        case .all:
            studentsFilterRaw = "all"
        }
    }

    // MARK: - Body

    var body: some View {
        HStack(spacing: 0) {
            sidebar

            Divider()

            content
        }
        .sheet(isPresented: $showingAddStudent) {
            AddStudentView()
        }
        .sheet(isPresented: Binding(get: { selectedStudentID != nil }, set: { if !$0 { selectedStudentID = nil } })) {
            if let id = selectedStudentID, let student = students.first(where: { $0.id == id }) {
                StudentDetailView(student: student) {
                    selectedStudentID = nil
                }
            } else {
                EmptyView()
            }
        }
        .onAppear {
            ensureInitialManualOrderIfNeeded()
        }
        .onChange(of: students.map { $0.id }) { _, _ in
            // Seed initial order alphabetically if everything is zero
            ensureInitialManualOrderIfNeeded()

            // Ensure manualOrder values remain unique; assign new students to the end
            if viewModel.repairManualOrderUniquenessIfNeeded(students) {
                do {
                    try modelContext.save()
                } catch {
                    saveErrorMessage = error.localizedDescription
                    isShowingSaveError = true
                }
            }
        }
        .alert("Save Failed", isPresented: $isShowingSaveError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(saveErrorMessage)
        }
    }

    // MARK: - Subviews

    /// Left-hand filter sidebar (All / levels).
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Sort Order")
                .font(.system(size: AppTheme.FontSize.caption, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)

            SidebarFilterButton(
                icon: "textformat.abc",
                title: "A–Z",
                color: .accentColor,
                isSelected: sortOrder == .alphabetical
            ) {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85, blendDuration: 0.1)) {
                    studentsSortOrderRaw = "alphabetical"
                }
            }

            SidebarFilterButton(
                icon: "calendar",
                title: "Age",
                color: .accentColor,
                isSelected: sortOrder == .age
            ) {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85, blendDuration: 0.1)) {
                    studentsSortOrderRaw = "age"
                }
            }

            SidebarFilterButton(
                icon: "gift",
                title: "Birthday",
                color: .accentColor,
                isSelected: sortOrder == .birthday
            ) {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85, blendDuration: 0.1)) {
                    studentsSortOrderRaw = "birthday"
                }
            }
            
            SidebarFilterButton(
                icon: "clock.badge.exclamationmark",
                title: "Last Lesson",
                color: .accentColor,
                isSelected: sortOrder == .lastLesson
            ) {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85, blendDuration: 0.1)) {
                    studentsSortOrderRaw = "lastLesson"
                }
            }

            SidebarFilterButton(
                icon: "arrow.up.arrow.down",
                title: "Manual",
                color: .accentColor,
                isSelected: sortOrder == .manual
            ) {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85, blendDuration: 0.1)) {
                    studentsSortOrderRaw = "manual"
                }
            }
            .padding(.bottom, 8)

            Text("Filters")
                .font(.system(size: AppTheme.FontSize.caption, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)

            // All filter
            SidebarFilterButton(
                icon: "person.3.fill",
                title: "All",
                color: .accentColor,
                isSelected: selectedFilter == .all
            ) {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85, blendDuration: 0.1)) {
                    studentsFilterRaw = "all"
                }
            }

            SidebarFilterButton(
                icon: "checkmark.circle.fill",
                title: "Present Now",
                color: .green,
                isSelected: selectedFilter == .presentNow,
                trailingBadgeText: presentNowCount > 0 ? "\(presentNowCount)" : nil,
                trailingBadgeColor: .green
            ) {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85, blendDuration: 0.1)) {
                    studentsFilterRaw = "presentNow"
                }
            }

            // Individual level filters (Upper, Lower, etc.) based on actual data
            ForEach(levelFilters, id: \.self) { filter in
                SidebarFilterButton(
                    icon: "circle.fill",
                    title: filter.title,
                    color: filter.color,
                    isSelected: selectedFilter == filter
                ) {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85, blendDuration: 0.1)) {
                        selectedFilterRawAssignment(for: filter)
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 16)
        .padding(.leading, 16)
        .frame(width: 180, alignment: .topLeading)
        .background(Color.gray.opacity(0.08))
    }

    /// Main grid of student cards.
    private var content: some View {
        Group {
            if filteredStudents.isEmpty {
                VStack(spacing: 8) {
                    Text("No students yet")
                        .font(.system(size: AppTheme.FontSize.titleMedium, weight: .semibold, design: .rounded))
                    Text("Click the plus button to add your first student.")
                        .font(.system(size: AppTheme.FontSize.body, weight: .regular, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                StudentsCardsGridView(
                    students: filteredStudents,
                    isBirthdayMode: sortOrder == .birthday,
                    isAgeMode: sortOrder == .age,
                    isLastLessonMode: sortOrder == .lastLesson,
                    lastLessonDays: daysSinceLastLessonByStudent,
                    isManualMode: sortOrder == .manual,
                    onTapStudent: { selectedStudentID = $0.id },
                    onReorder: { movingStudent, fromIndex, toIndex, subset in
                        // Reuse existing merge logic from StudentsViewModel
                        let newAllIDs = viewModel.mergeReorderedSubsetIntoAll(
                            movingID: movingStudent.id,
                            from: fromIndex,
                            to: toIndex,
                            current: subset,
                            allStudents: students
                        )
                        assignManualOrder(from: newAllIDs)
                        do {
                            try modelContext.save()
                        } catch {
                            saveErrorMessage = error.localizedDescription
                            isShowingSaveError = true
                        }
                    }
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clear)
        .overlay(alignment: .topTrailing) {
            Button {
                showingAddStudent = true
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

