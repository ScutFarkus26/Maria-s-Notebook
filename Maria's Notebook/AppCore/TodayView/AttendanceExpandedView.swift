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

    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var hSizeClass
    @Environment(SaveCoordinator.self) private var saveCoordinator

    @Query(sort: Student.sortByLastName)
    private var allStudentsRaw: [Student]
    // DEDUPLICATION: CloudKit sync can create duplicate records with the same ID.
    private var allStudents: [Student] { allStudentsRaw.uniqueByID }
    private var allStudentIDs: [UUID] { allStudents.map { $0.id } }

    @State private var viewModel = AttendanceViewModel()

    @SyncedAppStorage("AttendanceEmail.enabled") private var emailEnabled: Bool = true
    @State private var showMailSheet = false
    @State private var showingTardyReport = false
    @State private var toastMessage: String?
    @State private var isEditing: Bool = true
    @State private var localSortKey: AttendanceViewModel.SortKey = .lastName

    // Persistence for locking
    private static let lockKeyPrefix = "Attendance.locked."
    private static let lockDateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.calendar = .current
        df.locale = .current
        df.timeZone = .current
        df.dateFormat = "yyyy-MM-dd"
        return df
    }()

    private let syncedStore = SyncedPreferencesStore.shared

    private func lockKey(for date: Date) -> String {
        let day = AppCalendar.startOfDay(date)
        let s = AttendanceExpandedView.lockDateFormatter.string(from: day)
        return AttendanceExpandedView.lockKeyPrefix + s
    }

    private func isLocked(for date: Date) -> Bool {
        syncedStore.bool(forKey: lockKey(for: date))
    }

    private func setLocked(_ locked: Bool, for date: Date) {
        let key = lockKey(for: date)
        if locked {
            syncedStore.set(true, forKey: key)
        } else {
            syncedStore.remove(key: key)
        }
    }

    private var filteredStudents: [Student] {
        let visible = viewModel.visibleStudents(from: allStudents)
        return viewModel.sortedAndFiltered(students: visible)
    }

    // MARK: - Action Bars

    // Compact action bar for iPhone
    @ViewBuilder
    private var compactActionBar: some View {
        HStack(spacing: AppTheme.Spacing.small) {
            // Sort picker
            Picker("Sort", selection: $localSortKey) {
                Text("First").tag(AttendanceViewModel.SortKey.firstName)
                Text("Last").tag(AttendanceViewModel.SortKey.lastName)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 140)

            Spacer()

            // Mark All Present
            Button {
                viewModel.markAllPresent(students: filteredStudents, modelContext: modelContext)
                saveCoordinator.save(modelContext, reason: "Mark all present")
                onChange()
            } label: {
                Label("All Present", systemImage: "checkmark.circle.fill")
                    .font(AppTheme.ScaledFont.captionSemibold)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(isNonSchoolDay || !isEditing)

            // Overflow menu
            Menu {
                // Lock/Unlock
                Button {
                    isEditing.toggle()
                    setLocked(!isEditing, for: date)
                } label: {
                    Label(isEditing ? "Lock Day" : "Unlock Day", systemImage: isEditing ? "lock.fill" : "lock.open")
                }

                // Reset
                Button(role: .destructive) {
                    viewModel.resetDay(students: filteredStudents, modelContext: modelContext)
                    saveCoordinator.save(modelContext, reason: "Reset day")
                    onChange()
                } label: {
                    Label("Reset Day", systemImage: SFSymbol.Action.arrowCounterclockwise)
                }
                .disabled(isNonSchoolDay || !isEditing)

                Divider()

                // Tardy Report
                Button {
                    showingTardyReport = true
                } label: {
                    Label("Tardy Report", systemImage: "chart.bar.doc.horizontal")
                }

                // Email
                if emailEnabled {
                    Button {
                        prepareAttendanceEmail()
                    } label: {
                        Label("Email Attendance", systemImage: SFSymbol.Communication.envelope)
                    }
                    .disabled(isNonSchoolDay)
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 18))
            }
        }
        .padding(.vertical, AppTheme.Spacing.small)
    }

    // Full action bar for iPad/macOS
    private var regularActionBar: some View {
        HStack(spacing: AppTheme.Spacing.md) {
            // Sort
            Picker("Sort", selection: $localSortKey) {
                Text("First").tag(AttendanceViewModel.SortKey.firstName)
                Text("Last").tag(AttendanceViewModel.SortKey.lastName)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 160)

            // Tardy Report
            Button {
                showingTardyReport = true
            } label: {
                Label("Tardy Report", systemImage: "chart.bar.doc.horizontal")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.bordered)
            .help("View Tardy Report")

            Spacer()

            // Lock
            Button {
                isEditing.toggle()
                setLocked(!isEditing, for: date)
            } label: {
                Label(isEditing ? "Lock" : "Unlock", systemImage: isEditing ? "lock.fill" : "lock.open")
            }
            .buttonStyle(.bordered)
            .help(isEditing ? "Lock this day" : "Unlock this day")

            // Reset
            Button {
                viewModel.resetDay(students: filteredStudents, modelContext: modelContext)
                saveCoordinator.save(modelContext, reason: "Reset day")
                onChange()
            } label: {
                Image(systemName: SFSymbol.Action.arrowCounterclockwise)
            }
            .buttonStyle(.bordered)
            .disabled(isNonSchoolDay || !isEditing)
            .help("Reset Day")

            // Mark All Present
            Button("Mark All Present") {
                viewModel.markAllPresent(students: filteredStudents, modelContext: modelContext)
                saveCoordinator.save(modelContext, reason: "Mark all present")
                onChange()
            }
            .buttonStyle(.borderedProminent)
            .disabled(isNonSchoolDay || !isEditing)

            // Email
            if emailEnabled {
                Button {
                    prepareAttendanceEmail()
                } label: {
                    Label("Email", systemImage: SFSymbol.Communication.envelope)
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.bordered)
                .disabled(isNonSchoolDay)
            }
        }
        .padding(.vertical, AppTheme.Spacing.small)
    }

    @ViewBuilder
    private var actionBar: some View {
#if os(iOS)
        if hSizeClass == .compact {
            compactActionBar
        } else {
            regularActionBar
        }
#else
        regularActionBar
#endif
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

    var body: some View {
        VStack(spacing: 0) {
            Divider()

            actionBar

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

    private func prepareAttendanceEmail() {
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
