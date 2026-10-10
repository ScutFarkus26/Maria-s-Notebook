import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// Bug hunt 2026-10-10, Part 2 #76, #48 and #90's Parsha items: combined weeks
/// and their halves didn't see each other's lessons; the weeks between Rosh
/// Hashanah and Simchat Torah read "No weekly parsha"; Shabbat Parah and Rosh
/// Hashanah were mislabeled; the art-lesson picker filtered on a format that
/// doesn't exist; suggestions saw only the first 400 lessons by name.
@Suite("Parsha fixes (fix 10-10 J1)")
@MainActor
struct ParshaFix1010J1Tests {

    private func saturday(_ year: Int, _ month: Int, _ day: Int) throws -> Date {
        try #require(Calendar(identifier: .gregorian).date(from: DateComponents(year: year, month: month, day: day)))
    }

    // MARK: - Combined weeks

    @Test("A combined week shows lessons tagged on either half, and a half shows the combined week's")
    func combinedKeysMatchBothWays() throws {
        let context = try CoreDataTestHelpers.makeContext()
        for (name, key) in [
            ("Building the Mishkan", "vayakhel"),
            ("Counting the gold", "pekudei"),
            ("Both weeks together", "vayakhel-pekudei"),
            ("Skin and walls", "tazria"),
            ("The ark", "noach")
        ] {
            let lesson = CoreDataTestHelpers.seedLesson(in: context, name: name, area: "Parsha", sequence: "")
            lesson.parshaKey = key
        }
        #expect(CoreDataTestHelpers.save(context))

        func names(for key: String) -> Set<String> {
            let request = CDFetchRequest(CDLesson.self)
            request.predicate = HebrewParshaService.lessonsPredicate(forParshaKey: key)
            return Set(context.safeFetch(request).map(\.name))
        }

        #expect(names(for: "vayakhel-pekudei") == ["Building the Mishkan", "Counting the gold", "Both weeks together"])
        #expect(names(for: "vayakhel") == ["Building the Mishkan", "Both weeks together"])
        #expect(names(for: "pekudei") == ["Counting the gold", "Both weeks together"])
        #expect(names(for: "noach") == ["The ark"])
        #expect(HebrewParshaService.tag("vayakhel", matches: "vayakhel-pekudei"))
        #expect(!HebrewParshaService.tag("tazria", matches: "vayakhel-pekudei"))
        #expect(HebrewParshaService.lessonCount(
            forParshaKey: "matot-masei", countsByTag: ["matot": 2, "masei": 1, "matot-masei": 1, "noach": 5]
        ) == 4)
    }

    @Test("The parsha picker lists every combined week after its second half")
    func pickerListsCombinedKeys() throws {
        let keys = HebrewParshaService.pickerKeys
        #expect(keys.count == 54 + 7)
        for pair in HebrewParshaService.doubledPairs {
            let second = try #require(keys.firstIndex(of: pair.second))
            #expect(keys[second + 1] == pair.combined)
        }
        #expect(Set(keys).count == keys.count)
    }

    // MARK: - Between Rosh Hashanah and Simchat Torah

    @Test("Vayelech and Ha'azinu are read after Rosh Hashanah, as Hebcal lists them")
    func leftoverParshiotAfterRoshHashanah() throws {
        // 5786 began on a Tuesday after a year that read Nitzavim alone.
        #expect(HebrewParshaService.parshaKey(forShabbat: try saturday(2025, 9, 27)) == "vayelech")
        #expect(HebrewParshaService.parshaKey(forShabbat: try saturday(2025, 10, 4)) == "haazinu")
        // 5785 began on a Thursday: Ha'azinu on 3 Tishri, Yom Kippur the next Shabbat.
        #expect(HebrewParshaService.parshaKey(forShabbat: try saturday(2024, 10, 5)) == "haazinu")
        #expect(HebrewParshaService.parshaKey(forShabbat: try saturday(2024, 10, 12)) == nil)
        #expect(HebrewParshaService.displacingFestivalName(forShabbat: try saturday(2024, 10, 12)) == "Yom Kippur")
        // 5787 begins on a Shabbat: Rosh Hashanah, then Ha'azinu.
        #expect(HebrewParshaService.displacingFestivalName(forShabbat: try saturday(2026, 9, 12)) == "Rosh Hashanah")
        #expect(HebrewParshaService.parshaKey(forShabbat: try saturday(2026, 9, 19)) == "haazinu")
        // Sukkot still displaces the reading.
        #expect(HebrewParshaService.parshaKey(forShabbat: try saturday(2025, 10, 11)) == nil)
    }

    @Test("The year's calendar runs on to the last Shabbat before Simchat Torah")
    func yearWalkIncludesHaazinu() throws {
        let walk = HebrewParshaService.shabbatotForHebrewYear(containing: try saturday(2025, 3, 22))
        let calendar = Calendar(identifier: .gregorian)
        let haazinu = try #require(walk.first { calendar.isDate($0.date, inSameDayAs: try saturday(2025, 10, 4)) })
        #expect(haazinu.parshaKey == "haazinu")
        let last = try #require(walk.last)
        #expect(calendar.isDate(last.date, inSameDayAs: try saturday(2025, 10, 11)))
        #expect(last.festivalName == "Sukkot")
    }

    // MARK: - Special Shabbatot

    @Test("Shabbat Parah is the Shabbat before HaChodesh, even after a Friday or Thursday Purim")
    func parahFollowsHaChodesh() throws {
        // 5785: Purim on Friday, March 14, 2025.
        #expect(SpecialShabbatService.specialShabbat(forShabbat: try saturday(2025, 3, 15)) == nil)
        #expect(SpecialShabbatService.specialShabbat(forShabbat: try saturday(2025, 3, 22)) == .parah)
        #expect(SpecialShabbatService.specialShabbat(forShabbat: try saturday(2025, 3, 29)) == .hachodesh)
        // 5778: Pesach on Shabbat, March 31, 2018 (Purim on Thursday).
        #expect(SpecialShabbatService.specialShabbat(forShabbat: try saturday(2018, 3, 3)) == nil)
        #expect(SpecialShabbatService.specialShabbat(forShabbat: try saturday(2018, 3, 10)) == .parah)
        #expect(SpecialShabbatService.specialShabbat(forShabbat: try saturday(2018, 3, 17)) == .hachodesh)
        #expect(SpecialShabbatService.specialShabbat(forShabbat: try saturday(2018, 3, 24)) == .hagadol)
        // An ordinary year is unchanged.
        #expect(SpecialShabbatService.specialShabbat(forShabbat: try saturday(2026, 2, 28)) == .zachor)
        #expect(SpecialShabbatService.specialShabbat(forShabbat: try saturday(2026, 3, 7)) == .parah)
    }

    @Test("Rosh Hashanah on Shabbat isn't called Shabbat Rosh Chodesh")
    func roshHashanahIsNotRoshChodesh() throws {
        #expect(SpecialShabbatService.specialShabbat(forShabbat: try saturday(2026, 9, 12)) == nil)
        // The new-moon Shabbatot are otherwise unchanged (29 Tishri 5787, the eve of Rosh Chodesh).
        #expect(SpecialShabbatService.specialShabbat(forShabbat: try saturday(2026, 10, 10)) == .macharChodesh)
    }

    // MARK: - Art lessons and suggestions

    @Test("The art-lesson picker finds lessons in an art area, by whole word")
    func artLessonFilter() {
        #expect(ParshaLessonEditorSheet.isArtLesson(area: "Art", sequence: "Watercolor"))
        #expect(ParshaLessonEditorSheet.isArtLesson(area: "Arts & Crafts", sequence: ""))
        #expect(ParshaLessonEditorSheet.isArtLesson(area: "Practical Life", sequence: "Visual Art"))
        #expect(!ParshaLessonEditorSheet.isArtLesson(area: "Earth Science", sequence: "Parts of the Earth"))
        #expect(!ParshaLessonEditorSheet.isArtLesson(area: "Math", sequence: "Fractions"))
    }

    @Test("The library fingerprint is the same every time and changes when a lesson is renamed")
    func fingerprintIsStable() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let ark = CoreDataTestHelpers.seedLesson(in: context, name: "The Ark")
        let tower = CoreDataTestHelpers.seedLesson(in: context, name: "The Tower")
        let first = ParshaSuggestionService.libraryFingerprint([ark, tower])
        #expect(ParshaSuggestionService.libraryFingerprint([tower, ark]) == first)
        #expect(first.count == 64)
        tower.name = "The Tower of Babel"
        #expect(ParshaSuggestionService.libraryFingerprint([ark, tower]) != first)
    }

    @Test("A large library sends the lessons closest to the parsha, not the first 400 by name")
    func shortlistRanksByParsha() throws {
        let context = try CoreDataTestHelpers.makeContext()
        var lessons: [CDLesson] = []
        for index in 0..<450 {
            lessons.append(CoreDataTestHelpers.seedLesson(in: context, name: String(format: "Lesson %03d", index)))
        }
        let mishkan = CoreDataTestHelpers.seedLesson(in: context, name: "Zigzag: building a model Tabernacle")
        lessons.append(mishkan)

        let shortlist = ParshaSuggestionService.shortlist(
            lessons, matching: ["Vayakhel", "Construction of the Tabernacle"], limit: 400
        )
        #expect(shortlist.count == 400)
        #expect(shortlist.first === mishkan)
        let small = ParshaSuggestionService.shortlist(Array(lessons.prefix(10)), matching: ["Tabernacle"], limit: 400)
        #expect(small.count == 10)
    }
}
