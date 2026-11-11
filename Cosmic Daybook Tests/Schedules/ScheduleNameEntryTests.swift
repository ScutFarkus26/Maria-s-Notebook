import Foundation
import SwiftUI
import Testing
@testable import CosmicDaybook

/// Typing or pasting names into a person's block on the Schedules sheet
/// (`ScheduleNameEntry`): each name is matched to one enrolled child, and a
/// name that fits nobody, or more than one child, stays in the field with a
/// plain line. The roster is made up, with the real one's shape: two Ettys
/// and two Sarahs with different last initials, a two-word first name and a
/// nickname.
@Suite("Schedules: names typed into a block")
@MainActor
struct ScheduleNameEntryTests {

    typealias Candidate = StudentNameMatcher.Candidate

    nonisolated static let ettyD = Candidate(id: UUID(), firstName: "Etty", lastName: "Dahan", nickname: nil)
    nonisolated static let ettyK = Candidate(id: UUID(), firstName: "Etty", lastName: "Kramer", nickname: nil)
    nonisolated static let sarahM = Candidate(id: UUID(), firstName: "Sarah", lastName: "Mizrahi", nickname: nil)
    nonisolated static let sarahK = Candidate(id: UUID(), firstName: "Sarah", lastName: "Klein", nickname: nil)
    nonisolated static let leiba = Candidate(id: UUID(), firstName: "Leiba Ruchama", lastName: "Gold", nickname: nil)
    nonisolated static let tiffy = Candidate(id: UUID(), firstName: "Tiferet", lastName: "Shapiro", nickname: "Tiffy")
    nonisolated static let lucy = Candidate(id: UUID(), firstName: "Lucy", lastName: "Tanner", nickname: nil)
    nonisolated static let ora = Candidate(id: UUID(), firstName: "Ora", lastName: "Pell", nickname: nil)

    nonisolated static let roster = [ettyD, ettyK, sarahM, sarahK, leiba, tiffy, lucy, ora]

    private func sorted(_ text: String) -> (matched: [UUID], unmatched: [ScheduleNameEntry.Unmatched]) {
        ScheduleNameEntry.sort(text, students: Self.roster)
    }

    @Test("A last initial, a two-word first name or a nickname finds one child", arguments: [
        ("Etty D.", ettyD.id), ("Etty K", ettyK.id), ("Sarah M.", sarahM.id), ("Leiba R.", leiba.id),
        ("Leiba Ruchama", leiba.id), ("Tiffy", tiffy.id)
    ])
    func oneChild(name: String, child: UUID) {
        let result = sorted(name)
        #expect(result.matched == [child])
        #expect(result.unmatched.isEmpty)
    }

    @Test("A bare shared name is more than one child; a name nobody has is nobody")
    func unmatched() {
        #expect(sorted("Sarah").unmatched == [.init(name: "Sarah", reason: .several(2))])
        #expect(sorted("Etty").unmatched == [.init(name: "Etty", reason: .several(2))])
        #expect(sorted("Vivi").unmatched == [.init(name: "Vivi", reason: .nobody)])
        #expect(sorted("Sarah, Etty, Vivi").matched.isEmpty)
    }

    @Test("A pasted line of six names with stray spaces sorts all six")
    func pastedLine() {
        let result = sorted("  Lucy T ,Ora,  Etty D.,Sarah K  ,\nTiffy , Leiba Ruchama ")
        #expect(result.matched
            == [Self.lucy.id, Self.ora.id, Self.ettyD.id, Self.sarahK.id, Self.tiffy.id, Self.leiba.id])
        #expect(result.unmatched.isEmpty)
    }

    @Test("A child named twice is added once")
    func namedTwice() {
        #expect(sorted("Lucy, Lucy T").matched == [Self.lucy.id])
    }

    @Test("A comma sorts the finished names; what's still being typed, and a name that fits nobody, stay")
    func typing() {
        var entry = ScheduleNameEntry()
        var children: Set<UUID> = []

        entry.text = "Lucy,"
        #expect(ScheduleNameEntry.addedSeparator(from: "Lucy", to: entry.text))
        entry.sortFinished(into: &children, students: Self.roster)
        #expect(children == [Self.lucy.id])
        #expect(entry.text.isEmpty)

        entry.text = "Vivi, Or"
        entry.sortFinished(into: &children, students: Self.roster)
        #expect(entry.text == "Vivi, Or")
        #expect(entry.unmatched == [.init(name: "Vivi", reason: .nobody)])

        entry.text = "Vivi, Ora,"
        entry.sortFinished(into: &children, students: Self.roster)
        #expect(children == [Self.lucy.id, Self.ora.id])
        #expect(entry.text == "Vivi, ")
        // Setting the field back to "Vivi, " types no new comma, so it doesn't sort again.
        #expect(!ScheduleNameEntry.addedSeparator(from: "Vivi, Ora,", to: entry.text))
        #expect(!ScheduleNameEntry.addedSeparator(from: "Vivi, O", to: "Vivi, Or"))

        entry.text = "Ora, "
        entry.dropStaleLines()
        #expect(entry.unmatched.isEmpty, "Vivi was taken out of the field, so its line goes")
    }

    @Test("The lines say what's wrong and what to do")
    func lines() {
        #expect(ScheduleNameEntry.line(for: .init(name: "Sarah", reason: .several(2)))
            == "Two children are called Sarah. Add a last initial.")
        #expect(ScheduleNameEntry.line(for: .init(name: "Etty K", reason: .several(3)))
            == "Three children are called Etty K. Add more of the last name.")
        #expect(ScheduleNameEntry.line(for: .init(name: "Vivi", reason: .nobody))
            == "No child is called Vivi. Check the spelling.")
    }

    // MARK: - Pictures

    @Test("Pictures: the Length row and the Children section with one unmatched name")
    func pictures() throws {
        var entry = ScheduleNameEntry(text: "Sarah, Lu")
        var children: Set<UUID> = [Self.ettyD.id, Self.ora.id]
        entry.text = "Sarah, Lucy,"
        entry.sortFinished(into: &children, students: Self.roster)
        #expect(entry.unmatched.count == 1)
        let chosen = Self.roster.filter { children.contains($0.id) }
            .map { "\($0.firstName) \($0.lastName.prefix(1))" }
            .joined(separator: ", ")
        let finalEntry = entry
        let finalChildren = children

        for scheme in [ColorScheme.dark, .light] {
            let length = VStack(alignment: .leading) {
                ScheduleLengthRow(length: .constant(30), startMinute: 9 * 60 + 50)
            }
            .padding()
            let lengthPNG = try LessonTimePictures.save(
                length, named: "group-sheet-length", scheme: scheme, width: 390
            )
            #expect((lengthPNG?.count ?? 0) > 1_000)

            let section = VStack(alignment: .leading, spacing: 10) {
                Text("CHILDREN").font(.footnote).foregroundStyle(.secondary)
                Text(chosen)
                ScheduleNameField(
                    entry: .constant(finalEntry), childIDs: .constant(finalChildren), students: Self.roster
                )
                Text("Choose Children…").foregroundStyle(Color.accentColor)
            }
            .padding()
            let sectionPNG = try LessonTimePictures.save(
                section, named: "group-sheet-children", scheme: scheme, width: 390
            )
            #expect((sectionPNG?.count ?? 0) > 1_000)
        }
    }
}
