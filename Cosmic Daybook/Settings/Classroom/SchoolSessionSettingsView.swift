import SwiftUI
import CoreData

/// The school session and the classroom's time zone, in the School year card
/// (domain-logic review R20 and A4). Both live on the shared settings row
/// (schema 25), so the Daybook Assistant reads them too. Only the lead guide
/// writes them, and only her own actions write: the days on Save, turning
/// them off at once, the zone as it is picked. Nothing is written because the
/// card opened or a change synced in.
struct SchoolSessionSettingsView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dependencies) private var dependencies

    /// What the share holds, as last read.
    @State private var stored = ClassroomCalendar.Snapshot()
    /// The days as shown: the stored session's, or a draft not saved yet.
    @State private var hasSession = false
    @State private var firstDay = Date()
    @State private var lastDay = Date()

    private var isGuide: Bool { CDClassroomMembership.currentRole(in: viewContext) == .leadGuide }

    /// The zone the class's days are in: the one set, else this device's.
    private var zone: TimeZone { stored.timeZoneID.flatMap(TimeZone.init(identifier:)) ?? .current }

    private var calendar: Calendar { AppCalendar.calendar(inZone: zone.identifier) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "calendar")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                Text("First and last days of school")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Toggle("Set the first and last days", isOn: Binding(
                get: { hasSession },
                set: { isOn in
                    hasSession = isOn
                    // Turning them off takes the session away at once; turning
                    // them on waits for Save, so no guessed days are written.
                    if !isOn, stored.session != nil { write(timeZoneID: stored.timeZoneID, session: nil) }
                }
            ))

            if hasSession {
                HStack(spacing: 12) {
                    DatePicker("First day", selection: $firstDay, displayedComponents: .date)
                    DatePicker("Last day", selection: $lastDay, displayedComponents: .date)
                    Button("Save", action: saveSession)
                        .buttonStyle(.borderedProminent)
                        .disabled(!hasUnsavedDays || datesAreOutOfOrder)
                }
                // The pickers show the class's days, also on a device set to another zone.
                .environment(\.timeZone, zone)
                .environment(\.calendar, calendar)
            }

            Text(sessionNote)
                .font(.footnote)
                .foregroundStyle(datesAreOutOfOrder ? Color.orange : Color.secondary)

            HStack(spacing: 8) {
                Text("Time zone")
                Menu(SchoolSessionCopy.zoneName(zone, isSet: stored.timeZoneID != nil)) {
                    Button("This device's: \(SchoolSessionCopy.zoneName(.current, isSet: true))") {
                        saveZone(TimeZone.current.identifier)
                    }
                    ForEach(SchoolSessionCopy.regions, id: \.name) { region in
                        Menu(region.name) {
                            ForEach(region.zoneIDs, id: \.self) { id in
                                Button(SchoolSessionCopy.cityName(id)) { saveZone(id) }
                            }
                        }
                    }
                }
                .fixedSize()
            }

            Text(
                "The class's days begin and end in this time zone on every device, so a phone "
                + "that is traveling still shows the class's day."
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .disabled(!isGuide)
        .task { reload() }
        // A change made on another of the guide's devices, arriving while this is open.
        .onReceive(NotificationCenter.default.publisher(for: .schoolDayDataDidChange)) { _ in reload() }
    }

    private var datesAreOutOfOrder: Bool {
        hasSession && calendar.startOfDay(for: lastDay) < calendar.startOfDay(for: firstDay)
    }

    /// The days shown, as a session; nil while they are out of order.
    private var draft: SchoolSession? {
        SchoolSession(firstDay: calendar.startOfDay(for: firstDay), lastDay: calendar.startOfDay(for: lastDay))
    }

    private var hasUnsavedDays: Bool { hasSession && draft != stored.session }

    private var sessionNote: String {
        if datesAreOutOfOrder { return "The last day is before the first day, so it can't be saved yet." }
        guard hasSession else {
            return "Without them, every weekday counts as a school day, also over the summer."
        }
        if hasUnsavedDays { return "Not saved yet. Choose Save to use these days." }
        return "The summer before the first day and after the last day counts as days off: "
            + "attendance, planning and reminders skip it, here and on your assistant's phone."
    }

    /// Reads the share again. Days being chosen and not yet saved are left
    /// alone; otherwise the card shows what the share holds.
    private func reload() {
        let wasEditing = hasUnsavedDays
        stored = AttendanceEmailLog.classroomCalendar(in: viewContext)
        guard !wasEditing else { return }
        hasSession = stored.session != nil
        if let session = stored.session {
            firstDay = session.firstDay
            lastDay = session.lastDay
        } else {
            let year = suggestedDays()
            firstDay = year.first
            lastDay = year.last
        }
    }

    /// The days the pickers open on before a session is set: this school
    /// year's start, and the following June 15.
    private func suggestedDays() -> (first: Date, last: Date) {
        let first = SchoolYear.currentStart(asOf: Date(), calendar: calendar, session: nil)
        let year = calendar.component(.year, from: first) + 1
        let last = calendar.date(from: DateComponents(year: year, month: 6, day: 15)) ?? first
        return (first, last)
    }

    private func saveSession() {
        guard hasSession, let draft else { return }
        // The first save from the Mac also says which zone those days are in.
        write(timeZoneID: stored.timeZoneID ?? AttendanceEmailLog.firstSaveZoneID, session: draft)
    }

    /// A new zone keeps the session's days: August 25 stays August 25.
    private func saveZone(_ id: String) {
        let session = stored.session.flatMap {
            SchoolSessionCopy.moved($0, from: calendar, to: AppCalendar.calendar(inZone: id))
        }
        write(timeZoneID: id, session: session)
    }

    private func write(timeZoneID: String?, session: SchoolSession?) {
        let changed = AttendanceEmailLog.saveClassroomCalendar(
            timeZoneID: timeZoneID, session: session,
            base: AttendanceEmail.storedSettings(),
            role: CDClassroomMembership.currentRole(in: viewContext), in: viewContext
        )
        guard changed else { return }
        dependencies.saveCoordinator.save(viewContext, reason: "Set the school session")
        stored = AttendanceEmailLog.classroomCalendar(in: viewContext)
        SchoolCalendarService.notifySchoolDayDataChanged()
    }
}

/// The wording and lists of the school session's controls.
nonisolated enum SchoolSessionCopy {

    struct Region: Equatable, Sendable {
        let name: String
        let zoneIDs: [String]
    }

    /// The system's time zones by the part of the world their names begin
    /// with ("America", "Europe"), each sorted by city.
    static let regions: [Region] = {
        let named = TimeZone.knownTimeZoneIdentifiers.filter { $0.contains("/") }
        let grouped = Dictionary(grouping: named) { String($0.prefix { $0 != "/" }) }
        return grouped.keys.sorted().map { key in
            Region(name: key, zoneIDs: (grouped[key] ?? []).sorted { cityName($0) < cityName($1) })
        }
    }()

    /// "New York" for "America/New_York"; "Indiana, Knox" for the three-part ones.
    static func cityName(_ identifier: String) -> String {
        identifier.split(separator: "/").dropFirst().joined(separator: ", ").replacingOccurrences(of: "_", with: " ")
    }

    /// "Eastern Time (New York)", and before one is set, that it is this
    /// device's for now.
    static func zoneName(_ zone: TimeZone, isSet: Bool, locale: Locale = .current) -> String {
        let name = zone.localizedName(for: .generic, locale: locale) ?? zone.identifier
        let city = cityName(zone.identifier)
        let full = city.isEmpty ? name : "\(name) (\(city))"
        return isSet ? full : "Not set: using this device's, \(full)"
    }

    /// `session` with the same calendar days in another zone.
    static func moved(_ session: SchoolSession, from old: Calendar, to new: Calendar) -> SchoolSession? {
        func day(_ date: Date) -> Date? {
            new.date(from: old.dateComponents([.year, .month, .day], from: date)).map { new.startOfDay(for: $0) }
        }
        return SchoolSession(firstDay: day(session.firstDay), lastDay: day(session.lastDay))
    }
}
