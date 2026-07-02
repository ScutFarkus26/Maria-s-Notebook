import SwiftUI
import CoreData
import OSLog

struct BookClubSessionDetailView: View {
    @ObservedObject var session: CDBookClubSession
    @Environment(\.managedObjectContext) private var viewContext
    let onClose: () -> Void
    let onDelete: () -> Void

    @State private var viewModel = BookClubSessionsViewModel()
    @State private var showingEditor = false
    @State private var showingRegenerateConfirm = false
    @State private var showingDeleteConfirm = false
    @State private var leaderReassignTarget: CDBookClubMeeting?

    nonisolated private static let logger = Logger.bookClub

    private var packet: CDBookClubPacket? {
        viewModel.packet(for: session, in: viewContext)
    }

    private var roster: [CDStudent] {
        viewModel.roster(for: session, in: viewContext)
    }

    private var orderedMeetings: [CDBookClubMeeting] {
        session.orderedMeetings
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    summarySection
                    rosterStrip
                    statusPicker
                    scheduleSection
                    Divider()
                    actionsSection
                }
                .padding(16)
            }
        }
        .sheet(isPresented: $showingEditor) {
            BookClubSessionEditorSheet(editingSession: session)
                .frame(minWidth: 560, minHeight: 600)
        }
        .sheet(item: $leaderReassignTarget) { meeting in
            LeaderReassignSheet(
                meeting: meeting,
                roster: roster,
                onSelect: { studentID in
                    meeting.leaderStudentID = studentID?.uuidString ?? ""
                    meeting.modifiedAt = Date()
                    session.modifiedAt = Date()
                    viewContext.safeSave()
                    leaderReassignTarget = nil
                },
                onCancel: { leaderReassignTarget = nil }
            )
            .frame(minWidth: 320, minHeight: 360)
        }
        .confirmationDialog(
            "Regenerate schedule?",
            isPresented: $showingRegenerateConfirm,
            titleVisibility: .visible
        ) {
            Button("Regenerate", role: .destructive) { regenerateSchedule() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Completed meetings will be kept. Incomplete meetings will be replaced with newly generated dates.")
        }
        .confirmationDialog(
            "Delete this session?",
            isPresented: $showingDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { deleteSession() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("All meetings in this session will be removed. The packet stays in your library.")
        }
    }

    private var header: some View {
        HStack {
            Text(titleText)
                .font(.headline)
                .lineLimit(1)
            Spacer()
            Button { onClose() } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var titleText: String {
        let trimmed = session.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        if let packet, !packet.title.isEmpty { return packet.title }
        return "Book Club"
    }

    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let packet, !packet.title.isEmpty {
                Label(packet.title, systemImage: "books.vertical")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else if session.packetID.isEmpty == false {
                Label("Packet missing", systemImage: "exclamationmark.triangle")
                    .font(.subheadline)
                    .foregroundStyle(.orange)
            }
            HStack(spacing: 12) {
                if let start = session.startDate {
                    Label(start.formatted(date: .abbreviated, time: .omitted), systemImage: "calendar")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Label(session.cadenceKind.displayName, systemImage: "repeat")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if session.rotateLeader {
                    Label("Rotating leader", systemImage: "arrow.triangle.2.circlepath.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var rosterStrip: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Roster")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            if roster.isEmpty {
                Text("No students yet — \(PlatformVerb.tapLowercased) Edit to add.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                FlowLayout(spacing: 6) {
                    ForEach(roster, id: \.objectID) { student in
                        Text(StudentFormatter.displayName(for: student))
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(Color.secondary.opacity(0.15)))
                    }
                }
            }
        }
    }

    private var statusPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Status")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Picker("Status", selection: Binding(
                get: { session.status },
                set: {
                    session.status = $0
                    session.modifiedAt = Date()
                    viewContext.safeSave()
                }
            )) {
                ForEach(BookClubSessionStatus.allCases) { status in
                    Text(status.displayName).tag(status)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
        }
    }

    private var scheduleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Schedule")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Spacer()
                Button {
                    showingRegenerateConfirm = true
                } label: {
                    Label("Regenerate", systemImage: "arrow.clockwise")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            if orderedMeetings.isEmpty {
                Text("No meetings scheduled yet.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 4) {
                    ForEach(orderedMeetings, id: \.objectID) { meeting in
                        BookClubMeetingRowView(
                            meeting: meeting,
                            leaderName: leaderName(for: meeting),
                            onToggleCompleted: { toggleCompleted(meeting) },
                            onReassignLeader: { leaderReassignTarget = meeting }
                        )
                        Divider()
                    }
                }
            }
        }
    }

    private var actionsSection: some View {
        HStack(spacing: 8) {
            Button {
                showingEditor = true
            } label: {
                Label("Edit", systemImage: "pencil")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            Button(role: .destructive) {
                showingDeleteConfirm = true
            } label: {
                Label("Delete", systemImage: "trash")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
    }

    private func leaderName(for meeting: CDBookClubMeeting) -> String? {
        guard let id = meeting.leaderStudentUUID,
              let student = roster.first(where: { $0.id == id }) else {
            return nil
        }
        return StudentFormatter.firstName(for: student)
    }

    private func toggleCompleted(_ meeting: CDBookClubMeeting) {
        meeting.markCompleted(!meeting.isCompleted)
        if meeting.isCompleted, session.status == .planned {
            session.status = .active
        }
        session.modifiedAt = Date()
        viewContext.safeSave()
    }

    private func regenerateSchedule() {
        guard let packet else { return }
        let cadence: BookClubCadence = {
            switch session.cadenceKind {
            case .weekly:
                let weekday = session.startDate.map { Calendar.current.component(.weekday, from: $0) } ?? 2
                return .weekly(weekday: weekday)
            case .biweekly:
                let weekday = session.startDate.map { Calendar.current.component(.weekday, from: $0) } ?? 2
                return .biweekly(weekday: weekday)
            case .custom:
                return .custom(weekdayMask: session.meetingWeekdayMask)
            }
        }()

        let completedMeetings = orderedMeetings.filter(\.isCompleted)
        let incompleteMeetings = orderedMeetings.filter { !$0.isCompleted }
        for meeting in incompleteMeetings {
            viewContext.delete(meeting)
        }

        let remainingReadingItems = Array(packet.readingItems.dropFirst(completedMeetings.count))
        let generated = BookClubScheduleGenerator.generate(
            startDate: session.startDate ?? Date(),
            cadence: cadence,
            readingItems: remainingReadingItems,
            roster: session.studentIDs,
            rotateLeader: session.rotateLeader
        )

        let baseOrdinal = completedMeetings.count
        for (offset, gen) in generated.enumerated() {
            let meeting = CDBookClubMeeting(context: viewContext)
            meeting.sessionID = session.id?.uuidString ?? ""
            meeting.session = session
            meeting.ordinal = Int32(baseOrdinal + offset + 1)
            meeting.date = gen.date
            meeting.readingLabel = gen.readingLabel
            meeting.leaderStudentID = gen.leaderStudentID?.uuidString ?? ""
        }

        if let lastDate = generated.last?.date {
            session.endDate = lastDate
        }
        session.modifiedAt = Date()
        viewContext.safeSave()
    }

    private func deleteSession() {
        viewContext.delete(session)
        viewContext.safeSave()
        onDelete()
    }
}

/// Sheet to reassign the leader of a single meeting.
private struct LeaderReassignSheet: View {
    let meeting: CDBookClubMeeting
    let roster: [CDStudent]
    let onSelect: (UUID?) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Assign leader for meeting \(meeting.ordinal)")
                .font(.headline)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    Button {
                        onSelect(nil)
                    } label: {
                        HStack {
                            Image(systemName: "circle.dashed")
                            Text("No leader")
                            Spacer()
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal, 10)
                        .background(meeting.leaderStudentID.isEmpty
                                    ? Color.accentColor.opacity(0.12)
                                    : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    ForEach(roster, id: \.objectID) { student in
                        Button {
                            onSelect(student.id)
                        } label: {
                            HStack {
                                Image(systemName: "person.fill")
                                    .foregroundStyle(.secondary)
                                Text(StudentFormatter.displayName(for: student))
                                Spacer()
                                if student.id?.uuidString == meeting.leaderStudentID {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                            .padding(.vertical, 6)
                            .padding(.horizontal, 10)
                            .background(student.id?.uuidString == meeting.leaderStudentID
                                        ? Color.accentColor.opacity(0.12)
                                        : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            Divider()
            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel)
            }
        }
        .padding(16)
    }
}
