import SwiftUI
import CoreData
import OSLog

/// Sheet for creating a new session or editing an existing one.
/// - When `editingSession` is non-nil, edits that session in place.
/// - Otherwise creates a new session; can be prefilled with a packet.
struct BookClubSessionEditorSheet: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.calendar) private var calendar

    let prefilledPacket: CDBookClubPacket?
    let editingSession: CDBookClubSession?

    init(prefilledPacket: CDBookClubPacket? = nil, editingSession: CDBookClubSession? = nil) {
        self.prefilledPacket = prefilledPacket
        self.editingSession = editingSession
    }

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \CDBookClubPacket.title, ascending: true)]
    )
    private var allPackets: FetchedResults<CDBookClubPacket>

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \CDStudent.firstName, ascending: true)]
    )
    private var allStudents: FetchedResults<CDStudent>

    @State private var selectedPacketID: NSManagedObjectID?
    @State private var displayName: String = ""
    @State private var selectedStudentIDs: Set<UUID> = []
    @State private var startDate: Date = nextMonday()
    @State private var cadenceKind: BookClubCadenceKind = .weekly
    @State private var weekday: Int = 2 // Monday
    @State private var customWeekdayMask: Int64 = 0
    @State private var rotateLeader: Bool = true
    @State private var notes: String = ""
    @State private var readingItems: [BookClubReadingItem] = []
    @State private var didInitialize: Bool = false

    nonisolated private static let logger = Logger.bookClub

    private var selectedPacket: CDBookClubPacket? {
        guard let id = selectedPacketID else { return nil }
        return allPackets.first { $0.objectID == id }
    }

    private var rosterInOrder: [CDStudent] {
        let enrolled = Array(allStudents).filterEnrolled()
        return enrolled.filter { student in
            guard let id = student.id else { return false }
            return selectedStudentIDs.contains(id)
        }.sorted { lhs, rhs in
            StudentFormatter.firstName(for: lhs) < StudentFormatter.firstName(for: rhs)
        }
    }

    private var canSave: Bool {
        selectedPacketID != nil && !readingItems.isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                packetSection
                rosterSection
                scheduleSection
                readingItemsSection
                preview
                notesSection
            }
            .formStyle(.grouped)
            .navigationTitle(editingSession == nil ? "New Book Club" : "Edit Session")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(editingSession == nil ? "Create" : "Save", action: save)
                        .disabled(!canSave)
                }
            }
        }
        .onAppear(perform: initializeIfNeeded)
        .onChange(of: selectedPacketID) { _, _ in
            if editingSession == nil, let packet = selectedPacket {
                readingItems = packet.readingItems
            }
        }
    }

    private var packetSection: some View {
        Section("Packet") {
            if editingSession != nil {
                // Packet can't be changed for an existing session.
                if let packet = selectedPacket {
                    Label(packet.displayTitle, systemImage: "books.vertical")
                } else {
                    Label("Packet missing", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
            } else {
                Picker("Packet", selection: $selectedPacketID) {
                    Text("Choose…").tag(NSManagedObjectID?.none)
                    ForEach(Array(allPackets), id: \.objectID) { packet in
                        Text(packet.displayTitle).tag(NSManagedObjectID?.some(packet.objectID))
                    }
                }
            }
            TextField("Display name (optional)", text: $displayName)
        }
    }

    private var rosterSection: some View {
        Section("Roster") {
            let enrolled = Array(allStudents).filterEnrolled()
            if enrolled.isEmpty {
                Text("No enrolled students.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(enrolled.sorted { $0.firstName < $1.firstName }, id: \.objectID) { student in
                    let isSelected = student.id.map { selectedStudentIDs.contains($0) } ?? false
                    Button {
                        toggleStudent(student)
                    } label: {
                        HStack {
                            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                            Text(StudentFormatter.displayName(for: student))
                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            Toggle("Rotate discussion leader through roster", isOn: $rotateLeader)
        }
    }

    private var scheduleSection: some View {
        Section("Schedule") {
            DatePicker("First meeting", selection: $startDate, displayedComponents: .date)
                .onChange(of: startDate) { _, newValue in
                    if cadenceKind != .custom {
                        weekday = calendar.component(.weekday, from: newValue)
                    }
                }
            Picker("Cadence", selection: $cadenceKind) {
                ForEach(BookClubCadenceKind.allCases) { kind in
                    Text(kind.displayName).tag(kind)
                }
            }

            if cadenceKind == .custom {
                weekdaySelector
            }
        }
    }

    private var weekdaySelector: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Meeting days")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                ForEach(1...7, id: \.self) { day in
                    let isOn = isWeekdaySet(day)
                    Button {
                        toggleWeekday(day)
                    } label: {
                        Text(weekdayShortLabel(day))
                            .font(.caption)
                            .frame(width: 32, height: 28)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(isOn ? Color.accentColor : Color.secondary.opacity(0.15))
                            )
                            .foregroundStyle(isOn ? Color.white : Color.primary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var readingItemsSection: some View {
        Section("Reading items") {
            if readingItems.isEmpty {
                Text("Add reading items to the packet first.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(readingItems) { item in
                    HStack {
                        Text("\(item.ordinal).")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                        TextField("Label", text: Binding(
                            get: { item.label },
                            set: { newValue in
                                if let idx = readingItems.firstIndex(where: { $0.id == item.id }) {
                                    readingItems[idx].label = newValue
                                }
                            }
                        ))
                    }
                }
            }
        }
    }

    private var preview: some View {
        Section("Preview") {
            let generated = generatePreview()
            if generated.isEmpty {
                Text("Choose a packet with reading items to preview.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(generated.enumerated()), id: \.offset) { _, meeting in
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text("Meeting \(meeting.ordinal)")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Text(meeting.date, style: .date)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Text(meeting.readingLabel)
                                .font(.callout)
                        }
                        Spacer()
                        if let leaderID = meeting.leaderStudentID,
                           let leader = rosterInOrder.first(where: { $0.id == leaderID }) {
                            Text(StudentFormatter.firstName(for: leader))
                                .font(.caption)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.secondary.opacity(0.15)))
                        }
                    }
                }
            }
        }
    }

    private var notesSection: some View {
        Section("Notes") {
            TextEditor(text: $notes)
                .frame(minHeight: 60)
        }
    }

    // MARK: - Logic

    private func initializeIfNeeded() {
        guard !didInitialize else { return }
        didInitialize = true

        if let editing = editingSession {
            // Editing existing session.
            selectedPacketID = allPackets.first { $0.id == editing.packetUUID }?.objectID
            displayName = editing.displayName
            selectedStudentIDs = Set(editing.studentIDs)
            startDate = editing.startDate ?? Date()
            cadenceKind = editing.cadenceKind
            customWeekdayMask = editing.meetingWeekdayMask
            rotateLeader = editing.rotateLeader
            notes = editing.notes
            if let editingDate = editing.startDate {
                weekday = calendar.component(.weekday, from: editingDate)
            }
            // Use the meetings' current reading labels for editing.
            readingItems = editing.orderedMeetings.enumerated().map { offset, meeting in
                BookClubReadingItem(ordinal: offset + 1, label: meeting.readingLabel)
            }
        } else if let prefilled = prefilledPacket {
            selectedPacketID = prefilled.objectID
            readingItems = prefilled.readingItems
            weekday = calendar.component(.weekday, from: startDate)
        } else {
            weekday = calendar.component(.weekday, from: startDate)
        }
    }

    private func generatePreview() -> [BookClubScheduleGenerator.GeneratedMeeting] {
        guard !readingItems.isEmpty else { return [] }
        let cadence = resolveCadence()
        let roster = rosterInOrder.compactMap(\.id)
        return BookClubScheduleGenerator.generate(
            startDate: startDate,
            cadence: cadence,
            readingItems: readingItems,
            roster: roster,
            rotateLeader: rotateLeader
        )
    }

    private func resolveCadence() -> BookClubCadence {
        switch cadenceKind {
        case .weekly: return .weekly(weekday: weekday)
        case .biweekly: return .biweekly(weekday: weekday)
        case .custom:
            let mask = customWeekdayMask == 0 ? (Int64(1) << weekday) : customWeekdayMask
            return .custom(weekdayMask: mask)
        }
    }

    private func save() {
        let session: CDBookClubSession
        if let editing = editingSession {
            session = editing
            for meeting in editing.orderedMeetings {
                viewContext.delete(meeting)
            }
        } else {
            session = CDBookClubSession(context: viewContext)
        }

        session.packetID = selectedPacket?.id?.uuidString ?? ""
        session.displayName = displayName
        session.startDate = startDate
        session.cadenceKind = cadenceKind
        session.meetingWeekdayMask = resolveStoredWeekdayMask()
        session.studentIDs = rosterInOrder.compactMap(\.id)
        session.rotateLeader = rotateLeader
        session.notes = notes
        if editingSession == nil {
            session.status = .planned
        }

        let cadence = resolveCadence()
        let generated = BookClubScheduleGenerator.generate(
            startDate: startDate,
            cadence: cadence,
            readingItems: readingItems,
            roster: rosterInOrder.compactMap(\.id),
            rotateLeader: rotateLeader
        )

        for gen in generated {
            let meeting = CDBookClubMeeting(context: viewContext)
            meeting.sessionID = session.id?.uuidString ?? ""
            meeting.session = session
            meeting.ordinal = Int32(gen.ordinal)
            meeting.date = gen.date
            meeting.readingLabel = gen.readingLabel
            meeting.leaderStudentID = gen.leaderStudentID?.uuidString ?? ""
        }

        if let lastDate = generated.last?.date {
            session.endDate = lastDate
        }
        session.modifiedAt = Date()
        viewContext.safeSave()
        dismiss()
    }

    private func resolveStoredWeekdayMask() -> Int64 {
        switch cadenceKind {
        case .weekly, .biweekly:
            return Int64(1) << weekday
        case .custom:
            return customWeekdayMask == 0 ? (Int64(1) << weekday) : customWeekdayMask
        }
    }

    private func toggleStudent(_ student: CDStudent) {
        guard let id = student.id else { return }
        if selectedStudentIDs.contains(id) {
            selectedStudentIDs.remove(id)
        } else {
            selectedStudentIDs.insert(id)
        }
    }

    private func isWeekdaySet(_ day: Int) -> Bool {
        (customWeekdayMask & (Int64(1) << day)) != 0
    }

    private func toggleWeekday(_ day: Int) {
        customWeekdayMask ^= (Int64(1) << day)
    }

    private func weekdayShortLabel(_ day: Int) -> String {
        switch day {
        case 1: return "Sun"
        case 2: return "Mon"
        case 3: return "Tue"
        case 4: return "Wed"
        case 5: return "Thu"
        case 6: return "Fri"
        case 7: return "Sat"
        default: return ""
        }
    }

    private static func nextMonday() -> Date {
        let calendar = AppCalendar.shared
        let now = Date()
        let weekday = calendar.component(.weekday, from: now)
        let delta = (2 - weekday + 7) % 7
        let target = delta == 0 ? 7 : delta
        return calendar.date(byAdding: .day, value: target, to: calendar.startOfDay(for: now)) ?? now
    }
}
