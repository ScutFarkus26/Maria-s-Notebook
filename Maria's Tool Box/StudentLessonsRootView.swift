import SwiftUI
import SwiftData

private enum StudentLessonsSort: String {
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

    @State private var selectedLesson: StudentLesson? = nil
    @State private var sort: StudentLessonsSort = .dateCreated
    @State private var filter: CompletionFilter = .all
    @State private var selectedSubject: String? = nil

    private let lessonsVM = LessonsViewModel()

    private var subjects: [String] {
        lessonsVM.subjects(from: lessons)
    }

    private var lessonMap: [UUID: Lesson] {
        Dictionary(uniqueKeysWithValues: lessons.map { ($0.id, $0) })
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
        .sheet(item: $selectedLesson) { sl in
            StudentLessonDetailView(studentLesson: sl) {
                selectedLesson = nil
            }
        }
    }

    // MARK: - Sidebar
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Sort")
                .font(.system(size: AppTheme.FontSize.caption, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)

            SidebarFilterButton(
                icon: "clock.badge.plus",
                title: StudentLessonsSort.dateCreated.rawValue,
                color: .accentColor,
                isSelected: sort == .dateCreated
            ) {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85, blendDuration: 0.1)) {
                    sort = .dateCreated
                }
            }

            SidebarFilterButton(
                icon: "calendar.badge.checkmark",
                title: StudentLessonsSort.dateGiven.rawValue,
                color: .accentColor,
                isSelected: sort == .dateGiven
            ) {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85, blendDuration: 0.1)) {
                    sort = .dateGiven
                }
            }

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
                    filter = .all
                }
            }

            SidebarFilterButton(
                icon: "checkmark.circle.fill",
                title: CompletionFilter.completed.rawValue,
                color: .green,
                isSelected: filter == .completed
            ) {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85, blendDuration: 0.1)) {
                    filter = .completed
                }
            }

            SidebarFilterButton(
                icon: "circle.dashed",
                title: CompletionFilter.notCompleted.rawValue,
                color: .orange,
                isSelected: filter == .notCompleted
            ) {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85, blendDuration: 0.1)) {
                    filter = .notCompleted
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
                    selectedSubject = nil
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
                        selectedSubject = subject
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
                            StudentLessonCard(studentLesson: sl, lesson: lessonMap[sl.lessonID], students: students)
                                .onTapGesture { selectedLesson = sl }
                        }
                    }
                    .padding(24)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

// MARK: - Card View (matches Albums/Students style)
private struct StudentLessonCard: View {
    let studentLesson: StudentLesson
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

    private var studentLine: String {
        let names: [String] = studentLesson.studentIDs.compactMap { id -> String? in
            guard let s = students.first(where: { $0.id == id }) else { return nil }
            return displayName(for: s)
        }
        if !names.isEmpty {
            return names.joined(separator: ", ")
        }
        let count = studentLesson.studentIDs.count
        return count > 0 ? "\(count) student\(count == 1 ? "" : "s")" : ""
    }

    private func displayName(for student: Student) -> String {
        let parts = student.fullName.split(separator: " ")
        guard let first = parts.first else { return student.fullName }
        let lastInitial = parts.dropFirst().first?.first.map { String($0) } ?? ""
        return lastInitial.isEmpty ? String(first) : "\(first) \(lastInitial)."
    }

    private var statusText: String {
        if let given = studentLesson.givenAt {
            let fmt = DateFormatter()
            fmt.setLocalizedDateFormatFromTemplate("EEEE, MMM d")
            return "Presented on " + fmt.string(from: given)
        } else if let scheduled = studentLesson.scheduledFor {
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

            if !studentLine.isEmpty {
                Text(studentLine)
                    .font(.system(size: AppTheme.FontSize.body, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
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

