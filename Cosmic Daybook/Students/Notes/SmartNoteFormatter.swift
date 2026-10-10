// SmartNoteFormatter.swift
// The notes Writing Help shows and drafts from, as plain text, and the draft
// prompts. Moved out of AppleIntelligenceSheet.swift (2026-10-10).

import CoreData
import Foundation

// MARK: - Smart Formatter
struct SmartNoteFormatter {
    let students: [CDStudent]
    let anonymize: Bool

    /// The notes as plain text: a one-line header ("3 notes, Sep 2 – Sep 30")
    /// and each note under plain labels. The guide reads and shares this, and
    /// it is also what Apple Intelligence drafts from.
    func generateContext(from notes: [CDNote]) -> String {
        let sortedNotes = notes.sorted { ($0.updatedAt ?? .distantPast) < ($1.updatedAt ?? .distantPast) }
        let names = anonymize ? NameAnonymizer(students: students) : nil
        let body = sortedNotes.map { formatSingleNote($0, names: names) }.joined(separator: "\n\n")
        return header(for: sortedNotes) + "\n\n" + body
    }

    func header(for sortedNotes: [CDNote]) -> String {
        let count = sortedNotes.count
        let counted = "\(count) \(count == 1 ? "note" : "notes")"
        guard let dates = dateRangeString(notes: sortedNotes) else { return counted }
        return counted + ", " + dates
    }

    private func formatSingleNote(_ note: CDNote, names: NameAnonymizer?) -> String {
        let studentName = resolveStudentName(for: note.scope)
        let contextDetail = resolveContextDetail(for: note)
        let dateStr = (note.updatedAt ?? Date()).formatted(date: .abbreviated, time: .shortened)
        let tagNames = ((note.tags as? [String]) ?? []).map { TagHelper.tagName($0) }.joined(separator: ", ")
        let about = tagNames.isEmpty ? contextDetail : "\(contextDetail) (\(tagNames))"
        // Anonymize hid only the "Student:" line; the names in the note itself
        // went out as written.
        let text = names?.anonymized(note.body) ?? note.body

        return """
        Date: \(dateStr)
        Student: \(studentName)
        About: \(about)
        Note: \(text)
        """
    }

    private func resolveStudentName(for scope: NoteScope) -> String {
        switch scope {
        case .all: return "Whole class"
        case .student(let id):
            guard let student = students.first(where: { $0.id == id }) else { return "Student removed" }
            return anonymize ? NameAnonymizer.label(for: student) : student.fullName
        case .students(let ids):
            if anonymize { return "Group of \(ids.count) \(ids.count == 1 ? "student" : "students")" }
            // Short names ("Maya S"): two Sarahs were both just "Sarah".
            let names = ids.compactMap { id in students.first(where: { $0.id == id })?.shortName }
            return names.joined(separator: ", ")
        }
    }

    private func resolveContextDetail(for note: CDNote) -> String {
        if let lesson = note.lesson { return "\(lesson.name) (lesson)" }
        if let work = note.work { return "\(work.title) (work)" }
        if let pres = note.lessonAssignment {
            let title = (pres.lessonTitleSnapshot ?? "").trimmed()
            return title.isEmpty ? "A presentation" : "\(title) (presentation)"
        }
        return "General observation"
    }

    private func dateRangeString(notes: [CDNote]) -> String? {
        guard let first = notes.first?.updatedAt ?? notes.first?.createdAt,
              let last = notes.last?.updatedAt ?? notes.last?.createdAt else { return nil }
        if AppCalendar.isSameDay(first, last) {
            return first.formatted(date: .abbreviated, time: .omitted)
        }
        let from = first.formatted(date: .abbreviated, time: .omitted)
        let through = last.formatted(date: .abbreviated, time: .omitted)
        return "\(from) – \(through)"
    }
}

// MARK: - Name Anonymizer

/// Swaps every child's name in a note's text for the label Anonymize uses
/// ("Student M"): full name, short name ("Maya S"), first name, nickname and
/// last name, as whole words. Longer forms go first, so "Maya Smith" becomes
/// one label, not "Student M Student M". A name matches written as a name
/// (capitalized) or in capitals, not in lowercase, so a child called Will or
/// Hope doesn't turn "she will" into "she Student W".
struct NameAnonymizer {
    private let replacements: [(regex: NSRegularExpression, label: String)]

    init(students: [CDStudent]) {
        var forms: [(form: String, label: String)] = []
        for student in students {
            let label = Self.label(for: student)
            let first = student.firstName.trimmed()
            let last = student.lastName.trimmed()
            let candidates = [
                "\(first) \(last)", student.shortName, first, (student.nickname ?? "").trimmed(), last
            ]
            for form in candidates where form.count >= 2 {
                forms.append((form, label))
            }
        }
        forms.sort { $0.form.count > $1.form.count }
        replacements = forms.compactMap { entry in
            let written = entry.form.prefix(1).uppercased() + entry.form.dropFirst()
            let spellings = Set([written, entry.form.uppercased()])
                .map { NSRegularExpression.escapedPattern(for: $0) }
                .sorted()
            let pattern = "\\b(?:" + spellings.joined(separator: "|") + ")\\b"
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
            return (regex, entry.label)
        }
    }

    /// The label that stands in for a child: "Student" and her first initial.
    static func label(for student: CDStudent) -> String {
        "Student \(student.firstName.prefix(1))"
    }

    func anonymized(_ text: String) -> String {
        var result = text
        for (regex, label) in replacements {
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(
                in: result, range: range, withTemplate: NSRegularExpression.escapedTemplate(for: label)
            )
        }
        return result
    }
}

// MARK: - Prompt Templates
enum PromptTemplate: String, CaseIterable {
    case raw = "Notes Only"
    case parentEmail = "Parent Email"
    case reportCard = "Report Card"
    case actionPlan = "Action Plan"
    case summary = "Weekly Summary"

    var icon: String {
        switch self {
        case .raw: return "doc.text"
        case .parentEmail: return "envelope.fill"
        case .reportCard: return "list.clipboard.fill"
        case .actionPlan: return "checklist"
        case .summary: return "text.alignleft"
        }
    }

    // swiftlint:disable line_length
    var instruction: String {
        switch self {
        case .raw: return ""
        case .parentEmail:
            return "Task: Draft a supportive, professional email to the parents. Summarize the progress shown in the data. Highlight achievements and gently mention 1 area for growth if applicable."
        case .reportCard:
            return "Task: Summarize the observations into a formal paragraph suitable for a semester report card. Focus on observed behaviors and academic progress."
        case .actionPlan:
            return "Task: Analyze the observations and list 3 specific, actionable follow-up steps for the teacher. Format as a checklist."
        case .summary:
            return "Task: Provide a concise bulleted summary of the key themes found in these notes."
        }
    }
    // swiftlint:enable line_length
}
