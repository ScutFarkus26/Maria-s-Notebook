import CoreData

// The notebook's attendance reminder follows what arrives from iCloud: a send
// from the guide's other devices or an assistant's phone, the guide's settings,
// and days off. Without this the Mac and iPad rebuilt it only at launch, on
// the attendance screen, on a send made here and in Settings, so a day sent
// elsewhere could still ring here at 9:00. The Daybook Assistant has its own
// follower (`EarlyPickupReminderUpkeep`).

extension AppBootstrapper {

    /// The import observers, held for the life of the process.
    @MainActor private static var reminderImportObservers: [NSObjectProtocol] = []

    /// What `PersistentHistoryProcessor` reports for an import that can move
    /// the reminder: the day's sends, and the guide's way of sending, its
    /// deadline and its switch.
    nonisolated static let frontDeskReminderEntities: Set<String> = ["AttendanceEmailSend", "AttendanceEmailSettings"]

    /// Whether an import that touched `changed` (`changedEntityNamesKey`) can
    /// move the reminder.
    nonisolated static func importMovesFrontDeskReminder(_ changed: Set<String>) -> Bool {
        !changed.isDisjoint(with: frontDeskReminderEntities)
    }

    /// Rebuilds the reminder on `context` after each import that can move
    /// it, from now on. Once per process, never in unit tests. A burst of
    /// imports costs about one rebuild: `FrontDeskEmailReminder.runs` skips
    /// one still waiting when a newer one is asked for.
    @MainActor
    static func followFrontDeskReminderImports(in context: NSManagedObjectContext) {
        guard reminderImportObservers.isEmpty, !AppBootstrapping.isRunningUnitTests else { return }
        let center = NotificationCenter.default
        let key = PersistentHistoryProcessor.changedEntityNamesKey
        reminderImportObservers.append(center.addObserver(
            forName: .presentationDataDidChange, object: nil, queue: .main
        ) { note in
            guard let changed = note.userInfo?[key] as? Set<String>, importMovesFrontDeskReminder(changed) else {
                return
            }
            Task { @MainActor in await FrontDeskEmailReminder.reschedule(in: context) }
        })
        // A day off added or taken away.
        reminderImportObservers.append(center.addObserver(
            forName: .schoolDayDataDidChange, object: nil, queue: .main
        ) { _ in
            Task { @MainActor in await FrontDeskEmailReminder.reschedule(in: context) }
        })
    }
}
