// AttendanceExpandedView+ActionBars.swift
// Action bar views extracted to reduce type body length

import SwiftUI

// MARK: - Action Bars

extension AttendanceExpandedView {

    // Compact action bar for iPhone
    @ViewBuilder
    var compactActionBar: some View {
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
                viewModel.markAllPresent(modelContext: viewContext)
                saved("Mark all present")
            } label: {
                Label("All Present", systemImage: "checkmark.circle.fill")
                    .font(AppTheme.ScaledFont.captionSemibold)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(isNonSchoolDay || !isEditing || viewModel.isFuture)

            // Overflow menu
            Menu {
                // Lock/Unlock (the lead guide's alone)
                if canLockDays {
                    Button {
                        isEditing.toggle()
                        setLocked(!isEditing, for: date)
                    } label: {
                        Label(isEditing ? "Lock Day" : "Unlock Day", systemImage: isEditing ? "lock.fill" : "lock.open")
                    }
                }

                // Reset (asks first, then offers Undo)
                Button(role: .destructive) {
                    confirmingReset = true
                } label: {
                    Label("Reset Day…", systemImage: SFSymbol.Action.arrowCounterclockwise)
                }
                .disabled(isNonSchoolDay || !isEditing)

                #if os(iOS)
                // The Montessori bells as children are marked in (this phone only)
                Toggle(isOn: $bellsOn) {
                    Label("Bells", systemImage: "bell")
                }
                #endif

                Divider()

                // Tardy Report
                Button {
                    showingTardyReport = true
                } label: {
                    Label("Tardy Report", systemImage: "chart.bar.doc.horizontal")
                }

                // Absence Report
                Button {
                    showingAbsenceReport = true
                } label: {
                    Label("Absence Report", systemImage: "chart.bar.doc.horizontal")
                }

                // Email (also on its own row once everyone's marked)
                if emailEnabled {
                    Button {
                        prepareAttendanceEmail()
                    } label: {
                        Label("Email Front Desk", systemImage: SFSymbol.Communication.envelope)
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
    @ViewBuilder
    var regularActionBar: some View {
#if os(iOS)
        // An iPad column can be narrower than the one row needs (beside
        // Insights in landscape it's ~690 pt), which crushed Lock and Mark All
        // Present to a letter or a word per line: two rows there instead. The
        // two keep their one-line width, so when the row only just fits, the
        // sort picker (flexible up to 160 pt) is what gives.
        ViewThatFits(in: .horizontal) {
            regularActionRow
            regularActionRows
        }
        .padding(.vertical, AppTheme.Spacing.small)
#else
        regularActionRow
            .padding(.vertical, AppTheme.Spacing.small)
#endif
    }

    /// Every action on one row: the Mac's bar, and the iPad's when it fits.
    private var regularActionRow: some View {
        HStack(spacing: AppTheme.Spacing.md) {
            sortPicker
            reportsMenu

            Spacer()

            lockButton
            resetButton
            markAllPresentButton
            frontDeskButton
        }
    }

    /// The narrow iPad column's bar: sort, reports and the day's lock and
    /// reset on top; marking everyone present and the email beneath, trailing
    /// (one above the other when even that row is too wide).
    private var regularActionRows: some View {
        VStack(spacing: AppTheme.Spacing.small) {
            HStack(spacing: AppTheme.Spacing.md) {
                sortPicker
                reportsMenu

                Spacer(minLength: 0)

                lockButton
                resetButton
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: AppTheme.Spacing.md) {
                    Spacer(minLength: 0)

                    markAllPresentButton
                    frontDeskButton
                }
                VStack(alignment: .trailing, spacing: AppTheme.Spacing.small) {
                    markAllPresentButton
                    frontDeskButton
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }

    // Sort
    private var sortPicker: some View {
        Picker("Sort", selection: $localSortKey) {
            Text("First").tag(AttendanceViewModel.SortKey.firstName)
            Text("Last").tag(AttendanceViewModel.SortKey.lastName)
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 160)
    }

    // Reports
    private var reportsMenu: some View {
        Menu {
            Button("Tardy Report") { showingTardyReport = true }
            Button("Absence Report") { showingAbsenceReport = true }
        } label: {
            Label("Reports", systemImage: "chart.bar.doc.horizontal")
                .labelStyle(.iconOnly)
        }
        .buttonStyle(.bordered)
        .help("View Reports")
    }

    // Lock (the lead guide's alone)
    @ViewBuilder
    private var lockButton: some View {
        if canLockDays {
            Button {
                isEditing.toggle()
                setLocked(!isEditing, for: date)
            } label: {
                Label(isEditing ? "Lock" : "Unlock", systemImage: isEditing ? "lock.fill" : "lock.open")
            }
            .buttonStyle(.bordered)
            #if os(iOS)
            .fixedSize()
            #endif
            .help(isEditing ? "Lock this day" : "Unlock this day")
        }
    }

    // Reset (asks first, then offers Undo)
    private var resetButton: some View {
        Button {
            confirmingReset = true
        } label: {
            Image(systemName: SFSymbol.Action.arrowCounterclockwise)
        }
        .buttonStyle(.bordered)
        .disabled(isNonSchoolDay || !isEditing)
        .help("Reset Day…")
    }

    // Mark All Present
    private var markAllPresentButton: some View {
        Button("Mark All Present") {
            viewModel.markAllPresent(modelContext: viewContext)
            saved("Mark all present")
        }
        .buttonStyle(.borderedProminent)
        #if os(iOS)
        .fixedSize()
        #endif
        .disabled(isNonSchoolDay || !isEditing || viewModel.isFuture)
    }

    // Email the front desk: prominent once everyone's marked, and
    // who sent it once it has gone
    @ViewBuilder
    private var frontDeskButton: some View {
        if emailEnabled {
            frontDeskControl
                .disabled(isNonSchoolDay)
        }
    }

    @ViewBuilder
    var actionBar: some View {
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
}
