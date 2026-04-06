import SwiftUI
import CoreData

struct DayDetailPopover: View {
    let cellID: CellID
    let items: [YearPlanCalendarItem]
    let lessonsByID: [String: CDLesson]
    let onRemove: (CDYearPlanEntry) -> Void
    let onReschedule: (CDYearPlanEntry, Date) -> Void

    @State private var rescheduleTarget: CDYearPlanEntry?
    @State private var rescheduleDate = Date()

    private var dateForCell: Date {
        var comps = DateComponents()
        comps.year = cellID.year
        comps.month = cellID.month
        comps.day = cellID.day
        return AppCalendar.shared.date(from: comps) ?? Date()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(dateForCell.formatted(date: .long, time: .omitted))
                .font(.headline)
                .padding(.bottom, 4)

            ForEach(items) { item in
                itemRow(item)
            }
        }
        .padding()
        .frame(minWidth: 260)
    }

    @ViewBuilder
    private func itemRow(_ item: YearPlanCalendarItem) -> some View {
        let lesson = lessonsByID[item.lessonID]
        let subject = lesson?.subject ?? ""

        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Circle()
                    .fill(AppColors.color(forSubject: subject))
                    .frame(width: 8, height: 8)

                Text(lesson?.name ?? "Unknown")
                    .font(.body)
                    .strikethrough(item.displayStatus == .promoted)

                Spacer()

                statusBadge(for: item)
            }

            if !subject.isEmpty || !(lesson?.group.isEmpty ?? true) {
                Text([subject, lesson?.group].compactMap { $0?.isEmpty == false ? $0 : nil }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let entry = item.planEntry, entry.isPlanned {
                planEntryActions(entry)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func planEntryActions(_ entry: CDYearPlanEntry) -> some View {
        HStack(spacing: 12) {
            if rescheduleTarget?.id == entry.id {
                DatePicker("", selection: $rescheduleDate, displayedComponents: .date)
                    .labelsHidden()
                    .datePickerStyle(.compact)

                Button("Save") {
                    onReschedule(entry, rescheduleDate)
                    rescheduleTarget = nil
                }
                .font(.caption.weight(.medium))

                Button("Cancel") {
                    rescheduleTarget = nil
                }
                .font(.caption)
            } else {
                Button("Reschedule") {
                    rescheduleDate = entry.plannedDate ?? dateForCell
                    rescheduleTarget = entry
                }
                .font(.caption)

                Button("Remove", role: .destructive) {
                    onRemove(entry)
                }
                .font(.caption)
            }
        }
        .padding(.top, 2)
    }

    @ViewBuilder
    private func statusBadge(for item: YearPlanCalendarItem) -> some View {
        switch item.displayStatus {
        case .promoted:
            Text("Promoted")
                .font(.caption)
                .foregroundStyle(.green)
        case .skipped:
            Text("Skipped")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .behindPace:
            Text("Behind")
                .font(.caption)
                .foregroundStyle(.red)
        case .planned:
            Text("Planned")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .scheduled:
            Text("Scheduled")
                .font(.caption)
                .foregroundStyle(.blue)
        case .presented:
            Text("Given")
                .font(.caption)
                .foregroundStyle(.green)
        }
    }
}
