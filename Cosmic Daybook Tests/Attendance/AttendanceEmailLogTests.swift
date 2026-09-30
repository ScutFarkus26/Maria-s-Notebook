import Foundation
import CoreData
import Testing
@testable import CosmicDaybook

/// The front-desk attendance email's shared records (schema 12): who sent a
/// day's email, and the guide's settings the assistants write it from.
@Suite("Front-desk email log")
@MainActor
struct AttendanceEmailLogTests {

    private func day(_ iso: String) throws -> Date {
        try CoreDataTestHelpers.day(iso)
    }

    private static let guideSettings = AttendanceEmailLog.Settings(
        isEnabled: true,
        toAddresses: "office@school.org; nurse@school.org",
        nameOrder: .lastFirst,
        groupByLevel: true
    )

    // MARK: - Sends

    @Test("A day's newest send is the one shown; other days have none")
    func latestSendPerDay() throws {
        let ctx = try CoreDataTestHelpers.makeContext()
        let monday = try day("2026-10-12")
        #expect(AttendanceEmailLog.latestSend(on: monday, in: ctx) == nil)

        let first = monday.addingTimeInterval(8 * 3_600 + 40 * 60)
        let update = monday.addingTimeInterval(9 * 3_600 + 5 * 60)
        AttendanceEmailLog.recordSend(on: monday.addingTimeInterval(3_600), role: .assistant, now: first, in: ctx)
        AttendanceEmailLog.recordSend(
            on: monday, role: .leadGuide, confirmedByHand: true, now: update, in: ctx
        )
        #expect(CoreDataTestHelpers.save(ctx))

        let latest = try #require(AttendanceEmailLog.latestSend(on: monday, in: ctx))
        #expect(latest.sentAt == update)
        #expect(latest.sentBy == .leadGuide)
        #expect(latest.wasConfirmedByHand)
        #expect(AttendanceEmailLog.sends(on: monday, in: ctx).count == 2)
        #expect(AttendanceEmailLog.latestSend(on: try day("2026-10-13"), in: ctx) == nil)
    }

    @Test("Who sent it, as each viewer reads it")
    func senderNames() throws {
        let ctx = try CoreDataTestHelpers.makeContext()
        let monday = try day("2026-10-12")
        let record = AttendanceEmailLog.recordSend(on: monday, role: .assistant, in: ctx)
        record.sentByID = "_sarah"
        record.sentByName = "Sarah"
        let byAssistant = AttendanceEmailLog.Send(record)
        #expect(byAssistant.senderName(viewerRole: .leadGuide, myRecordName: "_guide", myName: nil) == "Sarah")
        #expect(byAssistant.senderName(viewerRole: .assistant, myRecordName: "_sarah", myName: "Sarah") == "you")
        #expect(byAssistant.senderName(viewerRole: .assistant, myRecordName: "_rivka", myName: "Rivka") == "Sarah")

        // No name and no id (the Sample Class): her own send is still hers.
        record.sentByID = nil
        record.sentByName = nil
        let anonymous = AttendanceEmailLog.Send(record)
        #expect(anonymous.senderName(viewerRole: .assistant, myRecordName: nil, myName: nil) == "you")
        #expect(anonymous.senderName(viewerRole: .leadGuide, myRecordName: nil, myName: nil) == "an assistant")
        record.sentByID = "_sarah"
        record.sentByName = "Sarah"

        record.sentBy = CDClassroomMembership.ClassroomRole.leadGuide.rawValue
        record.sentByID = "_guide"
        record.sentByName = nil
        let byGuide = AttendanceEmailLog.Send(record)
        #expect(byGuide.senderName(viewerRole: .leadGuide, myRecordName: nil, myName: nil) == "you")
        #expect(byGuide.senderName(viewerRole: .assistant, myRecordName: "_sarah", myName: "Sarah") == "your guide")
        #expect(
            byGuide.senderName(viewerRole: .assistant, myRecordName: "_sarah", myName: "Sarah", guideName: "Danny")
                == "Danny"
        )
    }

    @Test("The summary names the time, and the date when sent on another day")
    func summaries() throws {
        let ctx = try CoreDataTestHelpers.makeContext()
        let monday = try day("2026-10-12")
        let sameDay = monday.addingTimeInterval(8 * 3_600 + 42 * 60)
        let record = AttendanceEmailLog.recordSend(on: monday, role: .assistant, now: sameDay, in: ctx)
        let time = sameDay.formatted(date: .omitted, time: .shortened)
        #expect(AttendanceEmailLog.Send(record).summary(senderName: "Sarah", for: monday) == "Sent \(time) by Sarah")

        record.wasConfirmedByHand = true
        record.sentAt = try day("2026-10-13").addingTimeInterval(10 * 3_600)
        let summary = AttendanceEmailLog.Send(record).summary(senderName: "you", for: monday)
        #expect(summary.hasPrefix("Marked sent "))
        #expect(summary.hasSuffix(" by you"))
        #expect(summary.contains("13"), "another day's send carries its date: \(summary)")
    }

    // MARK: - Settings

    @Test("Only the lead guide writes the settings, and an unchanged write does nothing")
    func settingsWrites() throws {
        let ctx = try CoreDataTestHelpers.makeContext()
        #expect(AttendanceEmailLog.settings(in: ctx) == nil)
        #expect(!AttendanceEmailLog.saveSettings(Self.guideSettings, role: .assistant, in: ctx))
        #expect(AttendanceEmailLog.settings(in: ctx) == nil)

        #expect(AttendanceEmailLog.saveSettings(Self.guideSettings, role: .leadGuide, in: ctx))
        #expect(CoreDataTestHelpers.save(ctx))
        #expect(AttendanceEmailLog.settings(in: ctx) == Self.guideSettings)
        #expect(!AttendanceEmailLog.saveSettings(Self.guideSettings, role: .leadGuide, in: ctx), "unchanged")

        var changed = Self.guideSettings
        changed.toAddresses = "front@school.org"
        #expect(AttendanceEmailLog.saveSettings(changed, role: .leadGuide, in: ctx))
        #expect(CoreDataTestHelpers.save(ctx))
        #expect(AttendanceEmailLog.settings(in: ctx)?.recipients == ["front@school.org"])
        #expect(ctx.safeFetch(CDFetchRequest(CDAttendanceEmailSettings.self)).count == 1)
    }

    @Test("Two devices' rows collapse to the newest on the next write")
    func duplicateSettingsRowsCollapse() throws {
        let ctx = try CoreDataTestHelpers.makeContext()
        let older = CDAttendanceEmailSettings(context: ctx)
        older.toAddresses = "old@school.org"
        older.modifiedAt = try day("2026-10-01")
        let newer = CDAttendanceEmailSettings(context: ctx)
        newer.toAddresses = "office@school.org; nurse@school.org"
        newer.nameOrderRaw = AttendanceEmailNameOrder.lastFirst.rawValue
        newer.groupByLevel = true
        newer.modifiedAt = try day("2026-10-02")
        #expect(CoreDataTestHelpers.save(ctx))
        #expect(AttendanceEmailLog.settings(in: ctx) == Self.guideSettings, "the newest row wins")

        #expect(AttendanceEmailLog.saveSettings(Self.guideSettings, role: .leadGuide, in: ctx))
        #expect(CoreDataTestHelpers.save(ctx))
        #expect(ctx.safeFetch(CDFetchRequest(CDAttendanceEmailSettings.self)).count == 1)
    }

    @Test("Nothing to send without the switch on and an address")
    func canSend() {
        var settings = Self.guideSettings
        #expect(settings.canSend)
        settings.isEnabled = false
        #expect(!settings.canSend)
        settings.isEnabled = true
        settings.toAddresses = " ; "
        #expect(!settings.canSend)
    }

    @Test("An assistant's draft is written in the guide's format, to the guide's recipients")
    func draftFollowsTheGuide() throws {
        let monday = try day("2026-10-12")
        let maya = AttendanceEmailStudent(firstName: "Maya", lastName: "Stone", level: .upper)
        let eli = AttendanceEmailStudent(firstName: "Eli", lastName: "Park", level: .adolescent)
        let draft = Self.guideSettings.draft(for: monday, present: [maya], tardy: [], absent: [eli])

        #expect(draft.recipients == ["office@school.org", "nurse@school.org"])
        #expect(draft.subject == AttendanceEmailReport.makeSubject(for: monday))
        #expect(draft.body == AttendanceEmailReport.makeBody(
            present: [maya], tardy: [], absent: [eli], date: monday, nameOrder: .lastFirst, groupByLevel: true
        ))
        #expect(draft.body.contains("Stone, Maya"))
        #expect(draft.mailtoURL?.scheme == "mailto")
    }

    // MARK: - Deadline

    @Test("Today counts down from half an hour before the due time, then turns late")
    func urgencyAroundTheDeadline() throws {
        let monday = try day("2026-10-12")
        func at(_ hour: Int, _ minute: Int) -> Date {
            monday.addingTimeInterval(Double(hour * 3_600 + minute * 60))
        }
        let nine = at(9, 0)
        #expect(AttendanceEmailLog.urgency(for: monday, deadlineMinutes: 540, now: at(8, 29)) == .none)
        #expect(AttendanceEmailLog.urgency(for: monday, deadlineMinutes: 540, now: at(8, 30)) == .due(nine))
        #expect(AttendanceEmailLog.urgency(for: monday, deadlineMinutes: 540, now: at(8, 59)) == .due(nine))
        #expect(AttendanceEmailLog.urgency(for: monday, deadlineMinutes: 540, now: nine) == .overdue(nine))
        // Another day never counts down: yesterday's is sent or it isn't.
        let tuesdayMorning = try day("2026-10-13").addingTimeInterval(10 * 3_600)
        #expect(AttendanceEmailLog.urgency(for: monday, deadlineMinutes: 540, now: tuesdayMorning) == .none)
    }

    @Test("A send after the due time says it was late")
    func lateSummary() throws {
        let ctx = try CoreDataTestHelpers.makeContext()
        let monday = try day("2026-10-12")
        let early = AttendanceEmailLog.recordSend(
            on: monday, role: .assistant, now: monday.addingTimeInterval(8 * 3_600 + 50 * 60), in: ctx
        )
        let late = AttendanceEmailLog.recordSend(
            on: monday, role: .assistant, now: monday.addingTimeInterval(9 * 3_600 + 4 * 60), in: ctx
        )
        let onTime = AttendanceEmailLog.Send(early).summary(senderName: "Sarah", for: monday, deadlineMinutes: 540)
        let afterNine = AttendanceEmailLog.Send(late).summary(senderName: "Sarah", for: monday, deadlineMinutes: 540)
        #expect(!onTime.hasSuffix("(late)"))
        #expect(afterNine.hasSuffix(" by Sarah (late)"))
    }

    @Test("The guide's due time travels with the settings")
    func deadlineTravels() throws {
        let ctx = try CoreDataTestHelpers.makeContext()
        var settings = Self.guideSettings
        #expect(settings.deadlineMinutes == 540)
        settings.deadlineMinutes = 8 * 60 + 45
        #expect(AttendanceEmailLog.saveSettings(settings, role: .leadGuide, in: ctx))
        #expect(CoreDataTestHelpers.save(ctx))
        #expect(AttendanceEmailLog.settings(in: ctx)?.deadlineMinutes == 525)
    }

    // MARK: - Reminder

    @Test("The reminder skips today once the email has gone, and days off")
    func reminderDates() throws {
        let monday = try day("2026-10-12")
        let early = monday.addingTimeInterval(7 * 3_600)
        let tuesday = try day("2026-10-13")
        let dates = FrontDeskEmailReminder.fireDates(
            from: early, minutes: 9 * 60, nonSchoolDays: [tuesday], count: 3, todayIsDone: true
        )
        let days = dates.map { Calendar.current.startOfDay(for: $0) }
        #expect(!days.contains(monday))
        #expect(!days.contains(tuesday))
        #expect(days.count == 3)
        #expect(FrontDeskEmailReminder.isReminder("frontdesk-2026-10-14"))
        #expect(!FrontDeskEmailReminder.isReminder("arrival-2026-10-14"))
    }
}
