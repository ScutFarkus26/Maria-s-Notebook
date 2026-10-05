import Foundation
import CoreData
import Testing
@testable import Daybook_Assistant

// The small touches around the grid: birthdays, the greeting to the
// assistant, the sky, the day-off pictures, and "everyone's marked".
@Suite("Assistant delight")
@MainActor
struct AssistantDelightTests {

    typealias Model = AssistantAttendanceViewModel

    // MARK: - Birthdays

    @Test("A birthday shows on its day, not the day before or after")
    func birthdayOnItsDay() throws {
        let born = try AssistantTestSupport.day("2016-10-14")
        #expect(AttendanceBirthday.on(try AssistantTestSupport.day("2026-10-14"), birthday: born) == .birthday)
        #expect(AttendanceBirthday.on(try AssistantTestSupport.day("2026-10-13"), birthday: born) == nil)
        #expect(AttendanceBirthday.on(try AssistantTestSupport.day("2026-10-15"), birthday: born) == nil)
    }

    @Test("A summer birthday gets a half-birthday six months on, in the next year")
    func summerHalfBirthday() throws {
        let born = try AssistantTestSupport.day("2017-07-20")
        #expect(AttendanceBirthday.on(try AssistantTestSupport.day("2027-01-20"), birthday: born) == .halfBirthday)
        #expect(AttendanceBirthday.on(try AssistantTestSupport.day("2026-07-20"), birthday: born) == .birthday)
        // Not a summer birthday: no half.
        let spring = try AssistantTestSupport.day("2017-04-20")
        #expect(AttendanceBirthday.on(try AssistantTestSupport.day("2026-10-20"), birthday: spring) == nil)
    }

    @Test("Aug 31 has its half-birthday on the last day of February")
    func halfBirthdayClampsToFebruary() throws {
        let born = try AssistantTestSupport.day("2016-08-31")
        #expect(AttendanceBirthday.on(try AssistantTestSupport.day("2027-02-28"), birthday: born) == .halfBirthday)
    }

    @Test("Feb 29 is kept on Feb 28 in other years")
    func leapDay() throws {
        let born = try AssistantTestSupport.day("2016-02-29")
        #expect(AttendanceBirthday.on(try AssistantTestSupport.day("2027-02-28"), birthday: born) == .birthday)
        #expect(AttendanceBirthday.on(try AssistantTestSupport.day("2028-02-29"), birthday: born) == .birthday)
        #expect(AttendanceBirthday.on(try AssistantTestSupport.day("2028-02-28"), birthday: born) == nil)
    }

    @Test("A birthday never entered (the day the child was added) shows no cake")
    func placeholderBirthdayIgnored() throws {
        // CDStudent stamps Date() as the birthday: a year later that's a
        // one-year-old, who can't be in the class.
        let added = try AssistantTestSupport.day("2025-09-29")
        #expect(AttendanceBirthday.on(try AssistantTestSupport.day("2026-09-29"), birthday: added) == nil)
        #expect(AttendanceBirthday.on(try AssistantTestSupport.day("2026-09-29"), birthday: nil) == nil)
    }

    @Test("A row carries its child's birthday on the day loaded")
    func rowCarriesBirthday() throws {
        let stack = try AssistantTestSupport.makeStack()
        let context = stack.viewContext
        let day = try AssistantTestSupport.day("2026-10-14")
        let maya = AssistantTestSupport.student("Maya", "Stone", in: context)
        maya.birthday = try AssistantTestSupport.day("2016-10-14")
        let ari = AssistantTestSupport.student("Ari", "Cedar", in: context)
        ari.birthday = try AssistantTestSupport.day("2016-03-02")

        #expect(Model.Row(student: maya, record: nil, shortName: "Maya", day: day).birthday == .birthday)
        #expect(Model.Row(student: ari, record: nil, shortName: "Ari", day: day).birthday == nil)
    }

    // MARK: - Sky

    @Test("The sky holds at the ends of the day and blends between")
    func sky() throws {
        let day = try AssistantTestSupport.day("2026-09-29")
        let calendar = Calendar.current
        func at(_ hour: Int, _ minute: Int = 0) throws -> Date {
            try #require(calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day))
        }
        #expect(AssistantSky.tint(at: try at(4)) == AssistantSky.dawn)
        #expect(AssistantSky.tint(at: try at(7, 30)) == AssistantSky.sunrise)
        #expect(AssistantSky.tint(at: try at(22)) == AssistantSky.dusk)
        let between = AssistantSky.tint(at: try at(8, 45))
        #expect(between != AssistantSky.sunrise && between != AssistantSky.morning)
        #expect(between == AssistantSky.sunrise.mixed(with: AssistantSky.morning, by: 0.5))
    }

    // MARK: - Days off

    @Test("A day off gets a picture for its kind and a title")
    func dayOffArt() {
        #expect(AssistantDayOffArt.art(for: .weekend).symbol == "sun.max.fill")
        #expect(AssistantDayOffArt.art(for: .holiday("Winter Break")).symbol == "snowflake")
        #expect(AssistantDayOffArt.art(for: .holiday("Sukkot")).symbol == "leaf.fill")
        #expect(AssistantDayOffArt.art(for: .holiday("Parent Conferences")).symbol == "books.vertical.fill")
        #expect(AssistantDayOffArt.art(for: .holiday("Founders' Day")).symbol == "party.popper.fill")
        #expect(AssistantDayOffArt.art(for: .holiday(nil)).title == "Day Off")
        #expect(AssistantDayOffArt.art(for: .holiday("Sukkot")).title == "Sukkot")
    }

    @Test("Today's day off speaks to the assistant; another day's doesn't")
    func dayOffMessage() {
        #expect(AssistantDayOffArt.message(for: .weekend, isToday: true, name: "Rivka Cohen")
            .hasPrefix("Enjoy the weekend, Rivka."))
        #expect(AssistantDayOffArt.message(for: .holiday("Sukkot"), isToday: true, name: nil)
            .hasPrefix("Enjoy the day off."))
        #expect(!AssistantDayOffArt.message(for: .weekend, isToday: false, name: "Rivka").contains("Rivka"))
    }

    // MARK: - Everyone marked

    @Test("Opening the screen is no completion: only a real increase buzzes, ripples and rings")
    func completionTrigger() {
        typealias Model = AssistantAttendanceViewModel
        // The screen's model arriving at launch.
        #expect(!Model.isCompletion(from: nil, to: 0))
        #expect(!Model.isCompletion(from: nil, to: 3))
        #expect(!Model.isCompletion(from: 1, to: nil))
        #expect(!Model.isCompletion(from: 2, to: 2))
        #expect(Model.isCompletion(from: 0, to: 1))
        #expect(Model.isCompletion(from: 1, to: 2))
    }

    @Test("The last unmarked child marked counts one completion; clearing and re-marking counts again")
    func completions() throws {
        let stack = try AssistantTestSupport.makeStack()
        let context = stack.viewContext
        AssistantTestSupport.student("Ari", "Cedar", in: context)
        AssistantTestSupport.student("Maya", "Stone", in: context)
        try context.save()
        let model = AssistantTestSupport.viewModel(stack)
        try #require(model.rows.count == 2)

        model.tap(model.rows[0])
        #expect(model.completions == 0)
        model.tap(model.rows[1])
        #expect(model.completions == 1)

        // A change with no one unmarked before it isn't a completion.
        model.markAbsent(reason: .none, for: model.rows[1])
        #expect(model.completions == 1)

        model.setStatus(.unmarked, for: model.rows[0])
        model.tap(model.rows[0])
        #expect(model.completions == 2)
    }

    @Test("Closing arrival counts as everyone marked")
    func closingArrivalCompletes() throws {
        let stack = try AssistantTestSupport.makeStack()
        let context = stack.viewContext
        AssistantTestSupport.student("Ari", "Cedar", in: context)
        AssistantTestSupport.student("Maya", "Stone", in: context)
        try context.save()
        let model = AssistantTestSupport.viewModel(stack)

        model.tap(model.rows[0])
        model.beginLate()
        #expect(model.completions == 1)
    }

    @Test("A day ahead never completes: marking everyone away isn't a morning")
    func futureNeverCompletes() throws {
        let stack = try AssistantTestSupport.makeStack()
        let context = stack.viewContext
        AssistantTestSupport.student("Ari", "Cedar", in: context)
        try context.save()
        let ahead = try #require(Calendar.current.date(byAdding: .day, value: 7, to: Date()))
        let model = AssistantTestSupport.viewModel(stack, on: ahead)

        model.markAbsent(reason: .vacation, for: model.rows[0])
        #expect(model.completions == 0)
    }

    @Test("Everyone's here, with the time today; otherwise how many are home")
    func completionText() throws {
        let stack = try AssistantTestSupport.makeStack()
        let context = stack.viewContext
        AssistantTestSupport.student("Ari", "Cedar", in: context)
        AssistantTestSupport.student("Maya", "Stone", in: context)
        try context.save()
        let model = AssistantTestSupport.viewModel(stack)
        model.tap(model.rows[0])
        model.tap(model.rows[1])
        let eight = try #require(Calendar.current.date(bySettingHour: 8, minute: 14, second: 0, of: Date()))

        let here = "Everyone's here · \(AttendanceClock.string(eight))"
        #expect(Model.completionText(model.rows, at: eight) == here)
        #expect(Model.completionText(model.rows, at: nil) == "Everyone's here")
        #expect(Model.completionText(model.rows, at: nil, milestone: .hundredthDay) == "Everyone's here for day 100")

        model.markAbsent(reason: .none, for: model.rows[1])
        #expect(Model.completionText(model.rows, at: eight) == "All marked · 1 here, 1 home")

        // Leaving early takes a child out of here and sends them home.
        model.setStatus(.leftEarly, for: model.rows[0])
        #expect(Model.completionText(model.rows, at: eight) == "All marked · 0 here, 2 home")
    }

    // MARK: - Bells

    @Test("The bells are the C major scale from middle C")
    func bellScale() {
        #expect(AttendanceBells.scale.count == 8)
        #expect(abs(AttendanceBells.scale[0] - 261.63) < 0.01)
        #expect(abs(AttendanceBells.scale[7] - 2 * AttendanceBells.scale[0]) < 0.05)
    }

    @Test("Bells climb the scale as the class fills, come back down, and never jump")
    func bellNotes() {
        let notes = (1...30).map(AttendanceBells.note(forHereCount:))
        #expect(notes[0] == AttendanceBells.scale[0])
        #expect(notes[7] == AttendanceBells.scale[7])
        #expect(notes[8] == AttendanceBells.scale[6])
        // Around again after C D E F G A B C′ B A G F E D.
        #expect(notes[14] == AttendanceBells.scale[0])
        // Every step is to a neighboring bell.
        for (earlier, later) in zip(notes, notes.dropFirst()) {
            let from = AttendanceBells.scale.firstIndex(of: earlier) ?? -10
            let to = AttendanceBells.scale.firstIndex(of: later) ?? 10
            #expect(abs(from - to) == 1)
        }
    }

    @Test("Children who ring the same bell share one tune: eight bells, not one per child")
    func bellTunesByNote() {
        let tunes = Set((1...30).map { AttendanceBells.tune(for: .here(count: $0)) })
        #expect(tunes.count == AttendanceBells.scale.count)
        #expect(AttendanceBells.tune(for: .here(count: 1)) == AttendanceBells.tune(for: .here(count: 15)))
        #expect(AttendanceBells.tune(for: .here(count: 1)) != AttendanceBells.tune(for: .here(count: 2)))
        #expect(AttendanceBells.Tune.allCases.count == 11)
    }

    @Test("Every tune is built away from the main actor, ringing out and never clipping")
    func bellTunesRendered() async {
        let rate = 8_000.0
        let rendered = await AttendanceBells.renderAll(sampleRate: rate)
        #expect(Set(rendered.keys) == Set(AttendanceBells.Tune.allCases))
        for (tune, samples) in rendered {
            #expect(samples.count >= Int(2.2 * rate), "\(tune) is too short")
            #expect(samples.allSatisfy { abs($0) <= 0.9001 }, "\(tune) clips")
            #expect(samples.contains { abs($0) > 0.01 }, "\(tune) is silent")
        }
    }
}
