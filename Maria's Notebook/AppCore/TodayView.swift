// TodayView.swift
// Today hub showing lessons, scheduled check-ins (WorkPlanItem), follow-ups (Stale Contracts), and completions.
// Updated to use WorkContract and WorkPlanItem instead of legacy WorkCheckIn.

import SwiftUI
import SwiftData

/// Today hub view. Binds to TodayViewModel and renders multiple sections.
struct TodayView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appRouter) private var appRouter
    @Environment(\.calendar) private var calendar
    @EnvironmentObject private var restoreCoordinator: RestoreCoordinator

    @StateObject private var viewModel: TodayViewModel

    // Navigation state
    @State private var selectedContractID: UUID? = nil
    @State private var selectedStudentLesson: StudentLesson? = nil

    // OPTIMIZATION: Use lightweight queries for change detection only
    // Only fetch IDs to detect changes, not full objects - significantly reduces memory usage
    @Query(sort: [SortDescriptor(\StudentLesson.id)]) private var studentLessonsForChangeDetection: [StudentLesson]
    @Query(sort: [SortDescriptor(\WorkPlanItem.id)]) private var planItemsForChangeDetection: [WorkPlanItem]
    
    // MEMORY OPTIMIZATION: Extract only IDs for change detection to avoid loading full objects
    private var studentLessonIDs: [UUID] {
        studentLessonsForChangeDetection.map { $0.id }
    }
    
    private var planItemIDs: [UUID] {
        planItemsForChangeDetection.map { $0.id }
    }
    
    // Helpers
    private var nameForLesson: (UUID) -> String { { id in viewModel.lessonsByID[id]?.name ?? "Lesson" } }
    
    private var duplicateFirstNames: Set<String> {
        let firsts = viewModel.studentsByID.values.map { $0.firstName.trimmed().lowercased() }
        var counts: [String: Int] = [:]
        for f in firsts { counts[f, default: 0] += 1 }
        return Set(counts.filter { $0.value > 1 }.map { $0.key })
    }

    private var displayNameForID: (UUID) -> String { { id in
        guard let s = viewModel.studentsByID[id] else { return "Student" }
        let first = s.firstName
        let key = first.trimmed().lowercased()
        if duplicateFirstNames.contains(key) {
            if let initialChar = s.lastName.trimmed().first {
                return "\(first) \(String(initialChar).uppercased())."
            }
        }
        return first
    } }

    private var studentNamesForIDs: ([UUID]) -> String { { ids in
        let names = ids.map { displayNameForID($0) }
        return names.joined(separator: ", ")
    } }

    @ViewBuilder
    private func studentPill(_ name: String, color: Color) -> some View {
        Text(name)
            .font(.system(size: AppTheme.FontSize.captionSmall, weight: .semibold, design: .rounded))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(color.opacity(0.12)))
    }

    // MARK: - Init
    init(context: ModelContext) {
        _viewModel = StateObject(wrappedValue: TodayViewModel(context: context, calendar: AppCalendar.shared))
    }

    var body: some View {
        Group {
            if restoreCoordinator.isRestoring {
                VStack(spacing: 16) {
                    ProgressView().controlSize(.large)
                    Text("Restoring data…")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
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
            }
        }
        .onAppear {
            viewModel.setCalendar(calendar)
            AppCalendar.adopt(timeZoneFrom: calendar)
            // Ensure initial date is a school day
            let coerced = SchoolCalendar.nearestSchoolDay(to: viewModel.date, using: modelContext)
            if coerced != viewModel.date {
                viewModel.date = AppCalendar.startOfDay(coerced)
            }
        }
        .onChange(of: calendar) { _, newCal in
            viewModel.setCalendar(newCal)
            AppCalendar.adopt(timeZoneFrom: newCal)
        }
        .onChange(of: viewModel.date) { _, newValue in
            // Ensure date is always a school day
            let coerced = SchoolCalendar.nearestSchoolDay(to: newValue, using: modelContext)
            if coerced != newValue {
                viewModel.date = AppCalendar.startOfDay(coerced)
            }
        }
        .onChange(of: studentLessonIDs) { _, _ in viewModel.reload() }
        .onChange(of: planItemIDs) { _, _ in viewModel.reload() }
        .onChange(of: appRouter.planningInboxRefreshTrigger) { _, _ in
            viewModel.reload()
        }
        // Sheet for Contract Details
        .sheet(isPresented: Binding(get: { selectedContractID != nil }, set: { if !$0 { selectedContractID = nil } })) {
            if let id = selectedContractID {
                WorkDetailContainerView(workID: id) {
                    selectedContractID = nil
                    viewModel.reload()
                }
            }
        }
        // Sheet for Student Lesson Details
        .sheet(isPresented: Binding(get: { selectedStudentLesson != nil }, set: { if !$0 { selectedStudentLesson = nil } })) {
            if let sl = selectedStudentLesson {
                StudentLessonDetailView(studentLesson: sl) {
                    selectedStudentLesson = nil
                }
#if os(macOS)
                .frame(minWidth: 720, minHeight: 640)
                .presentationSizingFitted()
#else
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
#endif
            }
        }
    }

    // MARK: - Header
    private var header: some View {
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
                    let prev = viewModel.previousDayWithLessons(before: viewModel.date)
                    viewModel.date = AppCalendar.startOfDay(prev)
                } label: { Image(systemName: "chevron.left") }
                .buttonStyle(.plain)

                DatePicker("Date", selection: Binding(get: { viewModel.date }, set: { newValue in
                    let coerced = SchoolCalendar.nearestSchoolDay(to: newValue, using: modelContext)
                    viewModel.date = AppCalendar.startOfDay(coerced)
                }), displayedComponents: .date)
#if os(macOS)
                .datePickerStyle(.field)
#else
                .datePickerStyle(.compact)
#endif

                Button {
                    let next = viewModel.nextDayWithLessons(after: viewModel.date)
                    viewModel.date = AppCalendar.startOfDay(next)
                } label: { Image(systemName: "chevron.right") }
                .buttonStyle(.plain)

                Button("Today") {
                    let today = Date()
                    let coerced = SchoolCalendar.nearestSchoolDay(to: today, using: modelContext)
                    viewModel.date = AppCalendar.startOfDay(coerced)
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

            if !(viewModel.absentToday.isEmpty && viewModel.leftEarlyToday.isEmpty) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(viewModel.absentToday.sorted { displayNameForID($0).localizedCaseInsensitiveCompare(displayNameForID($1)) == .orderedAscending }, id: \.self) { sid in
                            let name = displayNameForID(sid)
                            if !name.trimmed().isEmpty {
                                studentPill(name, color: .red)
                            }
                        }
                        if !viewModel.absentToday.isEmpty && !viewModel.leftEarlyToday.isEmpty {
                            Color.clear.frame(width: 8)
                        }
                        ForEach(viewModel.leftEarlyToday.sorted { displayNameForID($0).localizedCaseInsensitiveCompare(displayNameForID($1)) == .orderedAscending }, id: \.self) { sid in
                            let name = displayNameForID(sid)
                            if !name.trimmed().isEmpty {
                                studentPill(name, color: .purple)
                            }
                        }
                    }
                    .padding(.leading, 8)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

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
                    .frame(maxWidth: .infinity, alignment: .center)
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

    // MARK: - Check-Ins (Scheduled via WorkPlanItem)
    private var checkInsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Scheduled Check-Ins", systemImage: "bell")
            if viewModel.overdueSchedule.isEmpty && viewModel.todaysSchedule.isEmpty {
                ContentUnavailableView("No check-ins due", systemImage: "checkmark.circle")
                    .frame(maxWidth: .infinity, alignment: .center)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    if !viewModel.overdueSchedule.isEmpty {
                        Text("Overdue")
                            .font(.system(size: AppTheme.FontSize.caption, weight: .semibold, design: .rounded))
                            .foregroundStyle(.red)
                        ForEach(viewModel.overdueSchedule) { item in
                            ContractScheduleRow(item: item,
                                              studentName: resolveStudentName(for: item.contract),
                                              lessonName: resolveLessonName(for: item.contract)) {
                                selectedContractID = item.contract.id
                            }
                        }
                    }
                    if !viewModel.todaysSchedule.isEmpty {
                        Text("Due Today")
                            .font(.system(size: AppTheme.FontSize.caption, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                        ForEach(viewModel.todaysSchedule) { item in
                            ContractScheduleRow(item: item,
                                              studentName: resolveStudentName(for: item.contract),
                                              lessonName: resolveLessonName(for: item.contract)) {
                                selectedContractID = item.contract.id
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - In Progress / Follow-Ups (Stale Contracts)
    private var inProgressSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Follow-Ups Due", systemImage: "bolt")
            if viewModel.staleFollowUps.isEmpty {
                ContentUnavailableView("No follow-ups due", systemImage: "checkmark.circle")
                    .frame(maxWidth: .infinity, alignment: .center)
            } else {
                VStack(spacing: 8) {
                    ForEach(viewModel.staleFollowUps) { item in
                        ContractFollowUpRow(item: item,
                                          studentName: resolveStudentName(for: item.contract),
                                          lessonName: resolveLessonName(for: item.contract)) {
                            selectedContractID = item.contract.id
                        }
                    }
                }
            }
        }
    }

    // MARK: - Completed
    private var completedSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Completed Today", systemImage: "checkmark.circle")
            if viewModel.completedContracts.isEmpty {
                ContentUnavailableView("No completions yet", systemImage: "clock")
            } else {
                VStack(spacing: 8) {
                    ForEach(viewModel.completedContracts) { contract in
                        CompletionRow(
                            studentName: resolveStudentName(for: contract),
                            lessonName: resolveLessonName(for: contract),
                            contract: contract
                        )
                        .contentShape(RoundedRectangle(cornerRadius: 10))
                        .onTapGesture {
                            selectedContractID = contract.id
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Helpers
    private func resolveStudentName(for contract: WorkContract) -> String {
        guard let uuid = contract.studentID.asUUID else { return "Student" }
        return displayNameForID(uuid)
    }
    
    private func resolveLessonName(for contract: WorkContract) -> String {
        guard let uuid = contract.lessonID.asUUID else { return "Lesson" }
        return nameForLesson(uuid)
    }
}

// MARK: - Rows

private struct ContractScheduleRow: View {
    let item: ContractScheduleItem
    let studentName: String
    let lessonName: String
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                Image(systemName: item.planItem.reason?.icon ?? "bell").foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(studentName)
                        .font(.system(size: AppTheme.FontSize.body, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                    Text(lessonName)
                        .font(.system(size: AppTheme.FontSize.caption, design: .rounded))
                        .foregroundStyle(.secondary)
                    
                    HStack(spacing: 4) {
                        Text(item.planItem.reason?.label ?? "Check-In")
                        if let note = item.planItem.note, !note.isEmpty {
                            Text("• \(note)")
                        }
                    }
                    .font(.system(size: AppTheme.FontSize.captionSmall, design: .rounded))
                    .foregroundStyle(.secondary)
                }
                Spacer()
                Text(item.planItem.scheduledDate, style: .date)
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

private struct ContractFollowUpRow: View {
    let item: ContractFollowUpItem
    let studentName: String
    let lessonName: String
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                Image(systemName: "arrow.clockwise").foregroundStyle(.purple)
                VStack(alignment: .leading, spacing: 2) {
                    Text(studentName)
                        .font(.system(size: AppTheme.FontSize.body, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                    Text(lessonName)
                        .font(.system(size: AppTheme.FontSize.caption, design: .rounded))
                        .foregroundStyle(.secondary)
                    Text("\(item.daysSinceTouch) days since update")
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

private struct LessonRow: View {
    let lessonName: String
    let studentNames: String
    let isPresented: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "text.book.closed").foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                if !studentNames.trimmed().isEmpty {
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

private struct CompletionRow: View {
    let studentName: String
    let lessonName: String
    let contract: WorkContract

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 2) {
                Text(studentName)
                    .font(.system(size: AppTheme.FontSize.body, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                Text(lessonName)
                    .font(.system(size: AppTheme.FontSize.caption, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let note = contract.completionNote, !note.trimmed().isEmpty {
                Image(systemName: "note.text")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.04)))
    }
}
