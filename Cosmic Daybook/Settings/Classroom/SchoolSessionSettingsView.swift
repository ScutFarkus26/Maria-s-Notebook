import SwiftUI
import CoreData

/// The school session and the classroom's time zone, in the School year card
/// (domain-logic review R20 and A4). Both live on the shared settings row
/// (schema 25), so the Daybook Assistant reads them too. Only the lead guide
/// writes them, and only her own actions write: the days on Save, turning
/// them off at once, the zone as it is picked. Nothing is written because the
/// card opened or a change synced in, and nothing else sets the zone: until
/// it is picked, each device follows its own (cold review 2026-11-21).
struct SchoolSessionSettingsView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dependencies) private var dependencies

    /// What the share holds, as last read.
    @State private var stored = ClassroomCalendar.Snapshot()
    /// The days as shown: the stored session's, or a draft not saved yet.
    @State private var hasSession = false
    @State private var firstDay = Date()
    @State private var lastDay = Date()
    /// A picked zone that would move the days already saved, waiting for the
    /// guide to say so.
    @State private var pendingZone: PendingZoneChange?

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
                        pickZone(TimeZone.current.identifier)
                    }
                    ForEach(SchoolSessionCopy.regions, id: \.name) { region in
                        Menu(region.name) {
                            ForEach(region.zoneIDs, id: \.self) { id in
                                Button(SchoolSessionCopy.cityName(id)) { pickZone(id) }
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
        .alert(
            "Change the time zone?",
            isPresented: Binding(get: { pendingZone != nil }, set: { if !$0 { pendingZone = nil } }),
            presenting: pendingZone
        ) { change in
            Button("Change Time Zone") { saveZone(change.zoneID) }
            Button("Cancel", role: .cancel) {}
        } message: { change in
            Text(change.message)
        }
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
        // The zone stays as it is: unset, the days follow each device's own.
        write(timeZoneID: stored.timeZoneID, session: draft)
    }

    /// A zone picked from the menu: saved at once, unless the days already
    /// saved would show on another day in it; then the guide is asked first.
    private func pickZone(_ id: String) {
        guard id != stored.timeZoneID, let picked = TimeZone(identifier: id) else { return }
        let message = SchoolSessionCopy.zoneChangeWarning(
            from: zone, to: picked, savedDays: SchoolSessionCopy.savedDaySpan(in: viewContext)
        )
        if let message {
            pendingZone = PendingZoneChange(zoneID: id, message: message)
        } else {
            saveZone(id)
        }
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

/// A zone the guide picked, and what it would do to the days already saved.
private struct PendingZoneChange {
    let zoneID: String
    let message: String
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

    /// What moving the class from `old` to `new` would do to the days
    /// already saved, or nil when it does nothing to them. Days are saved at
    /// the midnight of the zone they were made in, and read as the day that
    /// holds that moment: in a zone to the west, that is the evening before.
    /// Every day in `savedDays` is checked, since two zones' clocks may
    /// change on different dates (Phoenix and Los Angeles differ only in
    /// winter).
    static func zoneChangeWarning(
        from old: TimeZone, to new: TimeZone, savedDays: ClosedRange<Date>?, locale: Locale = .current
    ) -> String? {
        guard let savedDays, old.identifier != new.identifier else { return nil }
        let oldCalendar = AppCalendar.calendar(inZone: old.identifier)
        let newCalendar = AppCalendar.calendar(inZone: new.identifier)
        var day = oldCalendar.startOfDay(for: savedDays.lowerBound)
        let last = oldCalendar.startOfDay(for: savedDays.upperBound)
        while day <= last {
            let was = oldCalendar.dateComponents([.year, .month, .day], from: day)
            let becomes = newCalendar.dateComponents([.year, .month, .day], from: day)
            if was != becomes {
                let isEarlier = (becomes.year ?? 0, becomes.month ?? 0, becomes.day ?? 0)
                    < (was.year ?? 0, was.month ?? 0, was.day ?? 0)
                return "Attendance and days off already in the notebook were saved in "
                    + "\(zoneName(old, isSet: true, locale: locale)). "
                    + "In \(zoneName(new, isSet: true, locale: locale)) "
                    + "they would show a day \(isEarlier ? "earlier" : "later"), on every device."
            }
            let next = AppCalendar.dayStart(after: day, calendar: oldCalendar)
            guard next > day else { break }
            day = next
        }
        return nil
    }

    /// The first and last days anything is saved on by its day: attendance,
    /// days off, school-day changes, locked days and sends to the school.
    /// Nil when there is none.
    @MainActor
    static func savedDaySpan(in context: NSManagedObjectContext) -> ClosedRange<Date>? {
        func edge<T: NSManagedObject>(_ type: T.Type, first: Bool) -> Date? {
            let request = CDFetchRequest(T.self)
            request.predicate = NSPredicate(format: "date != nil")
            request.sortDescriptors = [NSSortDescriptor(key: "date", ascending: first)]
            request.fetchLimit = 1
            return context.safeFetchFirst(request)?.value(forKey: "date") as? Date
        }
        func edges<T: NSManagedObject>(_ type: T.Type) -> [Date] {
            [edge(type, first: true), edge(type, first: false)].compactMap { $0 }
        }
        let dates = edges(CDAttendanceRecord.self) + edges(CDNonSchoolDay.self)
            + edges(CDSchoolDayOverride.self) + edges(CDAttendanceDayLock.self)
            + edges(CDAttendanceEmailSend.self)
        guard let first = dates.min(), let last = dates.max() else { return nil }
        return first...last
    }

    /// `session` with the same calendar days in another zone.
    static func moved(_ session: SchoolSession, from old: Calendar, to new: Calendar) -> SchoolSession? {
        func day(_ date: Date) -> Date? {
            new.date(from: old.dateComponents([.year, .month, .day], from: date)).map { new.startOfDay(for: $0) }
        }
        return SchoolSession(firstDay: day(session.firstDay), lastDay: day(session.lastDay))
    }
}
