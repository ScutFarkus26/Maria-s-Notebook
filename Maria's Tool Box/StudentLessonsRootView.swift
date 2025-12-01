import SwiftUI
import SwiftData

private enum StudentLessonsSort: String {
    case presentThenGiven = "Default"
    case dateCreated = "Date Created"
    case dateGiven = "Date Given"
}

private enum CompletionFilter: String {
    case all = "All"
    case completed = "Completed"
    case notCompleted = "Not Completed"
}

struct StudentLessonsRootView: View {
    @Query private var studentLessons: [StudentLesson]
    @Query private var lessons: [Lesson]
    @Query private var students: [Student]

    @State private var selectedLessonID: UUID? = nil
    @State private var quickActionsLessonID: UUID? = nil

    @SceneStorage("StudentLessons.filter") private var studentLessonsFilterRaw: String = "all"
    @SceneStorage("StudentLessons.sort") private var studentLessonsSortRaw: String = "default"
    @SceneStorage("StudentLessons.subject") private var studentLessonsSubjectRaw: String = ""

    private var filter: CompletionFilter {
        switch studentLessonsFilterRaw {
        case "completed": return .completed
        case "notCompleted": return .notCompleted
        default: return .all
        }
    }

    private var sort: StudentLessonsSort {
        switch studentLessonsSortRaw {
        case "dateCreated": return .dateCreated
        case "dateGiven": return .dateGiven
        default: return .presentThenGiven
        }
    }

    private var selectedSubject: String? {
        studentLessonsSubjectRaw.isEmpty ? nil : studentLessonsSubjectRaw
    }

    private let lessonsVM = LessonsViewModel()

    private var subjects: [String] {
        lessonsVM.subjects(from: lessons)
    }

    private var lessonMap: [UUID: Lesson] {
        Dictionary(uniqueKeysWithValues: lessons.map { ($0.id, $0) })
    }

    private func applySubjectFilter(_ base: [StudentLesson]) -> [StudentLesson] {
        if let subject = selectedSubject {
            return base.filter { sl in
                if let l = lessonMap[sl.lessonID] {
                    return l.subject.caseInsensitiveCompare(subject) == .orderedSame
                }
                return false
            }
        }
        return base
    }

    private var defaultUpcoming: [StudentLesson] {
        var base = studentLessons.filter { $0.givenAt == nil }
        base = applySubjectFilter(base)
        return base.sorted { lhs, rhs in
            switch (lhs.scheduledFor, rhs.scheduledFor) {
            case let (l?, r?):
                return l < r
            case (nil, nil):
                return lhs.createdAt < rhs.createdAt
            case (nil, _?):
                return false
            case (_?, nil):
                return true
            }
        }
    }

    private var defaultGiven: [StudentLesson] {
        var base = studentLessons.filter { $0.givenAt != nil }
        base = applySubjectFilter(base)
        return base.sorted { lhs, rhs in
            let l = lhs.givenAt ?? .distantPast
            let r = rhs.givenAt ?? .distantPast
            return l > r
        }
    }

    private var filteredAndSorted: [StudentLesson] {
        // Apply completion filter first
        var base: [StudentLesson]
        switch filter {
        case .all:
            base = studentLessons
        case .completed:
            base = studentLessons.filter { $0.givenAt != nil }
        case .notCompleted:
            base = studentLessons.filter { $0.givenAt == nil }
        }

        // Subject filter (using referenced Lesson)
        if let subject = selectedSubject {
            base = base.filter { sl in
                if let l = lessonMap[sl.lessonID] {
                    return l.subject.caseInsensitiveCompare(subject) == .orderedSame
                }
                return false
            }
        }

        // Sorting
        switch sort {
        case .presentThenGiven:
            let upcoming: [StudentLesson] = base.filter { $0.givenAt == nil }.sorted { lhs, rhs in
                switch (lhs.scheduledFor, rhs.scheduledFor) {
                case let (l?, r?):
                    return l < r
                case (nil, nil):
                    return lhs.createdAt < rhs.createdAt
                case (nil, _?):
                    return false
                case (_?, nil):
                    return true
                }
            }
            let given: [StudentLesson] = base.filter { $0.givenAt != nil }.sorted { lhs, rhs in
                let l = lhs.givenAt ?? .distantPast
                let r = rhs.givenAt ?? .distantPast
                return l > r
            }
            return upcoming + given
        case .dateCreated:
            return base.sorted { lhs, rhs in lhs.createdAt > rhs.createdAt }
        case .dateGiven:
            return base.sorted { lhs, rhs in
                switch (lhs.givenAt, rhs.givenAt) {
                case let (l?, r?):
                    return l > r
                case (nil, nil):
                    // If neither has a givenAt, fall back to createdAt
                    return lhs.createdAt > rhs.createdAt
                case (nil, _?):
                    // Place undated (not yet given) after those with dates
                    return false
                case (_?, nil):
                    return true
                }
            }
        }
    }

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: 260, maximum: 320), spacing: 24)]
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            content
        }
        .sheet(isPresented: Binding(get: { selectedLessonID != nil }, set: { if !$0 { selectedLessonID = nil } })) {
            if let id = selectedLessonID, let sl = studentLessons.first(where: { $0.id == id }) {
                StudentLessonDetailView(studentLesson: sl) {
                    selectedLessonID = nil
                }
            } else {
                EmptyView()
            }
        }
        .sheet(isPresented: Binding(get: { quickActionsLessonID != nil }, set: { if !$0 { quickActionsLessonID = nil } })) {
            if let id = quickActionsLessonID, let sl = studentLessons.first(where: { $0.id == id }) {
                StudentLessonQuickActionsView(studentLesson: sl) {
                    quickActionsLessonID = nil
                }
            } else {
                EmptyView()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("QuickActionsRequested"))) { _ in
            // If there is at least one student lesson, open quick actions for the first upcoming
            if let first = studentLessons.first { quickActionsLessonID = first.id }
        }
    }

    // MARK: - Sidebar
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Filters")
                .font(.system(size: AppTheme.FontSize.caption, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.top, 8)

            SidebarFilterButton(
                icon: "line.3.horizontal.decrease.circle",
                title: CompletionFilter.all.rawValue,
                color: .accentColor,
                isSelected: filter == .all
            ) {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85, blendDuration: 0.1)) {
                    studentLessonsFilterRaw = "all"
                }
            }

            SidebarFilterButton(
                icon: "checkmark.circle.fill",
                title: CompletionFilter.completed.rawValue,
                color: .green,
                isSelected: filter == .completed
            ) {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85, blendDuration: 0.1)) {
                    studentLessonsFilterRaw = "completed"
                }
            }

            SidebarFilterButton(
                icon: "circle.dashed",
                title: CompletionFilter.notCompleted.rawValue,
                color: .orange,
                isSelected: filter == .notCompleted
            ) {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85, blendDuration: 0.1)) {
                    studentLessonsFilterRaw = "notCompleted"
                }
            }

            Text("Subject")
                .font(.system(size: AppTheme.FontSize.caption, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.top, 8)

            // Clear subject filter
            SidebarFilterButton(
                icon: "rectangle.3.group",
                title: "All Subjects",
                color: .accentColor,
                isSelected: selectedSubject == nil
            ) {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85, blendDuration: 0.1)) {
                    studentLessonsSubjectRaw = ""
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
                        studentLessonsSubjectRaw = subject
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

    // MARK: - Content
    private var content: some View {
        Group {
            if sort == .presentThenGiven {
                let showUpcoming = filter != .completed
                let showGiven = filter != .notCompleted
                let up = defaultUpcoming
                let gv = defaultGiven

                if (!showUpcoming || up.isEmpty) && (!showGiven || gv.isEmpty) {
                    VStack(spacing: 8) {
                        Text("No student lessons")
                            .font(.system(size: AppTheme.FontSize.titleMedium, weight: .semibold, design: .rounded))
                        Text("Try adjusting your filters or add lessons from the Lessons library.")
                            .font(.system(size: AppTheme.FontSize.body, weight: .regular, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 24) {
                            if showUpcoming && !up.isEmpty {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack(spacing: 10) {
                                        Image(systemName: "clock")
                                            .foregroundStyle(.secondary)
                                        Text("To Present")
                                            .font(.system(size: AppTheme.FontSize.caption, weight: .semibold, design: .rounded))
                                            .foregroundStyle(.secondary)
                                    }
                                    LazyVGrid(columns: columns, alignment: .leading, spacing: 24) {
                                        ForEach(up, id: \.id) { sl in
                                            StudentLessonCard(snapshot: sl.snapshot(), lesson: lessonMap[sl.lessonID], students: students)
                                                .onTapGesture { selectedLessonID = sl.id }
                                                .contextMenu {
                                                    Button {
                                                        quickActionsLessonID = sl.id
                                                    } label: {
                                                        Label("Quick Actions…", systemImage: "bolt")
                                                    }
                                                }
                                        }
                                    }
                                }
                            }
                            if showGiven && !gv.isEmpty {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack(spacing: 10) {
                                        Image(systemName: "checkmark.circle")
                                            .foregroundStyle(.secondary)
                                        Text("Given")
                                            .font(.system(size: AppTheme.FontSize.caption, weight: .semibold, design: .rounded))
                                            .foregroundStyle(.secondary)
                                    }
                                    LazyVGrid(columns: columns, alignment: .leading, spacing: 24) {
                                        ForEach(gv, id: \.id) { sl in
                                            StudentLessonCard(snapshot: sl.snapshot(), lesson: lessonMap[sl.lessonID], students: students)
                                                .onTapGesture { selectedLessonID = sl.id }
                                                .contextMenu {
                                                    Button {
                                                        quickActionsLessonID = sl.id
                                                    } label: {
                                                        Label("Quick Actions…", systemImage: "bolt")
                                                    }
                                                }
                                        }
                                    }
                                }
                            }
                        }
                        .padding(24)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                if filteredAndSorted.isEmpty {
                    VStack(spacing: 8) {
                        Text("No student lessons")
                            .font(.system(size: AppTheme.FontSize.titleMedium, weight: .semibold, design: .rounded))
                        Text("Try adjusting your filters or add lessons from the Lessons library.")
                            .font(.system(size: AppTheme.FontSize.body, weight: .regular, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, alignment: .leading, spacing: 24) {
                            ForEach(filteredAndSorted, id: \.id) { sl in
                                StudentLessonCard(snapshot: sl.snapshot(), lesson: lessonMap[sl.lessonID], students: students)
                                    .onTapGesture { selectedLessonID = sl.id }
                                    .contextMenu {
                                        Button {
                                            quickActionsLessonID = sl.id
                                        } label: {
                                            Label("Quick Actions…", systemImage: "bolt")
                                        }
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
}

// MARK: - Card View (matches Albums/Students style)
private struct StudentLessonCard: View {
    let snapshot: StudentLessonSnapshot
    let lesson: Lesson?
    let students: [Student]

    private var lessonName: String {
        (lesson?.name.isEmpty == false ? lesson?.name : nil) ?? "Lesson"
    }

    private var subject: String {
        lesson?.subject ?? ""
    }

    private var subjectColor: Color {
        AppColors.color(forSubject: subject)
    }

    private var subjectBadge: some View {
        HStack(spacing: 6) {
            Circle().fill(subjectColor).frame(width: 6, height: 6)
            Text(subject.isEmpty ? "Subject" : subject)
                .font(.system(size: AppTheme.FontSize.captionSmall, weight: .semibold, design: .rounded))
                .foregroundStyle(subjectColor)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(subjectColor.opacity(0.12)))
        .accessibilityLabel("Subject: \(subject.isEmpty ? "Unknown" : subject)")
    }

    private struct StudentChip: Identifiable { let id: UUID; let label: String; let isMissing: Bool }
    private var studentChips: [StudentChip] {
        var chips: [StudentChip] = []
        for id in snapshot.studentIDs {
            if let s = students.first(where: { $0.id == id }) {
                chips.append(StudentChip(id: id, label: displayName(for: s), isMissing: false))
            } else {
                chips.append(StudentChip(id: id, label: "(Removed)", isMissing: true))
            }
        }
        return chips
    }

    private func displayName(for student: Student) -> String {
        let parts = student.fullName.split(separator: " ")
        guard let first = parts.first else { return student.fullName }
        let lastInitial = parts.dropFirst().first?.first.map { String($0) } ?? ""
        return lastInitial.isEmpty ? String(first) : "\(first) \(lastInitial)."
    }

    private var statusText: String {
        if let given = snapshot.givenAt {
            let fmt = DateFormatter()
            fmt.setLocalizedDateFormatFromTemplate("EEEE, MMM d")
            return "Presented on " + fmt.string(from: given)
        } else if let scheduled = snapshot.scheduledFor {
            let fmt = DateFormatter()
            fmt.setLocalizedDateFormatFromTemplate("EEEE, MMM d")
            return "Scheduled for " + fmt.string(from: scheduled)
        } else {
            return "Not Scheduled"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(lessonName)
                    .font(.system(size: AppTheme.FontSize.titleSmall, weight: .semibold, design: .rounded))
                Spacer(minLength: 0)
                subjectBadge
            }

            if !studentChips.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(studentChips, id: \.id) { chip in
                            HStack(spacing: 6) {
                                Text(chip.label)
                                    .font(.system(size: AppTheme.FontSize.caption, weight: .semibold, design: .rounded))
                                    .foregroundStyle(chip.isMissing ? .secondary : .primary)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(chip.isMissing ? Color.primary.opacity(0.08) : subjectColor.opacity(0.15))
                            )
                        }
                    }
                }
            }

            Text(statusText)
                .font(.system(size: AppTheme.FontSize.caption, weight: .regular, design: .rounded))
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(minHeight: 100)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(cardBackgroundColor)
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.primary.opacity(0.06), lineWidth: 1))
                .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 2)
        )
        .accessibilityElement(children: .combine)
    }

    private var cardBackgroundColor: Color {
        #if os(macOS)
        return Color(NSColor.windowBackgroundColor)
        #else
        return Color(uiColor: .secondarySystemBackground)
        #endif
    }
}

#Preview {
    StudentLessonsRootView()
}
