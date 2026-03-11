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
    var regularActionBar: some View {
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
