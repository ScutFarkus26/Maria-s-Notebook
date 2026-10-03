// AttendanceExpandedView+Controls.swift
// The Mac and iPad roll's controls: View (sort, group by level), the day's
// lock, and the More menu (Reset Day, Reopen Arrival, the reports, the
// email). In the Attendance window's toolbar, or at the band's edge where
// the roll sits inside Today.

import SwiftUI

extension AttendanceExpandedView {

    // MARK: - Toolbar

    /// The three controls as toolbar items, for the Attendance screen.
    @ToolbarContentBuilder
    var rollToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            viewMenu
            lockButton
            moreMenu
        }
    }

    /// The same three at the band's edge, where the roll has no toolbar of
    /// its own (inside Today).
    var inlineControls: some View {
        HStack(spacing: 2) {
            viewMenu
            lockButton
            moreMenu
        }
        .buttonStyle(.borderless)
        .labelStyle(.iconOnly)
        .fixedSize()
    }

    // MARK: - View

    private var viewMenu: some View {
        Menu {
            Picker("Sort By", selection: $localSortKey) {
                Text("First Name").tag(AttendanceViewModel.SortKey.firstName)
                Text("Last Name").tag(AttendanceViewModel.SortKey.lastName)
            }
            .pickerStyle(.inline)
            Toggle("Group by Level", isOn: $groupsByLevel)
        } label: {
            Label("View", systemImage: "line.3.horizontal.decrease.circle")
        }
        .help("Sort and group the roll")
    }

    // MARK: - Lock

    @ViewBuilder
    private var lockButton: some View {
        if canLockDays {
            Button {
                isEditing.toggle()
                setLocked(!isEditing, for: date)
            } label: {
                Label(isEditing ? "Lock Day" : "Unlock Day", systemImage: isEditing ? "lock.open" : "lock.fill")
            }
            .help(isEditing ? "Lock this day so no one can change it" : "Unlock this day")
        }
    }

    // MARK: - More

    private var moreMenu: some View {
        Menu {
            if isEditing, !viewModel.isFuture, viewModel.phase == .late {
                Button("Reopen Arrival", systemImage: "arrow.uturn.backward") {
                    withAnimation(.smooth(duration: 0.3)) { viewModel.reopenArrival() }
                }
            }
            Button("Reset Day…", systemImage: SFSymbol.Action.arrowCounterclockwise, role: .destructive) {
                confirmingReset = true
            }
            .disabled(isNonSchoolDay || !isEditing)
            Divider()
            Button("Tardy Report", systemImage: "chart.bar.doc.horizontal") { showingTardyReport = true }
            Button("Absence Report", systemImage: "chart.bar.doc.horizontal") { showingAbsenceReport = true }
            if emailEnabled, !isNonSchoolDay {
                Divider()
                Button(
                    frontDeskSend == nil ? "Email Front Desk" : "Email Front Desk Again",
                    systemImage: SFSymbol.Communication.envelope,
                    action: prepareAttendanceEmail
                )
                if frontDeskSend == nil {
                    Button("Mark Email as Sent", systemImage: "checkmark.circle") {
                        recordFrontDeskSend(confirmedByHand: true)
                    }
                }
            }
        } label: {
            Label("More", systemImage: "ellipsis.circle")
        }
        .help("Reset, reports and the front-desk email")
    }

    // MARK: - Closing arrival

    /// Close Arrival…'s question, and Close Arrival & Email…'s, each naming
    /// who's still not marked.
    var closeArrivalDialogs: CloseArrivalDialogs {
        CloseArrivalDialogs(
            confirmingClose: $confirmingClose,
            confirmingCloseAndEmail: $confirmingCloseAndEmail,
            unmarkedNames: viewModel.unmarkedNames,
            isLate: viewModel.phase == .late,
            onClose: { viewModel.phase == .late ? markRestAbsent() : closeArrival() },
            onCloseAndEmail: {
                closeArrival()
                prepareAttendanceEmail()
            }
        )
    }

    /// With arrival already closed here: just the children still unmarked.
    private func markRestAbsent() {
        withAnimation(.smooth(duration: 0.3)) {
            viewModel.markUnmarkedAbsent(modelContext: viewContext)
        }
        saved("Mark the rest absent")
    }
}

/// The questions before arrival closes, as a modifier so the roll's body
/// stays one line here.
struct CloseArrivalDialogs: ViewModifier {
    @Binding var confirmingClose: Bool
    @Binding var confirmingCloseAndEmail: Bool
    let unmarkedNames: [String]
    let isLate: Bool
    let onClose: () -> Void
    let onCloseAndEmail: () -> Void

    private var count: Int { unmarkedNames.count }
    private var names: String { unmarkedNames.formatted(.list(type: .and)) }

    func body(content: Content) -> some View {
        content
            .confirmationDialog(
                count == 1 ? "Mark 1 child absent?" : "Mark \(count) children absent?",
                isPresented: $confirmingClose, titleVisibility: .visible
            ) {
                Button("Mark \(count) Absent", role: .destructive, action: onClose)
            } message: {
                Text(isLate ? "\(names)." : "\(names). After this, a child who comes in is marked late.")
            }
            .confirmationDialog(
                "Close arrival and email the front desk?",
                isPresented: $confirmingCloseAndEmail, titleVisibility: .visible
            ) {
                Button("Mark \(count) Absent & Email", action: onCloseAndEmail)
                Button("Mark \(count) Absent Only", action: onClose)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("\(names) \(count == 1 ? "isn't" : "aren't") marked. "
                    + "They'll be marked absent, and anyone who comes in after is marked late.")
            }
    }
}
