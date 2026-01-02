import SwiftUI
import SwiftData
import UniformTypeIdentifiers
#if os(iOS)
import MessageUI
#endif
#if os(macOS)
import AppKit
#endif
#if os(iOS)
import UIKit
#endif

struct AttendanceView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var hSizeClass
    @EnvironmentObject private var saveCoordinator: SaveCoordinator

    @Query(sort: [SortDescriptor(\Student.lastName), SortDescriptor(\Student.firstName)])
    private var allStudents: [Student]

    @StateObject private var viewModel = AttendanceViewModel()

    @SyncedAppStorage("AttendanceEmail.enabled") private var emailEnabled: Bool = true
    @SyncedAppStorage("AttendanceEmail.to") private var emailTo: String = ""
    @SyncedAppStorage("AttendanceEmail.from") private var emailFrom: String = ""

    @State private var showMailSheet = false
    @State private var toastMessage: String? = nil
    @State private var isEditing: Bool = true
    @State private var localSortKey: AttendanceViewModel.SortKey = .lastName

    private var filteredStudents: [Student] {
        let visible = viewModel.visibleStudents(from: allStudents)
        return viewModel.sortedAndFiltered(students: visible)
    }

    private var columns: [GridItem] {
    #if os(iOS)
        if hSizeClass == .compact {
            return [GridItem(.flexible(minimum: 0), spacing: 12)]
        }
    #endif
        return [GridItem(.adaptive(minimum: 220, maximum: 300), spacing: 16)]
    }

    private var isNonSchoolDay: Bool {
        SchoolCalendar.isNonSchoolDay(viewModel.selectedDate, using: modelContext)
    }

    // MARK: - Per-day Lock Persistence
    private static let lockKeyPrefix = "Attendance.locked."
    private static let lockDateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.calendar = .current
        df.locale = .current
        df.timeZone = .current
        df.dateFormat = "yyyy-MM-dd"
        return df
    }()

    private func lockKey(for date: Date) -> String {
        let day = date.normalizedDay()
        let s = AttendanceView.lockDateFormatter.string(from: day)
        return AttendanceView.lockKeyPrefix + s
    }

    private func isLocked(for date: Date) -> Bool {
        UserDefaults.standard.bool(forKey: lockKey(for: date))
    }

    private func setLocked(_ locked: Bool, for date: Date) {
        let key = lockKey(for: date)
        if locked {
            UserDefaults.standard.set(true, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .onAppear {
            // Ensure initial selection is a school day
            let coerced = SchoolCalendar.nearestSchoolDay(to: viewModel.selectedDate, using: modelContext)
            if coerced != viewModel.selectedDate { viewModel.selectedDate = coerced }
            viewModel.load(for: viewModel.selectedDate, students: viewModel.visibleStudents(from: allStudents), modelContext: modelContext)
            _ = saveCoordinator.save(modelContext, reason: "Ensure attendance records exist for selected day")
            isEditing = !isLocked(for: viewModel.selectedDate)
            localSortKey = viewModel.sortKey
        }
        .onChange(of: viewModel.selectedDate) { _, newValue in
            let coerced = SchoolCalendar.nearestSchoolDay(to: newValue, using: modelContext)
            if coerced != newValue {
                viewModel.selectedDate = coerced
                return
            }
            viewModel.load(for: newValue, students: viewModel.visibleStudents(from: allStudents), modelContext: modelContext)
            _ = saveCoordinator.save(modelContext, reason: "Ensure attendance records exist for selected day")
            isEditing = !isLocked(for: viewModel.selectedDate)
        }
        .onChange(of: allStudents.map { $0.id }) { _, _ in
            // If students change (added/removed), ensure records exist
            viewModel.load(for: viewModel.selectedDate, students: viewModel.visibleStudents(from: allStudents), modelContext: modelContext)
            _ = saveCoordinator.save(modelContext, reason: "Ensure attendance records exist for selected day")
        }
        .onChange(of: localSortKey) { _, newValue in
            // Defer the update to avoid publishing during view updates
            DispatchQueue.main.async {
                viewModel.sortKey = newValue
            }
        }
#if os(iOS)
        .sheet(isPresented: $showMailSheet) {
            AttendanceEmail.composerForCurrentPrefs(
                present: names(for: .present),
                tardy: names(for: .tardy),
                absent: names(for: .absent),
                date: viewModel.selectedDate
            ) { result, error in
                switch result {
                case .sent: toast("Email sent")
                case .saved: toast("Draft saved")
                case .failed: toast("Failed to send: \(error?.localizedDescription ?? "Unknown error")")
                case .cancelled: break
                @unknown default: break
                }
            }
            .ignoresSafeArea()
        }
#endif
        .overlay(alignment: .top) {
            if let message = toastMessage {
                Text(message)
                    .font(.system(size: AppTheme.FontSize.caption, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.black.opacity(0.85))
                    )
                    .foregroundColor(.white)
                    .shadow(color: Color.black.opacity(0.2), radius: 6, x: 0, y: 3)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .padding(.top, 8)
            }
        }
#if os(iOS)
        .safeAreaInset(edge: .bottom) {
            if hSizeClass == .compact {
                HStack(spacing: 12) {
                    if emailEnabled {
                        Button {
                            prepareAttendanceEmail()
                        } label: {
                            Label("Email", systemImage: "envelope")
                        }
                        .disabled(isNonSchoolDay)
                    }
                    Button("Reset") {
                        viewModel.resetDay(students: filteredStudents, modelContext: modelContext)
                        _ = saveCoordinator.save(modelContext, reason: "Reset day")
                    }
                    .disabled(isNonSchoolDay || !isEditing)
                    Button("All Present") {
                        viewModel.markAllPresent(students: filteredStudents, modelContext: modelContext)
                        _ = saveCoordinator.save(modelContext, reason: "Mark all present")
                    }
                    .disabled(isNonSchoolDay || !isEditing)
                    Spacer()
                }
                .padding()
                .background(.bar)
            }
        }
#endif
    }

    @ViewBuilder
    private var header: some View {
    #if os(iOS)
        if hSizeClass == .compact {
            compactHeader
        } else {
            regularHeader
        }
    #else
        regularHeader
    #endif
    }

    // MARK: - Header
    private var regularHeader: some View {
        VStack(spacing: 12) {
            // Row 1: Date navigation and primary actions
            HStack(spacing: 16) {
                Button {
                    let prev = SchoolCalendar.previousSchoolDay(before: viewModel.selectedDate, using: modelContext)
                    viewModel.selectedDate = prev.normalizedDay()
                } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.plain)
                .help("Previous Day")

                DatePicker("Date", selection: Binding(get: { viewModel.selectedDate }, set: { newValue in
                    let coerced = SchoolCalendar.nearestSchoolDay(to: newValue, using: modelContext)
                    viewModel.selectedDate = coerced.normalizedDay()
                }), displayedComponents: .date)
#if os(macOS)
                    .datePickerStyle(.field)
#else
                    .datePickerStyle(.compact)
#endif

                Button {
                    let next = SchoolCalendar.nextSchoolDay(after: viewModel.selectedDate, using: modelContext)
                    viewModel.selectedDate = next.normalizedDay()
                } label: {
                    Image(systemName: "chevron.right")
                }
                .buttonStyle(.plain)
                .help("Next Day")

                Button("Today") {
                    let today = Date()
                    let coerced = SchoolCalendar.nearestSchoolDay(to: today, using: modelContext)
                    viewModel.selectedDate = coerced.normalizedDay()
                }
                .buttonStyle(.plain)
                .help("Jump to Today")
                .keyboardShortcut("t", modifiers: [.command])

                Spacer()

                Button {
                    isEditing.toggle()
                    setLocked(!isEditing, for: viewModel.selectedDate)
                } label: {
                    ZStack {
                        // Reserve width for the widest label to prevent layout shift
                        Label("Unlock", systemImage: "lock.open").opacity(0)
                        Label(isEditing ? "Lock" : "Unlock", systemImage: isEditing ? "lock.fill" : "lock.open")
                    }
                }
                .buttonStyle(.bordered)
                .keyboardShortcut("e", modifiers: [.command])
                .help(isEditing ? "Lock this day to prevent changes" : "Unlock this day to allow editing")

                Button("Mark All Present") {
                    viewModel.markAllPresent(students: filteredStudents, modelContext: modelContext)
                    _ = saveCoordinator.save(modelContext, reason: "Mark all present")
                }
                .buttonStyle(.borderedProminent)
                .disabled(isNonSchoolDay || !isEditing)
                .keyboardShortcut("p", modifiers: [.command, .shift])

                Button("Reset Day") {
                    viewModel.resetDay(students: filteredStudents, modelContext: modelContext)
                    _ = saveCoordinator.save(modelContext, reason: "Reset day")
                }
                .buttonStyle(.bordered)
                .disabled(isNonSchoolDay || !isEditing)
                .keyboardShortcut("r", modifiers: [.command, .shift])
            }
            
            // Row 2: Sort filter
            HStack(spacing: 16) {
                // Sort picker
                Picker("Sort", selection: $localSortKey) {
                    Text("First").tag(AttendanceViewModel.SortKey.firstName)
                    Text("Last").tag(AttendanceViewModel.SortKey.lastName)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 200)

                Spacer()
            }

            if isNonSchoolDay {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
                    Text("Marked as a non-school day. Attendance is optional; bulk actions disabled.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.05)))
            }

            // Row 3: Header stats: "In Class" treats Present + Tardy as in-class attendance.
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                // Primary stat: In Class
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text("In Class")
                            .font(.system(size: AppTheme.FontSize.callout, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                        Text("\(viewModel.inClassCount)")
                            .font(.system(size: AppTheme.FontSize.titleSmall, weight: .semibold, design: .rounded))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                Capsule().fill(Color.accentColor.opacity(0.12))
                            )
                    }
                }

                Divider()
                    .frame(height: 24)
                    .padding(.horizontal, 4)

                // Breakdown chips (secondary)
                HStack(spacing: 12) {
                    breakdownChip(title: "Present", count: viewModel.countPresent, color: .green)
                    breakdownChip(title: "Tardy", count: viewModel.countTardy, color: .blue)
                    breakdownChip(title: "Absent", count: viewModel.countAbsent, color: .red)
                    breakdownChip(title: "Left Early", count: viewModel.countLeftEarly, color: .purple)
                    breakdownChip(title: "Unmarked", count: viewModel.countUnmarked, color: .gray)
                }

                if emailEnabled {
                    Divider()
                        .frame(height: 24)
                        .padding(.horizontal, 4)

                    Button {
                        prepareAttendanceEmail()
                    } label: {
                        Label("Email", systemImage: "envelope")
                    }
                    .buttonStyle(.bordered)
                    .disabled(isNonSchoolDay)
                    .help("Send attendance report via email")
                }

                Spacer()
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 16)
    }

    // Compact header for iPhone (compact width)
    private var compactHeader: some View {
        VStack(spacing: 10) {
            // Row 1: Date navigation
            HStack(spacing: 12) {
                Button {
                    let prev = SchoolCalendar.previousSchoolDay(before: viewModel.selectedDate, using: modelContext)
                    viewModel.selectedDate = prev.normalizedDay()
                } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.plain)

                DatePicker("", selection: Binding(get: { viewModel.selectedDate }, set: { newValue in
                    let coerced = SchoolCalendar.nearestSchoolDay(to: newValue, using: modelContext)
                    viewModel.selectedDate = coerced.normalizedDay()
                }), displayedComponents: .date)
                .labelsHidden()
                .datePickerStyle(.compact)

                Button {
                    let next = SchoolCalendar.nextSchoolDay(after: viewModel.selectedDate, using: modelContext)
                    viewModel.selectedDate = next.normalizedDay()
                } label: {
                    Image(systemName: "chevron.right")
                }
                .buttonStyle(.plain)

                Spacer()

                Button("Today") {
                    let today = Date()
                    let coerced = SchoolCalendar.nearestSchoolDay(to: today, using: modelContext)
                    viewModel.selectedDate = coerced.normalizedDay()
                }
                .buttonStyle(.plain)

                Button {
                    isEditing.toggle()
                    setLocked(!isEditing, for: viewModel.selectedDate)
                } label: {
                    ZStack {
                        Label("Unlock", systemImage: "lock.open").opacity(0)
                        Label(isEditing ? "Lock" : "Unlock", systemImage: isEditing ? "lock.fill" : "lock.open")
                    }
                }
                .buttonStyle(.plain)
                .help(isEditing ? "Lock this day to prevent changes" : "Unlock this day to allow editing")
            }

            if isNonSchoolDay {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
                    Text("Marked as a non-school day. Attendance is optional; bulk actions disabled.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.05)))
            }

            // Row 2: Primary stat + breakdown chips (scrollable)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .center, spacing: 8) {
                    // In Class primary stat
                    HStack(spacing: 8) {
                        Text("In Class")
                            .font(.system(size: AppTheme.FontSize.callout, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                        Text("\(viewModel.inClassCount)")
                            .font(.system(size: AppTheme.FontSize.titleSmall, weight: .semibold, design: .rounded))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                Capsule().fill(Color.accentColor.opacity(0.12))
                            )
                    }

                    // Breakdown chips
                    breakdownChip(title: "Present", count: viewModel.countPresent, color: .green)
                    breakdownChip(title: "Tardy", count: viewModel.countTardy, color: .blue)
                    breakdownChip(title: "Absent", count: viewModel.countAbsent, color: .red)
                    breakdownChip(title: "Left Early", count: viewModel.countLeftEarly, color: .purple)
                    breakdownChip(title: "Unmarked", count: viewModel.countUnmarked, color: .gray)
                }
                .padding(.vertical, 2)
            }

            // Row 3: Sort filter
            HStack(spacing: 12) {
                Picker("Sort", selection: $localSortKey) {
                    Text("First").tag(AttendanceViewModel.SortKey.firstName)
                    Text("Last").tag(AttendanceViewModel.SortKey.lastName)
                }
                .pickerStyle(.segmented)

                Spacer()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private func statChip(label: String, value: Int, color: Color) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text("\(label): \(value)")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(color.opacity(0.12)))
    }

    private func breakdownChip(title: String, count: Int, color: Color) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text("\(title) \(count)")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule().strokeBorder(color.opacity(0.20), lineWidth: 1)
        )
    }

    // MARK: - Content
    private var content: some View {
        ScrollView {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                ForEach(filteredStudents, id: \.id) { student in
                    AttendanceCard(
                        student: student,
                        record: viewModel.recordsByStudent[student.id.uuidString],
                        isEditing: isEditing,
                        onTap: {
                            viewModel.cycleStatus(for: student, modelContext: modelContext)
                            _ = saveCoordinator.save(modelContext, reason: "Update attendance status")
                        },
                        onEditNote: { newNote in
                            viewModel.updateNote(for: student, note: newNote, modelContext: modelContext)
                            _ = saveCoordinator.save(modelContext, reason: "Update attendance note")
                        }
                    )
                }
            }
            .padding(20)
        }
    }

    private func names(for status: AttendanceStatus) -> [String] {
        filteredStudents.compactMap { s in
            if let rec = viewModel.recordsByStudent[s.id.uuidString], rec.status == status {
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
        } else {
            toast("Mail is not configured on this device.")
        }
#else
        AttendanceEmail.sendUsingMailAppForCurrentPrefs(
            present: present,
            tardy: tardy,
            absent: absent,
            date: viewModel.selectedDate
        ) { success in
            if success { toast("Email sent") } else { toast("Failed to send email") }
        }
#endif
    }

    private func toast(_ message: String) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
            toastMessage = message
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation(.easeInOut(duration: 0.25)) {
                toastMessage = nil
            }
        }
    }
}


