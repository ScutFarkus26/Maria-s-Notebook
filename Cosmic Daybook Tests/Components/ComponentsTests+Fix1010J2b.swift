import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

// Bug hunt 2026-10-10, Part 2 #81 and #90: the debounced search field, toast
// hand-off, tag rename, OptionalDatePicker's hour, isoDateLocal's time zone and
// New Work's title.

@MainActor
private final class Collected {
    var values: [String] = []
}

@Suite("Debounced search field (Fix1010J2b)")
@MainActor
struct DebounceFix1010J2bTests {
    @Test("A keystroke that cancels the wait reports nothing; only the last value is reported")
    func cancelledWaitReportsNothing() async {
        let collected = Collected()
        let first = DebouncedSearchField.debounce("a", after: .milliseconds(50)) { collected.values.append($0) }
        first.cancel()
        let second = DebouncedSearchField.debounce("ab", after: .milliseconds(50)) { collected.values.append($0) }
        await first.value
        await second.value
        #expect(collected.values == ["ab"])
    }
}

@Suite("Toast hand-off (Fix1010J2b)")
@MainActor
struct ToastHandOffFix1010J2bTests {
    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<200 where !condition() {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test("A toast shown while the next one is on its way waits its turn")
    func toastDuringHandOffWaits() async throws {
        let service = ToastService(handOffDelay: .milliseconds(30))
        service.show("A")
        service.show("B")
        #expect(service.currentToast?.message == "A")

        service.dismiss()
        service.show("C")
        // Before the fix C showed in the gap and B pushed it out a moment later.
        #expect(service.currentToast == nil)

        await waitUntil { service.currentToast != nil }
        #expect(service.currentToast?.message == "B")
        #expect(service.queuedToasts.map(\.message) == ["C"])

        try await Task.sleep(for: .milliseconds(120))
        #expect(service.currentToast?.message == "B")
    }

    @Test("Dismissing twice shows the next toast once, not two in a row")
    func doubleDismissHandsOffOnce() async throws {
        let service = ToastService(handOffDelay: .milliseconds(30))
        service.show("A")
        service.show("B")
        service.show("C")

        service.dismiss()
        service.dismiss()

        await waitUntil { service.currentToast != nil }
        try await Task.sleep(for: .milliseconds(120))
        #expect(service.currentToast?.message == "B")
        #expect(service.queuedToasts.map(\.message) == ["C"])
    }
}

@Suite("Tag rename reaches every tagged row (Fix1010J2b)")
@MainActor
struct TagRenameFix1010J2bTests {
    @Test("Renaming a tag changes it on todos, todo templates and resources")
    func renameReachesTemplatesAndResources() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let old = TodoTagHelper.createTag(name: "Art", color: .blue)
        let new = TodoTagHelper.createTag(name: "Art Studio", color: .blue)
        let other = TodoTagHelper.createTag(name: "Office", color: .red)

        let todo = CDTodoItem(context: context)
        todo.tagsArray = [old, other]
        let template = CDTodoTemplate(context: context)
        template.tagsArray = [old]
        let resource = CDResource(context: context)
        resource.tagsArray = [other, old]
        let untouched = CDResource(context: context)
        untouched.tagsArray = [other]

        let changed = TagRename.rename(old, to: new, in: context)

        #expect(changed == 3)
        #expect(todo.tagsArray == [new, other])
        #expect(template.tagsArray == [new])
        #expect(resource.tagsArray == [other, new])
        #expect(untouched.tagsArray == [other])
    }

    @Test("Renaming onto a tag the row already has keeps it once")
    func renameOntoExistingTagKeepsOne() {
        let tags = TagRename.renamed("Art|blue", to: "Office|red", in: ["Art|blue", "Office|red", "Math|green"])
        #expect(tags == ["Office|red", "Math|green"])
    }
}

@Suite("Default hour on clock-change days (Fix1010J2b)")
struct OptionalDatePickerHourFix1010J2bTests {
    private func calendar() throws -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/New_York"))
        return calendar
    }

    @Test("9 AM is 9 AM on the Sundays the clocks change", arguments: [
        DateComponents(year: 2026, month: 3, day: 8),
        DateComponents(year: 2026, month: 11, day: 1)
    ])
    func nineStaysNine(day: DateComponents) throws {
        let calendar = try calendar()
        var noonParts = day
        noonParts.hour = 12
        let noon = try #require(calendar.date(from: noonParts))

        let date = OptionalDatePicker.defaultDate(on: noon, hour: 9, calendar: calendar)

        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        #expect(parts.year == day.year && parts.month == day.month && parts.day == day.day)
        #expect(parts.hour == 9)
        #expect(parts.minute == 0)
    }

    @Test("No hour means the start of the day")
    func noHourIsStartOfDay() throws {
        let calendar = try calendar()
        let noon = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 10, hour: 12)))
        #expect(OptionalDatePicker.defaultDate(on: noon, hour: nil, calendar: calendar)
            == calendar.startOfDay(for: noon))
    }
}

@Suite("Local day keys follow the time zone (Fix1010J2b)")
struct IsoDateLocalFix1010J2bTests {
    @Test("A day key uses the zone asked for, even after another zone was used")
    func followsZoneChange() throws {
        let instant = try #require(ISO8601DateFormatter().date(from: "2026-10-10T02:00:00Z"))
        let losAngeles = try #require(TimeZone(identifier: "America/Los_Angeles"))
        let tokyo = try #require(TimeZone(identifier: "Asia/Tokyo"))

        #expect(DateFormatters.isoDateLocal(in: losAngeles).string(from: instant) == "2026-10-09")
        #expect(DateFormatters.isoDateLocal(in: tokyo).string(from: instant) == "2026-10-10")
        #expect(DateFormatters.isoDateLocal(in: losAngeles).string(from: instant) == "2026-10-09")
    }

    @Test("The everyday formatter uses the device's current zone")
    func everydayUsesCurrentZone() {
        #expect(DateFormatters.isoDateLocal.timeZone.identifier == TimeZone.current.identifier)
    }
}

@Suite("New Work's title follows the lesson (Fix1010J2b)")
struct WorkTitleAutoFillFix1010J2bTests {
    @Test("An empty title takes the lesson's name")
    func emptyTakesLesson() {
        #expect(WorkTitleAutoFill.title(current: "", autoFilled: nil, suggested: "Stamp Game") == "Stamp Game")
    }

    @Test("A filled-in title follows a change of lesson")
    func autoFilledFollowsLesson() {
        #expect(WorkTitleAutoFill.title(current: "Stamp Game", autoFilled: "Stamp Game", suggested: "Bead Frame")
            == "Bead Frame")
    }

    @Test("A title she typed stays")
    func typedTitleStays() {
        #expect(WorkTitleAutoFill.title(current: "Maya's map", autoFilled: "Stamp Game", suggested: "Bead Frame")
            == nil)
        #expect(WorkTitleAutoFill.title(current: "Maya's map", autoFilled: nil, suggested: "Bead Frame") == nil)
    }
}
