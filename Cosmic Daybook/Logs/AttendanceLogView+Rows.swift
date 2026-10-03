// AttendanceLogView+Rows.swift
// The per-record row of the attendance log, and the edits it offers.

import SwiftUI
import CoreData

extension AttendanceLogView {

    // MARK: - Row

    /// `studentsByID` is the render's roster lookup, built once per render.
    @ViewBuilder
    // swiftlint:disable:next function_body_length
    func attendanceRow(for record: CDAttendanceRecord, studentsByID: [UUID: CDStudent]) -> some View {
        HStack(alignment: .center, spacing: 12) {
            // Status indicator
            Circle()
                .fill(record.status.color)
                .frame(width: 12, height: 12)

            VStack(alignment: .leading, spacing: 2) {
                // CDStudent name
                if let studentID = record.studentIDUUID, let student = studentsByID[studentID] {
                    Text(student.shortName)
                        .font(AppTheme.ScaledFont.bodySemibold)
                } else {
                    Text("Unknown Student")
                        .font(AppTheme.ScaledFont.bodySemibold)
                        .foregroundStyle(.secondary)
                }

                // Status and reason
                HStack(spacing: 6) {
                    Text(record.status.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if record.status == .absent && record.absenceReason != .none {
                        Text("•")
                            .foregroundStyle(.secondary)
                        Image(systemName: record.absenceReason.icon)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(record.absenceReason.displayName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            // Note indicator
            if record.note?.isEmpty == false {
                Image(systemName: "note.text")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .surface(
            UIConstants.CornerRadius.control,
            fill: Color.primary.opacity(UIConstants.OpacityConstants.trace),
            style: .continuous
        )
        .contentShape(Rectangle())
        .contextMenu {
            let canEdit = CDAttendanceStore(context: viewContext).canWrite(on: record.date)
            // Ahead of the day, only an absence (or clearing it).
            let statuses = availableStatuses.filter { AttendanceRules.allows($0, on: record.date ?? Date()) }
            // Change status submenu
            Menu {
                ForEach(statuses, id: \.self) { status in
                    Button {
                        updateRecordStatus(record, to: status)
                    } label: {
                        Label(status.displayName, systemImage: status == record.status ? "checkmark" : "circle")
                    }
                    .disabled(status == record.status)
                }
            } label: {
                Label("Change Status", systemImage: "arrow.triangle.2.circlepath")
            }
            .disabled(!canEdit)

            if let studentID = record.studentIDUUID {
                #if os(macOS)
                Button {
                    openStudentInNewWindow(studentID)
                } label: {
                    Label("View Student", systemImage: "person.text.rectangle")
                }
                #endif
            }

            Divider()

            Button(role: .destructive) {
                deleteRecord(record)
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .disabled(!canEdit)
        }
    }

    /// Through the store, as a grid tap goes: it refuses a locked day and
    /// stamps who marked it, when, and `markedAt`.
    private func updateRecordStatus(_ record: CDAttendanceRecord, to status: AttendanceStatus) {
        let store = CDAttendanceStore(context: viewContext)
        guard store.updateStatus(record, to: status) else {
            showRefusal(for: record, store: store)
            return
        }
        dependencies.saveCoordinator.save(viewContext, reason: "Update attendance status")
    }

    private func deleteRecord(_ record: CDAttendanceRecord) {
        let store = CDAttendanceStore(context: viewContext)
        guard store.delete(record) else {
            showRefusal(for: record, store: store)
            return
        }
        dependencies.saveCoordinator.save(viewContext, reason: "Delete attendance record")
    }

    /// The store refuses only a locked day (every role may write attendance,
    /// `ClassroomPermissions`); otherwise a refused status change means the
    /// record already had that status, so there's nothing to say.
    private func showRefusal(for record: CDAttendanceRecord, store: CDAttendanceStore) {
        guard store.isLocked(record.date ?? Date()) else { return }
        dependencies.toastService.showError("That day's attendance is locked. Unlock it to make changes.")
    }
}
