import SwiftUI
import SwiftData
import OSLog

/// Main view for managing recurring schedules
struct SchedulesView: View {
    private static let logger = Logger.schedules
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Schedule.name) private var schedules: [Schedule]
    @Query(sort: \Student.firstName) private var studentsRaw: [Student]
    private var students: [Student] { studentsRaw.filter { $0.isEnrolled } }

    @State private var showingAddSheet = false
    @State private var selectedSchedule: Schedule?
    @State private var scheduleToEdit: Schedule?

    var body: some View {
        VStack(spacing: 0) {
            ViewHeader(title: "Schedules") {
                Button {
                    showingAddSheet = true
                } label: {
                    Label("Add Schedule", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }

            Divider()

            ScrollView {
                if schedules.isEmpty {
                    emptyState
                } else {
                    schedulesGrid
                }
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            ScheduleEditorSheet(schedule: nil)
        }
        .sheet(item: $selectedSchedule) { schedule in
            ScheduleDetailSheet(schedule: schedule) { editSchedule in
                selectedSchedule = nil
                Task { @MainActor in
                    do {
                        try await Task.sleep(for: .milliseconds(300))
                    } catch {
                        Self.logger.warning("Failed to sleep before showing editor: \(error, privacy: .public)")
                    }
                    scheduleToEdit = editSchedule
                }
            }
        }
        .sheet(item: $scheduleToEdit) { schedule in
            ScheduleEditorSheet(schedule: schedule)
        }
    }

    // MARK: - Schedules Grid

    private var schedulesGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 320, maximum: 500), spacing: 16)], spacing: 16) {
            ForEach(schedules) { schedule in
                ScheduleCard(schedule: schedule, students: students)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedSchedule = schedule
                    }
                    .contextMenu {
                        Button {
                            selectedSchedule = schedule
                        } label: {
                            Label("View", systemImage: "eye")
                        }

                        Button {
                            scheduleToEdit = schedule
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }

                        Divider()

                        Button(role: .destructive) {
                            deleteSchedule(schedule)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
            }
        }
        .padding(24)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "clock.badge.checkmark")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("No Schedules Yet")
                .font(.title2.weight(.semibold))

            // swiftlint:disable:next line_length
            Text("Create recurring schedules for activities like reading support, special lessons, or other regular sessions.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 350)

            Button {
                showingAddSheet = true
            } label: {
                Label("Add First Schedule", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    // MARK: - Actions

    private func deleteSchedule(_ schedule: Schedule) {
        modelContext.delete(schedule)
        modelContext.safeSave()
    }
}

// MARK: - Schedule Card

struct ScheduleCard: View {
    let schedule: Schedule
    let students: [Student]

    private var studentLookup: [String: Student] {
        Dictionary(uniqueKeysWithValues: students.map { ($0.id.uuidString.lowercased(), $0) })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(spacing: 10) {
                Image(systemName: schedule.icon)
                    .font(.title2)
                    .foregroundStyle(Color(hex: schedule.colorHex) ?? .blue)

                Text(schedule.name)
                    .font(.headline)

                Spacer()

                Text("\(schedule.safeSlots.count) slots")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            // Days summary
            if schedule.activeWeekdays.isEmpty {
                Text("No slots configured")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .italic()
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(schedule.activeWeekdays, id: \.self) { weekday in
                        dayRow(weekday: weekday)
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.08))
        )
    }

    private func dayRow(weekday: Weekday) -> some View {
        let slots = schedule.slots(for: weekday)
        return HStack(alignment: .top, spacing: 12) {
            Text(weekday.shortName)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(width: 40, alignment: .leading)

            VStack(alignment: .leading, spacing: 4) {
                ForEach(slots) { slot in
                    HStack(spacing: 8) {
                        if let timeString = slot.timeString, !timeString.isEmpty {
                            Text(timeString)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .frame(width: 50, alignment: .leading)
                        }

                        if let student = studentLookup[slot.studentID.lowercased()] {
                            Text(student.fullName)
                                .font(.subheadline)
                        } else {
                            Text("Unknown Student")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .italic()
                        }
                    }
                }
            }

            Spacer()
        }
    }
}

// MARK: - Color Extension

extension Color {
    init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        var rgb: UInt64 = 0
        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else { return nil }

        let r = Double((rgb & 0xFF0000) >> 16) / 255.0
        let g = Double((rgb & 0x00FF00) >> 8) / 255.0
        let b = Double(rgb & 0x0000FF) / 255.0

        self.init(red: r, green: g, blue: b)
    }
}

#Preview {
    SchedulesView()
        .previewEnvironment()
}
