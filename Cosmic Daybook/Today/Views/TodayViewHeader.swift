// TodayViewHeader.swift
// Header and attendance strip components for TodayView - extracted for maintainability

import SwiftUI
import CoreData

// MARK: - TodayView Header Extension

extension TodayView {

    // MARK: - Native macOS Toolbar

    #if os(macOS)
    /// ‹ Today › — the day itself reads in the window subtitle. Today stays in
    /// place and greys out on the current school day, so the stepper never
    /// changes width under the pointer.
    @ToolbarContentBuilder
    var macOSTodayToolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .automatic) {
            Button {
                let previousDate = previousSchoolDaySync(before: viewModel.date)
                viewModel.date = AppCalendar.startOfDay(previousDate)
            } label: {
                Image(systemName: "chevron.left")
            }
            .accessibilityLabel("Previous School Day")
            .help("Previous School Day")

            todayButton

            Button {
                let nextDate = nextSchoolDaySync(after: viewModel.date)
                viewModel.date = AppCalendar.startOfDay(nextDate)
            } label: {
                Image(systemName: "chevron.right")
            }
            .accessibilityLabel("Next School Day")
            .help("Next School Day")

            // The stepper's field is gone, so a far-off day is a calendar away.
            Button {
                isDatePickerPresented = true
            } label: {
                Image(systemName: "calendar")
            }
            .accessibilityLabel("Go to Date")
            .help("Go to a school day")
            .popover(isPresented: $isDatePickerPresented, arrowEdge: .bottom) {
                DatePicker("School Day", selection: schoolDayBinding, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                    .padding(12)
            }

            // The pad's section hides itself while the pad is empty, so this
            // is how a blank page is reached on a day that has nothing on it.
            Button {
                adaptiveWithAnimation(.snappy(duration: 0.2)) {
                    isDayPadExpanded = true
                }
            } label: {
                Label("Day Pad", systemImage: "note.text")
                    .labelStyle(.titleAndIcon)
            }
            .help("Open today's pad")
        }
    }

    /// The picked day, coerced onto the nearest school day.
    private var schoolDayBinding: Binding<Date> {
        Binding(
            get: { viewModel.date },
            set: { newValue in
                let coercedDate = nearestSchoolDaySync(to: newValue)
                viewModel.date = AppCalendar.startOfDay(coercedDate)
            }
        )
    }
    #endif

    /// Back to the current school day; disabled while already there. Shared
    /// by the Mac stepper and the iOS toolbar.
    var todayButton: some View {
        Button("Today") {
            let currentSchoolDay = nearestSchoolDaySync(to: Date())
            viewModel.date = AppCalendar.startOfDay(currentSchoolDay)
        }
        .disabled(isViewingCurrentSchoolDay)
        .help("Return to the current school day")
    }

    private var isViewingCurrentSchoolDay: Bool {
        let currentSchoolDay = nearestSchoolDaySync(to: Date())
        return AppCalendar.startOfDay(viewModel.date) == AppCalendar.startOfDay(currentSchoolDay)
    }

    // MARK: - Floating Button Clearance

    /// Keeps the last row of Today's lists clear of the floating button
    /// (56 pt, 24 pt off the Mac window's corner; 48 pt up on iPad). The
    /// iPhone list already gets its room from `quickCaptureButtonClearance()`.
    var quickCaptureClearance: CGFloat {
        guard isQuickCaptureButtonVisible else { return 0 }
        #if os(macOS)
        return 88
        #else
        return isIPhoneCompact ? 0 : 112
        #endif
    }

    // MARK: - Attendance Band

    /// One line: "19 here · 2 late · 3 absent [chips] … Attendance ›".
    /// Neutral throughout — an amber dot for late, gray for absent, no red
    /// fills. A click anywhere on the band (or on Attendance ›) opens the grid
    /// below it; the absent chips keep their right-click Mark Tardy.
    var attendanceStrip: some View {
        let absentPairs = sortedNamePairs(viewModel.absentToday)
        let leftEarlyPairs = sortedNamePairs(viewModel.leftEarlyToday)
        let counts = viewModel.attendanceSummary
        let summary = TodayAttendanceBandSummary(
            hereCount: counts.presentCount,
            lateCount: counts.tardyCount,
            absentCount: counts.absentCount,
            leftEarlyCount: counts.leftEarlyCount,
            lateNames: counts.tardyCount > 0 ? lateStudentNames : [],
            absentNames: absentPairs.map(\.name),
            leftEarlyNames: leftEarlyPairs.map(\.name)
        )

        return HStack(spacing: 14) {
            attendanceBandCounts(summary: summary, absentPairs: absentPairs, leftEarlyPairs: leftEarlyPairs)
                // VoiceOver hears the band as one sentence; Mark Tardy rides
                // along as an action per absent child.
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(summary.accessibilityLabel)
                .accessibilityActions {
                    ForEach(absentPairs, id: \.id) { pair in
                        Button("Mark \(pair.name) Tardy") { markTardy(pair.id) }
                    }
                }

            Spacer(minLength: 0)

            Button {
                toggleAttendanceExpanded()
            } label: {
                HStack(spacing: 4) {
                    Text("Attendance")
                    Image(systemName: "chevron.right")
                        .imageScale(.small)
                        .rotationEffect(.degrees(isAttendanceExpanded ? 90 : 0))
                }
                .font(AppTheme.ScaledFont.captionSemibold)
                .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)
            .fixedSize()
            .accessibilityValue(isAttendanceExpanded ? "Expanded" : "Collapsed")
            .accessibilityHint("Shows the attendance grid")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .surface(UIConstants.CornerRadius.control, fill: Color.primary.opacity(UIConstants.OpacityConstants.hint))
        .contentShape(Rectangle())
        .onTapGesture { toggleAttendanceExpanded() }
        .task(id: lateNamesKey) {
            lateStudentNames = counts.tardyCount > 0 ? loadLateStudentNames() : []
        }
        // Marks arriving from the Daybook Assistant or another device. The
        // counts and names come from the view model, which only a reload
        // refreshes; the grid is collapsed by default, so without this an
        // imported mark changed nothing on Today until a revisit.
        .onPresentationDataChangeWhenVisible(
            of: ["AttendanceRecord", "AttendanceDayLock"], in: viewContext, catchUpOnAppear: false
        ) {
            viewModel.scheduleReload()
        }
    }

    private func toggleAttendanceExpanded() {
        adaptiveWithAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            isAttendanceExpanded.toggle()
        }
    }

    @ViewBuilder
    private func attendanceBandCounts(
        summary: TodayAttendanceBandSummary,
        absentPairs: [(id: UUID, name: String)],
        leftEarlyPairs: [(id: UUID, name: String)]
    ) -> some View {
        HStack(spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text("\(summary.hereCount)")
                    .font(AppTheme.ScaledFont.titleSmall)
                    .monospacedDigit()
                Text("here")
                    .font(AppTheme.ScaledFont.callout)
                    .foregroundStyle(.secondary)
            }
            .fixedSize()

            if let lateText = summary.lateText {
                Divider().frame(height: 18)
                TodayLateCount(text: lateText, names: summary.lateNames, help: summary.lateHelp)
            }

            if summary.absentText != nil || summary.leftEarlyText != nil {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        if let absentText = summary.absentText {
                            namedGroup(absentText, dot: .gray, pairs: absentPairs, marksTardy: true)
                        }
                        if let leftEarlyText = summary.leftEarlyText {
                            namedGroup(leftEarlyText, dot: .purple, pairs: leftEarlyPairs, marksTardy: false)
                        }
                    }
                }
                .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// "3 absent" with a dot, then the children as neutral chips.
    private func namedGroup(
        _ text: String,
        dot: Color,
        pairs: [(id: UUID, name: String)],
        marksTardy: Bool
    ) -> some View {
        HStack(spacing: 6) {
            bandDot(dot)
            Text(text)
                .font(AppTheme.ScaledFont.callout)
                .foregroundStyle(.secondary)
                .fixedSize()
            ForEach(pairs, id: \.id) { pair in
                if marksTardy {
                    studentPill(pair.name)
                        .contextMenu {
                            Text(pair.name)
                            Divider()
                            Button {
                                markTardy(pair.id)
                            } label: {
                                Label("Mark Tardy", systemImage: "clock")
                            }
                        }
                } else {
                    studentPill(pair.name)
                }
            }
        }
    }

    /// Resolves names once per student — sort key and display label are the
    /// same short-name value.
    private func sortedNamePairs(_ ids: [UUID]) -> [(id: UUID, name: String)] {
        ids.map { (id: $0, name: displayNameForID($0)) }
            .filter { !$0.name.trimmed().isEmpty }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Changes whenever the late names could: another day, another filter,
    /// or a different tally after a reload.
    private var lateNamesKey: String {
        let counts = viewModel.attendanceSummary
        return "\(viewModel.date.timeIntervalSinceReferenceDate)|\(viewModel.levelFilter.rawValue)|"
            + "\(counts.presentCount)|\(counts.tardyCount)|\(counts.absentCount)|\(counts.leftEarlyCount)"
    }

    /// The day's late children in short-name format. The view model counts
    /// them but keeps no list, so this reads the day's records — one small
    /// fetch, only when the tally changes and someone is late.
    private func loadLateStudentNames() -> [String] {
        let day = AppCalendar.startOfDay(viewModel.date)
        guard let nextDay = AppCalendar.shared.date(byAdding: .day, value: 1, to: day) else { return [] }
        let records = TodayDataFetcher.fetchAttendance(day: day, nextDay: nextDay, context: viewContext).records
        let lateIDs = records.compactMap { record -> UUID? in
            guard record.status == .tardy, let id = record.studentID.asUUID,
                  let student = viewModel.studentsByID[id],
                  viewModel.levelFilter.matches(student.level) else { return nil }
            return id
        }
        return sortedNamePairs(lateIDs).map(\.name)
    }

    private func bandDot(_ color: Color) -> some View {
        Circle().fill(color).frame(width: 8, height: 8)
    }

    // MARK: - Student Chip

    func studentPill(_ name: String) -> some View {
        Text(name)
            .font(AppTheme.ScaledFont.captionSmallSemibold)
            .foregroundStyle(.secondary)
            .textSelection(.disabled)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .capsuleFill(Color.primary.opacity(UIConstants.OpacityConstants.veryFaint))
            .fixedSize()
    }
}

// MARK: - Late Count

/// "2 late" with an amber dot. Hovering names the children (tooltip); a click
/// lists them in a popover, which also serves iPad, where there's no hover.
private struct TodayLateCount: View {
    let text: String
    let names: [String]
    let help: String
    @State private var isShowingNames = false

    var body: some View {
        Button {
            isShowingNames = true
        } label: {
            HStack(spacing: 6) {
                Circle().fill(Color.lateAmber).frame(width: 8, height: 8)
                Text(text)
                    .font(AppTheme.ScaledFont.callout)
                    .foregroundStyle(.secondary)
            }
            .fixedSize()
        }
        .buttonStyle(.plain)
        .help(help)
        .popover(isPresented: $isShowingNames, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Late")
                    .font(AppTheme.ScaledFont.captionSemibold)
                    .foregroundStyle(.secondary)
                if names.isEmpty {
                    Text(text)
                } else {
                    ForEach(names, id: \.self) { name in
                        Text(name)
                    }
                }
            }
            .padding(12)
            .presentationCompactAdaptation(.popover)
        }
    }
}
