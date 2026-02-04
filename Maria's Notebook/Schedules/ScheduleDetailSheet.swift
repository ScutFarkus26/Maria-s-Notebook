import SwiftUI
import SwiftData

/// Detail view for viewing a schedule's full configuration
struct ScheduleDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let schedule: Schedule
    let onEdit: (Schedule) -> Void

    @Query(sort: \Student.firstName) private var students: [Student]

    private var studentLookup: [String: Student] {
        Dictionary(uniqueKeysWithValues: students.map { ($0.id.uuidString, $0) })
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Header info
                    headerSection

                    if !schedule.notes.isEmpty {
                        notesSection
                    }

                    Divider()

                    // Schedule by day
                    scheduleSection
                }
                .padding(24)
            }
            .navigationTitle(schedule.name)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    Button {
                        onEdit(schedule)
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 500, minHeight: 400)
        #endif
    }

    // MARK: - Header Section

    private var headerSection: some View {
        HStack(spacing: 16) {
            Image(systemName: schedule.icon)
                .font(.system(size: 40))
                .foregroundStyle(Color(hex: schedule.colorHex) ?? .blue)
                .frame(width: 60, height: 60)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill((Color(hex: schedule.colorHex) ?? .blue).opacity(0.15))
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(schedule.name)
                    .font(.title2.weight(.bold))

                Text("\(schedule.safeSlots.count) slots across \(schedule.activeWeekdays.count) days")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }

    // MARK: - Notes Section

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Notes", systemImage: "note.text")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)

            Text(schedule.notes)
                .font(.body)
        }
    }

    // MARK: - Schedule Section

    private var scheduleSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Weekly Schedule")
                .font(.title3.weight(.semibold))

            if schedule.activeWeekdays.isEmpty {
                emptyScheduleState
            } else {
                ForEach(Weekday.schoolDays, id: \.self) { weekday in
                    daySection(weekday: weekday)
                }
            }
        }
    }

    private func daySection(weekday: Weekday) -> some View {
        let slots = schedule.slots(for: weekday)

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(weekday.rawValue)
                    .font(.headline)

                Spacer()

                if !slots.isEmpty {
                    Text("\(slots.count) student\(slots.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if slots.isEmpty {
                Text("No students scheduled")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
                    .italic()
                    .padding(.vertical, 8)
            } else {
                VStack(spacing: 6) {
                    ForEach(slots) { slot in
                        slotRow(slot: slot)
                    }
                }
            }

            Divider()
        }
    }

    private func slotRow(slot: ScheduleSlot) -> some View {
        HStack(spacing: 12) {
            if let student = studentLookup[slot.studentID] {
                // Student avatar/initials
                Text(student.initials)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Color(hex: schedule.colorHex) ?? .blue))

                VStack(alignment: .leading, spacing: 2) {
                    Text(student.fullName)
                        .font(.subheadline)

                    if !slot.notes.isEmpty {
                        Text(slot.notes)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Image(systemName: "person.crop.circle.badge.questionmark")
                    .foregroundStyle(.secondary)

                Text("Unknown Student")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .italic()
            }

            Spacer()

            if let timeString = slot.timeString, !timeString.isEmpty {
                Text(timeString)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.03))
        )
    }

    private var emptyScheduleState: some View {
        VStack(spacing: 12) {
            Image(systemName: "calendar.badge.plus")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)

            Text("No students scheduled yet")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Button {
                onEdit(schedule)
            } label: {
                Label("Add Students", systemImage: "plus")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }
}

#Preview {
    ScheduleDetailSheet(schedule: Schedule(name: "Reading Support")) { _ in }
        .previewEnvironment()
}
