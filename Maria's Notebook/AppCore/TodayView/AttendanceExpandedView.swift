// AttendanceExpandedView.swift
// Expanded attendance grid view for TodayView

import SwiftUI
import SwiftData
#if os(iOS)
import MessageUI
#endif

/// Attendance Expanded View Logic
struct AttendanceExpandedView: View {
    let date: Date
    let isNonSchoolDay: Bool
    let onChange: () -> Void
    let onToast: (String) -> Void

    @Environment(\.modelContext) var modelContext
    @Environment(\.horizontalSizeClass) var hSizeClass
    @Environment(SaveCoordinator.self) var saveCoordinator

    @Query(sort: Student.sortByLastName)
    private var allStudentsRaw: [Student]
    // DEDUPLICATION: CloudKit sync can create duplicate records with the same ID.
    private var allStudents: [Student] { allStudentsRaw.uniqueByID.filter(\.isEnrolled) }
    private var allStudentIDs: [UUID] { allStudents.map(\.id) }

    @State var viewModel = AttendanceViewModel()

    @SyncedAppStorage("AttendanceEmail.enabled") var emailEnabled: Bool = true
    @State private var showMailSheet = false
    @State var showingTardyReport = false
    @State private var toastMessage: String?
    @State var isEditing: Bool = true
    @State var localSortKey: AttendanceViewModel.SortKey = .lastName
    @State private var activeChipPopover: AttendanceStatus?

    // Persistence for locking
    private static let lockKeyPrefix = "Attendance.locked."
    private let syncedStore = SyncedPreferencesStore.shared

    private func lockKey(for date: Date) -> String {
        let day = AppCalendar.startOfDay(date)
        return AttendanceExpandedView.lockKeyPrefix + DateFormatters.isoDateLocal.string(from: day)
    }

    private func isLocked(for date: Date) -> Bool {
        syncedStore.bool(forKey: lockKey(for: date))
    }

    func setLocked(_ locked: Bool, for date: Date) {
        let key = lockKey(for: date)
        if locked {
            syncedStore.set(true, forKey: key)
        } else {
            syncedStore.remove(key: key)
        }
    }

    var filteredStudents: [Student] {
        let visible = viewModel.visibleStudents(from: allStudents)
        return viewModel.sortedAndFiltered(students: visible)
    }

    private var nonSchoolDayWarning: some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            Image(systemName: SFSymbol.Status.exclamationmarkTriangleFill).foregroundStyle(.yellow)
            Text("Non-school day. Attendance optional.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.bottom, AppTheme.Spacing.sm)
    }

    private var attendanceGrid: some View {
        AttendanceGrid(
            students: filteredStudents,
            recordsByStudentID: viewModel.recordsByStudentID,
            onCycleStatus: { student in
                viewModel.cycleStatus(for: student, modelContext: modelContext)
                saveCoordinator.save(modelContext, reason: "Update status")
                onChange()
            },
            onUpdateNote: { student, note in
                viewModel.updateNote(for: student, note: note, modelContext: modelContext)
                saveCoordinator.save(modelContext, reason: "Update note")
            },
            onUpdateAbsenceReason: { student, reason in
                viewModel.updateAbsenceReason(for: student, reason: reason, modelContext: modelContext)
                saveCoordinator.save(modelContext, reason: "Update reason")
            }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Attendance Summary Strip (iPhone)

    @ViewBuilder
    private var attendanceSummaryStrip: some View {
#if os(iOS)
        if hSizeClass == .compact {
            HStack(spacing: 10) {
                // Primary: In Class count
                HStack(spacing: 6) {
                    Text("In Class")
                        .font(AppTheme.ScaledFont.captionSemibold)
                        .foregroundStyle(.secondary)
                    Text("\(viewModel.inClassCount)")
                        .font(AppTheme.ScaledFont.calloutSemibold)
                        .monospacedDigit()
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.accentColor.opacity(0.12)))
                }

                if viewModel.countTardy > 0 {
                    tappableStatChip(title: "Tardy", count: viewModel.countTardy, color: .blue, status: .tardy)
                }
                if viewModel.countAbsent > 0 {
                    tappableStatChip(title: "Absent", count: viewModel.countAbsent, color: .red, status: .absent)
                }
                if viewModel.countLeftEarly > 0 {
                    tappableStatChip(
                        title: "Left Early", count: viewModel.countLeftEarly,
                        color: .purple, status: .leftEarly
                    )
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, AppTheme.Spacing.compact)
            .padding(.bottom, AppTheme.Spacing.small)
        }
#endif
    }

    private func tappableStatChip(title: String, count: Int, color: Color, status: AttendanceStatus) -> some View {
        Button {
            activeChipPopover = activeChipPopover == status ? nil : status
        } label: {
            HStack(spacing: 4) {
                Circle().fill(color).frame(width: 6, height: 6)
                Text("\(title) \(count)")
                    .font(AppTheme.ScaledFont.captionSmallSemibold)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().strokeBorder(color.opacity(0.20), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .popover(isPresented: Binding(
            get: { activeChipPopover == status },
            set: { if !$0 { activeChipPopover = nil } }
        )) {
            chipPopoverContent(title: title, color: color, status: status)
        }
    }

    private func chipPopoverContent(title: String, color: Color, status: AttendanceStatus) -> some View {
        let studentNames = names(for: status)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Circle().fill(color).frame(width: 8, height: 8)
                Text(title)
                    .font(AppTheme.ScaledFont.calloutSemibold)
            }
            .padding(.bottom, 2)

            if studentNames.isEmpty {
                Text("None")
                    .font(AppTheme.ScaledFont.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(studentNames, id: \.self) { name in
                    Text(name)
                        .font(AppTheme.ScaledFont.callout)
                }
            }
        }
        .padding()
        .frame(minWidth: 160, alignment: .leading)
        .presentationCompactAdaptation(.popover)
    }

    var body: some View {
        VStack(spacing: 0) {
            Divider()

            actionBar

            attendanceSummaryStrip

            if isNonSchoolDay {
                nonSchoolDayWarning
            }

            attendanceGrid
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            loadData()
        }
        .onChange(of: date) { _, _ in
            loadData()
        }
        .onChange(of: allStudentIDs) { _, _ in
            loadData()
        }
        .onChange(of: localSortKey) { _, newValue in
            Task { @MainActor in
                viewModel.sortKey = newValue
            }
        }
        .sheet(isPresented: $showingTardyReport) {
            AttendanceTardyReport()
        }
        .sheet(isPresented: $showMailSheet) {
#if os(iOS)
            AttendanceEmail.composerForCurrentPrefs(
                present: names(for: .present),
                tardy: names(for: .tardy),
                absent: names(for: .absent),
                date: date
            ) { result, error in
                switch result {
                case .sent:
                    onToast("Email sent")
                case .saved:
                    onToast("Draft saved")
                case .failed:
                    onToast("Failed to send: \(error?.localizedDescription ?? "Unknown error")")
                case .cancelled:
                    break
                @unknown default:
                    break
                }
            }
            .ignoresSafeArea()
#endif
        }
    }

    private func loadData() {
        viewModel.load(for: date, students: viewModel.visibleStudents(from: allStudents), modelContext: modelContext)
        isEditing = !isLocked(for: date)
        localSortKey = viewModel.sortKey
    }

    private func names(for status: AttendanceStatus) -> [String] {
        filteredStudents.compactMap { s in
            if let rec = viewModel.recordsByStudentID[s.cloudKitKey], rec.status == status {
                return s.fullName
            }
            return nil
        }
        .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    func prepareAttendanceEmail() {
        let present = names(for: .present)
        let tardy = names(for: .tardy)
        let absent = names(for: .absent)
#if os(iOS)
        if MFMailComposeViewController.canSendMail() {
            showMailSheet = true
        }
#else
        AttendanceEmail.sendUsingMailAppForCurrentPrefs(
            present: present,
            tardy: tardy,
            absent: absent,
            date: date
        ) { success in
            onToast(success ? "Email sent" : "Failed to send email")
        }
#endif
    }
}
