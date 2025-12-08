import SwiftUI
import SwiftData

struct TodayView: View {
    @Environment(\.modelContext) private var modelContext

    @StateObject private var viewModel: TodayViewModel

    // Navigation state for details
    @State private var selectedWorkID: UUID? = nil
    @State private var selectedStudentLesson: StudentLesson? = nil

    // Lookup helpers from VM caches to avoid per-row fetches
    private var nameForLesson: (UUID) -> String { { id in viewModel.lessonsByID[id]?.name ?? "Lesson" } }
    private var studentNamesForIDs: ([UUID]) -> String { { ids in
        let names = ids.compactMap { viewModel.studentsByID[$0]?.fullName }
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
    private var studentNameForID: (UUID) -> String { { id in viewModel.studentsByID[id]?.fullName ?? "Student" } }

    init(context: ModelContext) {
        _viewModel = StateObject(wrappedValue: TodayViewModel(context: context))
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
        let cal = Calendar.current
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
                            CheckInRow(ci: ci, workTitle: workTitleForID(ci.workID)) { selectedWorkID = ci.workID }
                        }
                    }
                    if !viewModel.todaysCheckIns.isEmpty {
                        Text("Due Today")
                            .font(.system(size: AppTheme.FontSize.caption, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                        ForEach(viewModel.todaysCheckIns, id: \.id) { ci in
                            CheckInRow(ci: ci, workTitle: workTitleForID(ci.workID)) { selectedWorkID = ci.workID }
                        }
                    }
                }
            }
        }
    }

    // MARK: - In Progress
    private var inProgressSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "In Progress Work", systemImage: "hammer")
            if viewModel.inProgressWork.isEmpty {
                ContentUnavailableView("No open work", systemImage: "tray")
            } else {
                VStack(spacing: 8) {
                    ForEach(viewModel.inProgressWork, id: \.id) { work in
                        WorkRow(work: work) { selectedWorkID = work.id }
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
                Text(lessonName)
                    .font(.system(size: AppTheme.FontSize.body, weight: .semibold, design: .rounded))
                if !studentNames.isEmpty {
                    Text(studentNames)
                        .font(.system(size: AppTheme.FontSize.caption, design: .rounded))
                        .foregroundStyle(.secondary)
                }
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
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                Image(systemName: "bell").foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(workTitle)
                        .font(.system(size: AppTheme.FontSize.body, weight: .semibold, design: .rounded))
                    Text(ci.date, style: .date)
                        .font(.system(size: AppTheme.FontSize.caption, design: .rounded))
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
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                Image(systemName: "hammer").foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(work.title.isEmpty ? work.workType.rawValue : work.title)
                        .font(.system(size: AppTheme.FontSize.body, weight: .semibold, design: .rounded))
                    Text(work.createdAt, style: .date)
                        .font(.system(size: AppTheme.FontSize.caption, design: .rounded))
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

