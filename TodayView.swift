import SwiftUI
import SwiftData

struct TodayView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.calendar) private var calendar

    @StateObject private var viewModel: TodayViewModel

    // Navigation state for details
    @State private var selectedWorkID: UUID? = nil
    @State private var selectedStudentLesson: StudentLesson? = nil

    @Query private var studentLessonsAll: [StudentLesson]

    // Lookup helpers from VM caches to avoid per-row fetches
    private var nameForLesson: (UUID) -> String { { id in viewModel.lessonsByID[id]?.name ?? "Lesson" } }
    
    // Compute first names that appear more than once (case-insensitive, trimmed)
    private var duplicateFirstNames: Set<String> {
        let firsts = viewModel.studentsByID.values.map { $0.firstName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        var counts: [String: Int] = [:]
        for f in firsts { counts[f, default: 0] += 1 }
        return Set(counts.filter { $0.value > 1 }.map { $0.key })
    }

    // Display name rule: First name; append last initial when the first name is not unique
    private var displayNameForID: (UUID) -> String { { id in
        guard let s = viewModel.studentsByID[id] else { return "Student" }
        let first = s.firstName
        let key = first.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if duplicateFirstNames.contains(key) {
            if let initialChar = s.lastName.trimmingCharacters(in: .whitespacesAndNewlines).first {
                return "\(first) \(String(initialChar).uppercased())."
            }
        }
        return first
    } }

    private var studentNamesForIDs: ([UUID]) -> String { { ids in
        let names = ids.map { displayNameForID($0) }
        return names.joined(separator: ", ")
    } }
    private var workTitleForID: (UUID) -> String { { id in
        guard let w = viewModel.worksByID[id] else { return "Work" }
        let t = w.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty { return t }
        if let slID = w.studentLessonID, let sl = viewModel.studentLessonsByID[slID] {
            if let l = viewModel.lessonsByID[sl.lessonID] { return l.name }
        }
        return w.workType.rawValue
    } }
    private var studentNameForID: (UUID) -> String { { id in displayNameForID(id) } }
    private var studentNamesForWorkID: (UUID) -> String { { id in
        guard let w = viewModel.worksByID[id] else { return "" }
        let names = w.participants.map { p in displayNameForID(p.studentID) }
        return names.joined(separator: ", ")
    } }

    init(context: ModelContext) {
        _viewModel = StateObject(wrappedValue: TodayViewModel(context: context, calendar: AppCalendar.shared))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        attendanceStrip
                        lessonsSection
                        checkInsSection
                        inProgressSection
                        completedSection
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
            }
        }
        .onAppear {
            viewModel.setCalendar(calendar)
        }
        .onChange(of: calendar) { _, newCal in
            viewModel.setCalendar(newCal)
        }
        .onChange(of: studentLessonsAll.map { $0.id }) { _, _ in
            viewModel.reload()
        }
        .onReceive(NotificationCenter.default.publisher(for: .PlanningInboxNeedsRefresh)) { _ in
            viewModel.reload()
        }
        .onChange(of: studentLessonsAll.map { $0.scheduledForDay.timeIntervalSinceReferenceDate }) { _, _ in
            viewModel.reload()
        }
        .onChange(of: studentLessonsAll.map { $0.scheduledFor?.timeIntervalSinceReferenceDate ?? -1 }) { _, _ in
            viewModel.reload()
        }
        .onChange(of: studentLessonsAll.map { $0.isPresented }) { _, _ in
            viewModel.reload()
        }
        .sheet(isPresented: Binding(get: { selectedWorkID != nil }, set: { if !$0 { selectedWorkID = nil } })) {
            if let id = selectedWorkID {
                WorkDetailContainerView(workID: id) {
                    selectedWorkID = nil
                }
            }
        }
        .sheet(isPresented: Binding(get: { selectedStudentLesson != nil }, set: { if !$0 { selectedStudentLesson = nil } })) {
            if let sl = selectedStudentLesson {
                StudentLessonDetailView(studentLesson: sl) {
                    selectedStudentLesson = nil
                }
#if os(macOS)
                .frame(minWidth: 720, minHeight: 640)
                .presentationSizing(.fitted)
#else
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
#endif
            } else {
                EmptyView()
            }
        }
    }

    // MARK: - Header
    private var header: some View {
        let cal = calendar
        return VStack(spacing: 8) {
            HStack(spacing: 12) {
                Text("Today")
                    .font(.system(size: AppTheme.FontSize.titleMedium, weight: .bold, design: .rounded))
                Spacer()
                Picker("Level", selection: $viewModel.levelFilter) {
                    ForEach(TodayViewModel.LevelFilter.allCases) { f in
                        Text(f.rawValue).tag(f)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 240)
            }
            HStack(spacing: 12) {
                Button {
                    if let prev = cal.date(byAdding: .day, value: -1, to: viewModel.date) {
                        viewModel.date = cal.startOfDay(for: prev)
                    }
                } label: { Image(systemName: "chevron.left") }
                .buttonStyle(.plain)

                DatePicker("Date", selection: Binding(get: { viewModel.date }, set: { newValue in
                    viewModel.date = cal.startOfDay(for: newValue)
                }), displayedComponents: .date)
#if os(macOS)
                .datePickerStyle(.field)
#else
                .datePickerStyle(.compact)
#endif

                Button {
                    if let next = cal.date(byAdding: .day, value: 1, to: viewModel.date) {
                        viewModel.date = cal.startOfDay(for: next)
                    }
                } label: { Image(systemName: "chevron.right") }
                .buttonStyle(.plain)

                Button("Today") {
                    viewModel.date = cal.startOfDay(for: Date())
                }
                .buttonStyle(.plain)
            }
            HStack(spacing: 8) {
                Text(viewModel.date, format: Date.FormatStyle().weekday(.abbreviated).month(.abbreviated).day())
                    .font(.system(size: AppTheme.FontSize.caption, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                Text("Lessons: \(viewModel.todaysLessons.count)")
                    .font(.system(size: AppTheme.FontSize.captionSmall, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Attendance Strip
    private var attendanceStrip: some View {
        HStack(spacing: 12) {
            statChip(title: "Present", count: viewModel.attendanceSummary.presentCount, color: .green)
            statChip(title: "Absent", count: viewModel.attendanceSummary.absentCount, color: .red)
            statChip(title: "Left Early", count: viewModel.attendanceSummary.leftEarlyCount, color: .purple)
            Spacer()
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.05)))
    }

    private func statChip(title: String, count: Int, color: Color) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text("\(title) \(count)")
                .font(.system(size: AppTheme.FontSize.captionSmall, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Capsule().strokeBorder(color.opacity(0.20), lineWidth: 1))
    }

    // MARK: - Lessons
    private var lessonsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Lessons for Today", systemImage: "text.book.closed")
            if viewModel.todaysLessons.isEmpty {
                ContentUnavailableView("No lessons scheduled today", systemImage: "calendar")
            } else {
                VStack(spacing: 8) {
                    ForEach(viewModel.todaysLessons, id: \.id) { sl in
                        Button {
                            selectedStudentLesson = sl
                        } label: {
                            LessonRow(
                                lessonName: nameForLesson(sl.resolvedLessonID),
                                studentNames: studentNamesForIDs(sl.resolvedStudentIDs),
                                isPresented: sl.isGiven
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - Check-Ins
    private var checkInsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Follow-Ups & Check-Ins", systemImage: "bell")
            if viewModel.overdueCheckIns.isEmpty && viewModel.todaysCheckIns.isEmpty {
                ContentUnavailableView("No check-ins due", systemImage: "checkmark.circle")
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    if !viewModel.overdueCheckIns.isEmpty {
                        Text("Overdue")
                            .font(.system(size: AppTheme.FontSize.caption, weight: .semibold, design: .rounded))
                            .foregroundStyle(.red)
                        ForEach(viewModel.overdueCheckIns, id: \.id) { ci in
                            CheckInRow(ci: ci, workTitle: workTitleForID(ci.workID), studentNames: studentNamesForWorkID(ci.workID)) { selectedWorkID = ci.workID }
                        }
                    }
                    if !viewModel.todaysCheckIns.isEmpty {
                        Text("Due Today")
                            .font(.system(size: AppTheme.FontSize.caption, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                        ForEach(viewModel.todaysCheckIns, id: \.id) { ci in
                            CheckInRow(ci: ci, workTitle: workTitleForID(ci.workID), studentNames: studentNamesForWorkID(ci.workID)) { selectedWorkID = ci.workID }
                        }
                    }
                }
            }
        }
    }

    // MARK: - In Progress
    private var inProgressSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Follow-Ups Due", systemImage: "bolt")
            if viewModel.inProgressWork.isEmpty {
                ContentUnavailableView("No follow-ups due", systemImage: "checkmark.circle")
            } else {
                VStack(spacing: 8) {
                    ForEach(viewModel.inProgressWork, id: \.id) { work in
                        WorkRow(work: work, studentNames: studentNamesForWorkID(work.id)) { selectedWorkID = work.id }
                    }
                }
            }
        }
    }

    // MARK: - Completed
    private var completedSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Completed Today", systemImage: "checkmark.circle")
            if viewModel.completedToday.isEmpty {
                ContentUnavailableView("No completions yet", systemImage: "clock")
            } else {
                VStack(spacing: 8) {
                    ForEach(viewModel.completedToday, id: \.id) { rc in
                        CompletionRow(
                            studentName: studentNameForID(rc.studentID),
                            workName: workTitleForID(rc.workID),
                            record: rc
                        )
                        .contentShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
        }
    }
}

// MARK: - Small Rows
private struct LessonRow: View {
    let lessonName: String
    let studentNames: String
    let isPresented: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "text.book.closed").foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                if !studentNames.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(studentNames)
                        .font(.system(size: AppTheme.FontSize.body, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                }
                Text(lessonName)
                    .font(.system(size: AppTheme.FontSize.caption, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isPresented {
                Text("Presented")
                    .font(.system(size: AppTheme.FontSize.captionSmall, weight: .semibold, design: .rounded))
                    .foregroundStyle(.green)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.green.opacity(0.12)))
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.04)))
    }
}

private struct CheckInRow: View {
    let ci: WorkCheckIn
    let workTitle: String
    let studentNames: String
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                Image(systemName: "bell").foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    if !studentNames.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(studentNames)
                            .font(.system(size: AppTheme.FontSize.body, weight: .semibold, design: .rounded))
                            .foregroundStyle(.primary)
                    }
                    Text(workTitle)
                        .font(.system(size: AppTheme.FontSize.caption, design: .rounded))
                        .foregroundStyle(.secondary)
                    Text(ci.date, style: .date)
                        .font(.system(size: AppTheme.FontSize.captionSmall, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                // Status badge (scheduled)
                Text(ci.status.rawValue)
                    .font(.system(size: AppTheme.FontSize.captionSmall, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.orange.opacity(0.12)))
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.04)))
        }
        .buttonStyle(.plain)
    }
}

private struct WorkRow: View {
    let work: WorkModel
    let studentNames: String
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                Image(systemName: "hammer").foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    if !studentNames.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(studentNames)
                            .font(.system(size: AppTheme.FontSize.body, weight: .semibold, design: .rounded))
                            .foregroundStyle(.primary)
                    }
                    Text(work.title.isEmpty ? work.workType.rawValue : work.title)
                        .font(.system(size: AppTheme.FontSize.caption, design: .rounded))
                        .foregroundStyle(.secondary)
                    Text(work.createdAt, style: .date)
                        .font(.system(size: AppTheme.FontSize.captionSmall, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.04)))
        }
        .buttonStyle(.plain)
    }
}

private struct CompletionRow: View {
    let studentName: String
    let workName: String
    let record: WorkCompletionRecord

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 2) {
                Text(studentName)
                    .font(.system(size: AppTheme.FontSize.body, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                Text(workName)
                    .font(.system(size: AppTheme.FontSize.caption, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if !record.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Image(systemName: "note.text")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.04)))
    }
}

#Preview {
    // This preview uses an in-memory model container; data will be empty.
    let container = try! ModelContainer(for: Schema([Item.self, Student.self, Lesson.self, StudentLesson.self, WorkModel.self, WorkParticipantEntity.self, WorkCompletionRecord.self, AttendanceRecord.self, WorkCheckIn.self, NonSchoolDay.self, SchoolDayOverride.self]), configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    return TodayView(context: container.mainContext)
}

