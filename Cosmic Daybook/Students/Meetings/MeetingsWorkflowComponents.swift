import SwiftUI
import CoreData
import UniformTypeIdentifiers

// MARK: - Queue Sidebar

/// The children waiting for a meeting, sorted by need, with this cycle's
/// progress on top and the absent and met children folded away below.
struct MeetingsQueueSidebar: View {
    let upNext: [CDStudent]
    let absent: [CDStudent]
    let met: [CDStudent]
    /// Progress counts the whole class (age filter applied, search not).
    let metCount: Int
    let totalCount: Int
    let signals: [UUID: MeetingQueueSignals]
    let draftIDs: Set<UUID>
    let cadenceDays: Int
    /// Rows can be dragged into a custom order (custom order, no search).
    let canReorder: Bool
    @Binding var selectedStudentID: UUID?
    @Binding var isAbsentExpanded: Bool
    @Binding var isMetExpanded: Bool
    let onMove: (IndexSet, Int) -> Void
    /// Puts a recently-met child back into the queue at the given index (nil = top).
    var onRequeue: (@MainActor (UUID, Int?) -> Void)?
    var onScheduleMeeting: ((CDStudent, Date?) -> Void)?
    var onPickMeetingDate: ((CDStudent) -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            MeetingsProgressHeader(metCount: metCount, totalCount: totalCount)
            Divider()
            List(selection: $selectedStudentID) {
                upNextSection
                if !absent.isEmpty {
                    Section(isExpanded: $isAbsentExpanded) {
                        ForEach(absent) { studentRow($0, isMet: false) }
                    } header: {
                        Text("Absent Today · \(absent.count)")
                    }
                }
                if !met.isEmpty {
                    Section(isExpanded: $isMetExpanded) {
                        ForEach(met) { student in
                            if onRequeue != nil, let id = student.id {
                                studentRow(student, isMet: true)
                                    .onDrag { NSItemProvider(object: id.uuidString as NSString) }
                            } else {
                                studentRow(student, isMet: true)
                            }
                        }
                    } header: {
                        Text("Met This Cycle · \(met.count)")
                    }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .quickCaptureButtonClearance()
        }
    }

    private var upNextSection: some View {
        Section {
            if upNext.isEmpty {
                Text(totalCount == 0 ? "No children to show" : "Everyone has met this cycle")
                    .foregroundStyle(.secondary)
                    .selectionDisabled()
            }
            ForEach(upNext) { studentRow($0, isMet: false) }
                .onMove(perform: canReorder ? onMove : nil)
                .onInsert(of: [Self.dragType]) { index, providers in
                    insertDroppedStudents(providers, at: index)
                }
        } header: {
            Text("Up Next · \(upNext.count)")
        }
    }

    /// Met rows are dragged as their student id, so a drop into Up Next can
    /// name the child without carrying the object.
    private static let dragType = UTType.plainText

    private func insertDroppedStudents(_ providers: [NSItemProvider], at index: Int) {
        guard let onRequeue else { return }
        let droppable = Set(met.compactMap(\.id))
        for provider in providers {
            _ = provider.loadObject(ofClass: NSString.self) { object, _ in
                guard let string = object as? String,
                      let id = UUID(uuidString: string),
                      droppable.contains(id) else { return }
                Task { @MainActor in
                    onRequeue(id, index)
                }
            }
        }
    }

    // The tag must be a non-optional UUID: List(selection: Binding<UUID?>) only
    // matches tags of exactly UUID, so tagging with the optional `student.id`
    // makes every row silently unselectable.
    @ViewBuilder
    private func studentRow(_ student: CDStudent, isMet: Bool) -> some View {
        let signal = student.id.flatMap { signals[$0] } ?? MeetingQueueSignals()
        let row = MeetingQueueRow(
            student: student,
            signal: signal,
            isLate: MeetingQueueArrangement.isLate(signal, cadenceDays: cadenceDays),
            hasDraft: student.id.map(draftIDs.contains) ?? false,
            isMet: isMet
        )
        .contextMenu { rowMenu(for: student, scheduledDate: signal.scheduled, isMet: isMet) }
        if let id = student.id {
            row.tag(id)
        } else {
            row.selectionDisabled()
        }
    }

    // MARK: - Row Menu

    @ViewBuilder
    private func rowMenu(for student: CDStudent, scheduledDate: Date?, isMet: Bool) -> some View {
        Button {
            selectedStudentID = student.id
        } label: {
            Label("Start Meeting", systemImage: "play.fill")
        }

        if let onRequeue, let id = student.id, isMet {
            Button {
                onRequeue(id, nil)
            } label: {
                Label("Move to Up Next", systemImage: "arrow.up.to.line")
            }
        }

        if let onScheduleMeeting {
            Divider()
            MeetingMoreMenuItems(
                scheduledDate: scheduledDate,
                onSchedule: { onScheduleMeeting(student, $0) },
                canClear: false,
                onPickDay: { onPickMeetingDate?(student) },
                onClear: nil
            )
        }
    }
}

// MARK: - Progress

/// "13 to go · 10 of 23 met" with a bar.
struct MeetingsProgressHeader: View {
    let metCount: Int
    let totalCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(totalCount - metCount == 0 ? "All met" : "\(totalCount - metCount) to go")
                    .font(.title3.weight(.semibold))
                Text("\(metCount) of \(totalCount) met")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: Double(metCount), total: Double(max(totalCount, 1)))
                .tint(.accentColor)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Queue Row

struct MeetingQueueRow: View {
    let student: CDStudent
    let signal: MeetingQueueSignals
    var isLate = false
    var hasDraft = false
    var isMet = false

    var body: some View {
        HStack(spacing: 10) {
            StudentAvatarView(student: student, size: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text(student.shortName)
                    .font(.subheadline.weight(.medium))
                HStack(spacing: 0) {
                    Text(waitText)
                        .fontWeight(isLate ? .semibold : .regular)
                        .foregroundStyle(isLate ? AppColors.warning : .secondary)
                    if let extra = extraText {
                        Text(" · \(extra)")
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.caption)
                .lineLimit(1)
            }

            Spacer(minLength: 4)

            if hasDraft {
                Image(systemName: "pencil")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Draft in progress")
            }

            if let date = signal.scheduled {
                Text(Self.dayLabel(date))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .capsuleFill(Color.accentColor.opacity(UIConstants.OpacityConstants.medium))
                    .accessibilityLabel("Booked \(Self.dayLabel(date))")
            }

            if isMet {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(AppColors.success)
                    .accessibilityLabel("Met")
            }
        }
        .padding(.vertical, 2)
    }

    private var waitText: String {
        guard let days = signal.daysWaiting() else { return "New · never met" }
        return days == 1 ? "1 day" : "\(days) days"
    }

    private var extraText: String? {
        var parts: [String] = []
        if signal.stuckWork > 0 { parts.append("\(signal.stuckWork) stuck") }
        if signal.focusCarried > 0 { parts.append("\(signal.focusCarried) focus") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// "Today", "Tomorrow", or "Oct 8".
    static func dayLabel(_ date: Date) -> String {
        if AppCalendar.isSameDay(date, Date()) { return "Today" }
        if AppCalendar.isSameDay(date, AppCalendar.addingDays(1, to: Date())) { return "Tomorrow" }
        return DateFormatters.shortMonthDay.string(from: date)
    }
}
