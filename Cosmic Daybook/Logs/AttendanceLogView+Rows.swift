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

            // CDNote indicator
            if !record.latestUnifiedNoteText.isEmpty {
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
            // Change status submenu
            Menu {
                ForEach(availableStatuses, id: \.self) { status in
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
        }
    }

    private func updateRecordStatus(_ record: CDAttendanceRecord, to status: AttendanceStatus) {
        record.status = status
        dependencies.saveCoordinator.save(viewContext, reason: "Update attendance status")
    }

    private func deleteRecord(_ record: CDAttendanceRecord) {
        viewContext.delete(record)
        dependencies.saveCoordinator.save(viewContext, reason: "Delete attendance record")
    }
}
