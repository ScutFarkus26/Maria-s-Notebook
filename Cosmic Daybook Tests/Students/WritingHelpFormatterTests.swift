import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// The writing-help sheet shows the gathered notes to the guide, so the text
/// reads as notes, not as a data export: a one-line header and plain labels.
@Suite("Writing help note formatter")
@MainActor
struct WritingHelpFormatterTests {

    @Test("The header counts the notes and gives their dates")
    func headerAndLabels() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let first = CoreDataTestHelpers.seedNote(in: context, body: "Counted to 100 with the bead chain.")
        first.updatedAt = try CoreDataTestHelpers.day("2026-09-02")
        let second = CoreDataTestHelpers.seedNote(in: context, body: "Chose the stamp game on her own.")
        second.updatedAt = try CoreDataTestHelpers.day("2026-09-30")

        let text = SmartNoteFormatter(students: [], anonymize: false).generateContext(from: [second, first])

        let from = try CoreDataTestHelpers.day("2026-09-02").formatted(date: .abbreviated, time: .omitted)
        let through = try CoreDataTestHelpers.day("2026-09-30").formatted(date: .abbreviated, time: .omitted)
        #expect(text.hasPrefix("2 notes, \(from) – \(through)\n\n"))
        #expect(text.contains("Student: Whole class"))
        #expect(text.contains("About: General observation"))
        #expect(text.contains("Note: Counted to 100 with the bead chain."))
        // Oldest first.
        let firstRange = try #require(text.range(of: "bead chain"))
        let secondRange = try #require(text.range(of: "stamp game"))
        #expect(firstRange.lowerBound < secondRange.lowerBound)
        for marker in ["DATA EXPORT", "CDNote", "Scope:", "ENTRY:", "N/A"] {
            #expect(!text.contains(marker), "the text says \(marker)")
        }
    }

    @Test("One note on one day reads as one note and that day")
    func singleNote() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let note = CoreDataTestHelpers.seedNote(in: context, body: "Read aloud to the group.")
        let day = try CoreDataTestHelpers.day("2026-10-01")
        note.updatedAt = day
        let header = SmartNoteFormatter(students: [], anonymize: false).header(for: [note])
        #expect(header == "1 note, " + day.formatted(date: .abbreviated, time: .omitted))
    }
}
