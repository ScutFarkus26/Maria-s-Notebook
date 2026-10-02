// AttendanceExpandedView+ActionBars.swift
// The iPhone's action bar. (The Mac and iPad have the band and the toolbar:
// `+Band`, `+Controls`.)

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

            // Mark the rest present (only while someone's unmarked)
            if let title = markRestPresentTitle, isEditing, !isNonSchoolDay {
                Button(action: markRestPresent) {
                    Label(title, systemImage: "checkmark.circle.fill")
                        .font(AppTheme.ScaledFont.captionSemibold)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }

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

    /// The iPhone's bar; the Mac and iPad have the band (`arrivalBand`).
    @ViewBuilder
    var actionBar: some View {
#if os(iOS)
        compactActionBar
#endif
    }
}
