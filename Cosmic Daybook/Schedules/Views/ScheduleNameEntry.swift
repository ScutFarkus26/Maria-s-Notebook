// ScheduleNameEntry.swift
// Typing or pasting children's names into a person's block on the
// Schedules sheet ("Lucy, Leora, Naomi"). On a comma or Return each finished
// name is matched to an enrolled child through `StudentNameMatcher` and
// joins the block's children; a name that matches nobody, or more than one
// child, stays in the field with a plain line saying why. Save sorts what is
// still in the field first, so a last name typed without a comma is never
// dropped. SwiftUI has no token field outside search, and the HIG's token
// fields are Mac only, so this is a plain text field over the sheet's own
// list of chosen children.

import SwiftUI

/// The names field's state: its text and the names it couldn't place.
nonisolated struct ScheduleNameEntry: Equatable, Sendable {

    /// Why a typed name couldn't be placed.
    enum Reason: Equatable, Sendable {
        /// No enrolled child goes by it.
        case nobody
        /// It fits this many enrolled children.
        case several(Int)
    }

    /// A typed name that couldn't be placed, and why.
    struct Unmatched: Equatable, Sendable {
        let name: String
        let reason: Reason
    }

    var text = ""
    /// The names the last sort couldn't place, as their lines show them.
    var unmatched: [Unmatched] = []

    /// Names end at a comma or a new line (a pasted list, or Return in the field).
    private static let separators = CharacterSet(charactersIn: ",\n\r")

    // MARK: - Sorting

    /// Splits `text` into names and matches each among `students`: one best
    /// candidate is a match; none, or several, leaves the name unmatched.
    /// Matched children come back in the order typed, each once.
    static func sort(
        _ text: String, students: [StudentNameMatcher.Candidate]
    ) -> (matched: [UUID], unmatched: [Unmatched]) {
        var matched: [UUID] = []
        var unmatched: [Unmatched] = []
        for name in names(in: text) {
            let found = StudentNameMatcher.matches(for: name, in: students)
            switch found.count {
            case 1:
                if !matched.contains(found[0].id) { matched.append(found[0].id) }
            case 0:
                unmatched.append(Unmatched(name: name, reason: .nobody))
            default:
                unmatched.append(Unmatched(name: name, reason: .several(found.count)))
            }
        }
        return (matched, unmatched)
    }

    /// The names in `text`, trimmed, empty ones left out.
    static func names(in text: String) -> [String] {
        text.components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// Whether going from `old` to `new` typed or pasted a comma or a new
    /// line: the moment the field sorts its finished names.
    static func addedSeparator(from old: String, to new: String) -> Bool {
        separatorCount(new) > separatorCount(old)
    }

    private static func separatorCount(_ text: String) -> Int {
        text.unicodeScalars.count(where: separators.contains)
    }

    /// Sorts every finished name in the field (those before its last comma
    /// or new line) into `childIDs`. What is still being typed stays, after
    /// any name that couldn't be placed.
    mutating func sortFinished(into childIDs: inout Set<UUID>, students: [StudentNameMatcher.Candidate]) {
        guard let last = text.rangeOfCharacter(from: Self.separators, options: .backwards) else { return }
        let finished = String(text[..<last.lowerBound])
        let typing = String(text[last.upperBound...]).trimmingCharacters(in: .whitespaces)
        let result = Self.sort(finished, students: students)
        childIDs.formUnion(result.matched)
        unmatched = result.unmatched
        let kept = result.unmatched.map(\.name)
        // A name left unplaced is followed by ", " so the next can be typed after it.
        text = kept.isEmpty ? typing : kept.joined(separator: ", ") + ", " + typing
    }

    /// Sorts everything in the field into `childIDs`, as Save does. Returns
    /// whether the field is clear: false when a name couldn't be placed, and
    /// the sheet stays open with its line showing.
    mutating func sortAll(into childIDs: inout Set<UUID>, students: [StudentNameMatcher.Candidate]) -> Bool {
        let result = Self.sort(text, students: students)
        childIDs.formUnion(result.matched)
        unmatched = result.unmatched
        text = result.unmatched.map(\.name).joined(separator: ", ")
        return result.unmatched.isEmpty
    }

    /// Lets go of the lines for names no longer in the field.
    mutating func dropStaleLines() {
        let present = Set(Self.names(in: text))
        unmatched.removeAll { !present.contains($0.name) }
    }

    // MARK: - Words

    /// The plain line under the field for `unmatched`.
    static func line(for unmatched: Unmatched) -> String {
        switch unmatched.reason {
        case .nobody:
            return "No child is called \(unmatched.name). Check the spelling."
        case .several(let count):
            let more = unmatched.name.split(separator: " ").count > 1
                ? "Add more of the last name." : "Add a last initial."
            return "\(countWord(count)) children are called \(unmatched.name). \(more)"
        }
    }

    private static func countWord(_ count: Int) -> String {
        let words = [2: "Two", 3: "Three", 4: "Four", 5: "Five", 6: "Six"]
        return words[count] ?? "\(count)"
    }
}

extension ScheduleNameEntry {

    /// `students` as the name matcher reads them.
    @MainActor
    static func candidates(_ students: [CDStudent]) -> [StudentNameMatcher.Candidate] {
        students.compactMap { student in
            student.id.map {
                StudentNameMatcher.Candidate(
                    id: $0, firstName: student.firstName, lastName: student.lastName, nickname: student.nickname
                )
            }
        }
    }
}

extension ScheduleBlockSheet {

    /// Save's first step: the names still in the field join `childIDs`.
    /// Returns whether saving can go on: false when a name couldn't be
    /// placed. A room's block has no names field, so nothing is sorted.
    static func sortNamesBeforeSave(
        _ names: inout ScheduleNameEntry, into childIDs: inout Set<UUID>,
        laneKind: TimetableLaneKind?, students: [StudentNameMatcher.Candidate]
    ) -> Bool {
        guard laneKind == .person else { return true }
        return names.sortAll(into: &childIDs, students: students)
    }
}

// MARK: - The field

/// The names field and its lines, in the sheet's Children section above
/// Choose Children….
struct ScheduleNameField: View {
    @Binding var entry: ScheduleNameEntry
    @Binding var childIDs: Set<UUID>
    let students: [StudentNameMatcher.Candidate]

    var body: some View {
        TextField("Add by name", text: $entry.text, prompt: Text("Type or paste names: Lucy, Leora"), axis: .vertical)
            .lineLimit(1...4)
            .autocorrectionDisabled()
            #if os(iOS)
            .textInputAutocapitalization(.words)
            #endif
            .onSubmit { sortAll() }
            .onChange(of: entry.text) { old, text in
                if ScheduleNameEntry.addedSeparator(from: old, to: text) {
                    entry.sortFinished(into: &childIDs, students: students)
                } else {
                    entry.dropStaleLines()
                }
            }
        ForEach(entry.unmatched, id: \.name) { unmatched in
            Label(ScheduleNameEntry.line(for: unmatched), systemImage: "exclamationmark.circle")
                .font(AppTheme.ScaledFont.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// Return sorts the last name too, and leaves the sheet open.
    private func sortAll() {
        _ = entry.sortAll(into: &childIDs, students: students)
    }
}
