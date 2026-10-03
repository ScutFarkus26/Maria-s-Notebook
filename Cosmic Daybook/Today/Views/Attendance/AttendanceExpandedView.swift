// AttendanceExpandedView.swift
// Expanded attendance grid view for TodayView

import SwiftUI
import CoreData
import OSLog
#if os(iOS)
import MessageUI
#endif

/// Attendance Expanded View Logic
struct AttendanceExpandedView: View {
    let date: Date
    let isNonSchoolDay: Bool
    let onChange: () -> Void
    let onToast: (String) -> Void
    /// A sideways swipe on the iPhone's tiles: true for the next school day.
    var onStepDay: ((Bool) -> Void)?
    /// The Attendance screen's own title shows "Day 37"; Today keeps its own.
    var showsDayInTitle = false
    /// The Attendance screen puts View, the lock and More in its toolbar;
    /// inside Today they sit at the band's edge.
    var hostsToolbar = false

    @Environment(\.managedObjectContext) var viewContext
    @Environment(\.horizontalSizeClass) var hSizeClass
    @Environment(SaveCoordinator.self) var saveCoordinator
    @Environment(\.dependencies) var dependencies
    @Environment(\.undoManager) var undoManager

    /// Reload when the class itself changes. (Not the day's roll, which the
    /// load decides: watching that would load every day twice.)
    private var rosterIDs: [UUID] { dependencies.roster.all.compactMap(\.id) }

    @State var viewModel = AttendanceViewModel()

    @SyncedAppStorage("AttendanceEmail.enabled") var emailEnabled: Bool = true
    @State var showMailSheet = false
    /// The day's newest front-desk email, from any device in the classroom.
    @State var frontDeskSend: AttendanceEmailLog.Send?
    /// Mail couldn't say whether the email went (another Mail app on iOS, or
    /// the Mac's Mail not answering): ask.
    @State var askingWhetherSent = false
    /// Mark Rest Absent & Email asks first, naming who.
    @State var confirmingRestAbsent = false
    @State var showingTardyReport = false
    @State var showingAbsenceReport = false
    @State var confirmingReset = false
    @State var confirmingClose = false
    @State var confirmingCloseAndEmail = false
    /// Group by Level, from the View menu (`AttendanceGrid`).
    @SyncedAppStorage(AttendanceGrid.groupsByLevelKey) var groupsByLevel = true
    @State var isEditing: Bool = true
    @State var localSortKey: AttendanceViewModel.SortKey = AttendanceViewModel.storedSortKey()
    @State var activeChipPopover: AttendanceStatus?
    /// "Everyone's here · 8:14", for a few seconds after a mark completes the roll.
    @State var finishedLine: String?
    /// "Welcome back, Maya", for a few seconds after a returning child is marked in.
    @State var welcomeLine: String?
    /// Bumped to drop the Day 100 confetti.
    @State var confettiBursts = 0
    #if os(iOS)
    /// The Montessori bells on the iPhone's tiles, off until turned on.
    @AppStorage(AttendanceBells.enabledKey) var bellsOn = false
    #endif

    // Locked days are `AttendanceDayLock` records in the classroom share, so
    // an assistant sees them too (they used to be an iCloud setting only the
    // guide's own devices read).
    private func isLocked(for date: Date) -> Bool {
        AttendanceDayLocks.isLocked(date, in: viewContext)
    }

    /// Only the lead guide locks and unlocks days.
    var canLockDays: Bool {
        CDClassroomMembership.currentRole(in: viewContext) == .leadGuide
    }

    func setLocked(_ locked: Bool, for date: Date) {
        let role = CDClassroomMembership.currentRole(in: viewContext)
        guard AttendanceDayLocks.setLocked(
            locked, for: date, role: role, lockedByID: ClassroomIdentity.currentUserRecordName, in: viewContext
        ) else { return }
        // An old-style lock for the day would lock it again on the next
        // carry-over; unlocking clears it.
        if !locked { SyncedPreferencesStore.shared.remove(key: AttendanceDayLocks.legacyKey(for: date)) }
        saveCoordinator.save(viewContext, reason: locked ? "Lock attendance day" : "Unlock attendance day")
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
            viewModel: viewModel,
            isEditing: isEditing,
            actions: AttendanceGridActions(
                tap: { row in
                    undoably("Mark", row) { viewModel.tap($0, modelContext: viewContext) }
                    rang(after: row)
                },
                setStatus: { status, row in
                    undoably("Mark", row) { viewModel.setStatus(status, for: $0, modelContext: viewContext) }
                    rang(after: row)
                },
                markAbsent: { reason, row in
                    undoably("Mark Absent", row) {
                        viewModel.markAbsent(reason: reason, for: $0, modelContext: viewContext)
                    }
                    rang(after: row)
                },
                saveNote: { row, note in
                    undoably("Note", row) { viewModel.updateNote(for: $0, note: note, modelContext: viewContext) }
                },
                savePickup: { row, time in
                    undoably("Pickup Time", row) {
                        viewModel.updatePickup(for: $0, time: time, modelContext: viewContext)
                    }
                },
                markBack: { row in
                    undoably("Back in Class", row) { viewModel.markBack($0, modelContext: viewContext) }
                    rang(after: row)
                }
            ),
            onStepDay: onStepDay
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// A bell for the mark, on the iPhone's tiles (`ring(after:)`).
    private func rang(after row: AttendanceRow) {
        #if os(iOS)
        ring(after: row)
        #endif
    }

    /// Saves a change to the roll and tells the host screen.
    func saved(_ reason: String) {
        saveCoordinator.save(viewContext, reason: reason)
        onChange()
    }

    var body: some View {
        VStack(spacing: 0) {
            if isCompact {
                Divider()
                actionBar
                attendanceSummaryStrip
                compactFrontDeskRow
                if isNonSchoolDay { nonSchoolDayWarning }
            } else {
                arrivalBand
            }

            attendanceGrid

            hintFooter
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Faintly amber once arrival closes, as on the Daybook Assistant.
        .background {
            if !isCompact, viewModel.phase == .late, !viewModel.isFuture {
                Color.lateAmber.opacity(0.05)
            }
        }
        .toolbar {
            if hostsToolbar, !isCompact { rollToolbar }
        }
        .modifier(closeArrivalDialogs)
        .onAppear {
            loadData()
        }
        .onChange(of: date) { _, _ in
            // An Undo belongs to the day it was offered on.
            dependencies.toastService.dismiss()
            finishedLine = nil
            welcomeLine = nil
            loadData()
        }
        .onChange(of: rosterIDs) { _, _ in
            loadData()
        }
        // A mark, lock or front-desk email sent on another device (an
        // assistant's, say) arrives as an iCloud import;
        // the roll is a one-off fetch, so redraw it while it is on screen.
        .onPresentationDataChangeWhenVisible(
            of: ["AttendanceRecord", "AttendanceDayLock", "AttendanceEmailSend"],
            in: viewContext, catchUpOnAppear: false
        ) {
            loadData()
        }
        // A mark made with Siri while the roll is open.
        .onReceive(NotificationCenter.default.publisher(for: .attendanceChangedBySiri)) { _ in
            loadData()
        }
        .onChange(of: localSortKey) { _, newValue in
            viewModel.setSortKey(newValue)
        }
        .onChange(of: viewModel.completions) { rollCompleted() }
        // A mark, Close Arrival or Reset that failed says so, rather than
        // looking as if it worked.
        .onChange(of: viewModel.problem) { _, problem in
            if let problem { dependencies.toastService.showError(problem.message) }
        }
        .modifier(delightFollowUps)
        .task(id: finishedLine) {
            guard finishedLine != nil, (try? await Task.sleep(for: .seconds(5))) != nil else { return }
            finishedLine = nil
        }
#if os(iOS)
        .sensoryFeedback(.success, trigger: viewModel.completions)
#endif
        .confirmationDialog(resetTitle, isPresented: $confirmingReset, titleVisibility: .visible) {
            Button("Reset Day", role: .destructive, action: resetDay)
        } message: {
            Text("Clears every mark, reason and note on the day. You can undo it right after.")
        }
        .sheet(isPresented: $showingTardyReport) {
            AttendanceTardyReport()
        }
        .sheet(isPresented: $showingAbsenceReport) {
            AttendanceAbsenceReport()
        }
        .sheet(isPresented: $showMailSheet) {
#if os(iOS)
            AttendanceEmail.composerForCurrentPrefs(
                present: students(for: .present),
                tardy: students(for: .tardy),
                absent: students(for: .absent),
                leftEarly: students(for: .leftEarly),
                date: date
            ) { result, error in
                switch result {
                case .sent:
                    onToast("Email sent")
                    recordFrontDeskSend(confirmedByHand: false)
                case .saved:
                    onToast("Draft saved")
                case .failed:
                    if let error {
                        let reason = error.localizedDescription
                        Logger.attendance.error("Front-desk email failed: \(reason, privacy: .public)")
                    }
                    onToast("The email didn't send. Check your connection and try again.")
                case .cancelled:
                    break
                @unknown default:
                    break
                }
            }
            .ignoresSafeArea()
#endif
        }
        .modifier(frontDeskFollowUps)
    }

    private func loadData() {
        viewModel.load(
            for: date, students: viewModel.visibleStudents(from: dependencies.roster.all), modelContext: viewContext
        )
        isEditing = !isLocked(for: date)
        localSortKey = viewModel.sortKey
        frontDeskSend = AttendanceEmailLog.latestSend(on: date, in: viewContext)
    }

    func students(for status: AttendanceStatus) -> [AttendanceEmailStudent] {
        viewModel.rows.filter { $0.status == status }.map { AttendanceEmailStudent($0.student) }
    }

    /// The status popover always reads "First Last", regardless of the email's own preference.
    func names(for status: AttendanceStatus) -> [String] {
        AttendanceEmailReport.sorted(students(for: status), by: .firstLast)
            .map { $0.name(order: .firstLast) }
    }
}
