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
    @Environment(\.dependencies) private var dependencies

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
    @State private var saveFailed: Bool = false

    private var selectedPacket: CDBookClubPacket? {
        guard let id = selectedPacketID else { return nil }
        return allPackets.first { $0.objectID == id }
    }

    private var rosterInOrder: [CDStudent] {
        let enrolled = dependencies.roster.enrolled
        return enrolled.filter { student in
            guard let id = student.id else { return false }
            return selectedStudentIDs.contains(id)
        }.sorted { lhs, rhs in
            StudentFormatter.firstName(for: lhs) < StudentFormatter.firstName(for: rhs)
        }
    }

    /// Members of the session being edited who have left the class. The roster
    /// lists enrolled children only, so they can't be seen or chosen there; they
    /// stay on the session (its history names them) but lead no new meeting.
    private var departedMembers: [CDStudent] {
        guard let editing = editingSession else { return [] }
        let enrolledIDs = Set(dependencies.roster.enrolled.compactMap(\.id))
        let departedIDs = editing.studentIDs.filter { !enrolledIDs.contains($0) }
        return departedIDs.compactMap { dependencies.roster.student(id: $0) }
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
                if editingSession == nil {
                    BookClubSchedulePreview(meetings: generatePreview(), roster: rosterInOrder)
                }
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
        .alert("Couldn't Save", isPresented: $saveFailed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("The book club couldn't be saved. Try again.")
        }
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
            let enrolled = dependencies.roster.enrolled
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
                            Text(student.shortName)
                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            if !departedMembers.isEmpty {
                Text("Also in this book club: \(departedMembers.map(\.shortName).joined(separator: ", ")) "
                     + "(left the class). They stay on the session but don't lead new meetings.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
                BookClubWeekdayPicker(weekdayMask: $customWeekdayMask)
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
            // The session's readings, numbered as its meetings are, with the
            // labels the meetings carry.
            let packetItems = allPackets.first { $0.id == editing.packetUUID }?.readingItems ?? []
            readingItems = BookClubSessionPlanner.readings(
                packetItems: packetItems, meetings: editing.orderedMeetings
            )
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
        if let editing = editingSession {
            saveEdits(to: editing)
        } else {
            createSession()
        }
        guard dependencies.saveCoordinator.save(
            viewContext, reason: editingSession == nil ? "Create book club session" : "Edit book club session",
            alertOnFailure: false
        ) else {
            saveFailed = true
            return
        }
        dismiss()
    }

    private func createSession() {
        let session = CDBookClubSession(context: viewContext)
        session.packetID = selectedPacket?.id?.uuidString ?? ""
        session.displayName = displayName
        session.startDate = startDate
        session.cadenceKind = cadenceKind
        session.meetingWeekdayMask = resolveStoredWeekdayMask()
        session.studentIDs = rosterInOrder.compactMap(\.id)
        session.rotateLeader = rotateLeader
        session.notes = notes
        session.status = .planned

        let generated = BookClubScheduleGenerator.generate(
            startDate: startDate,
            cadence: resolveCadence(),
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
    }

    /// Updates the session in place (`BookClubSessionPlanner.applyEdits`): held
    /// meetings stay as they are, and only the unheld ones follow a new schedule.
    private func saveEdits(to session: CDBookClubSession) {
        let draft = BookClubSessionPlanner.SessionEdits(
            displayName: displayName,
            startDate: startDate,
            cadenceKind: cadenceKind,
            weekdayMask: resolveStoredWeekdayMask(),
            cadence: resolveCadence(),
            roster: rosterInOrder.compactMap(\.id),
            departedMembers: departedMembers.compactMap(\.id),
            rotateLeader: rotateLeader,
            notes: notes,
            readings: readingItems
        )
        BookClubSessionPlanner.applyEdits(draft, to: session, today: Date(), calendar: calendar, context: viewContext)
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

    private static func nextMonday() -> Date {
        let calendar = AppCalendar.shared
        let now = Date()
        let weekday = calendar.component(.weekday, from: now)
        let delta = (2 - weekday + 7) % 7
        let target = delta == 0 ? 7 : delta
        return calendar.date(byAdding: .day, value: target, to: calendar.startOfDay(for: now)) ?? now
    }
}
