//
//  MCPNotebookTools+MasteryCandidates.swift
//  Maria's Notebook
//
//  Who looks ready to be marked mastered, and on what evidence.
//
//  Sequence tracks read "0 mastered" for nearly every child, because
//  recording a presentation never marks mastery and going back to assess is
//  a separate trip the guide rarely makes. Nothing here closes that gap by
//  writing: a mastery mark means the guide assessed the child, and no
//  reading of the record can stand in for that. What this tool does is
//  gather the evidence the notebook already holds — the guide confirmed her
//  ready at capture, her practice work came back proficient, a recall check
//  found it retained — rank it, and hand back the exact `mark_mastered`
//  call, so the guide's yes covers the whole list in one step.
//

import CoreData
import Foundation

extension MCPNotebookTools {

    // MARK: - Tool

    static func masteryCandidatesTool(context: @escaping MCPContextProvider) -> MCPToolDefinition {
        MCPToolDefinition(
            name: "mastery_candidates",
            title: "Mastery Candidates",
            description: "Children with a lesson on record that nobody has marked mastered, where "
                + "the notebook already holds evidence they have it: the guide confirmed them ready "
                + "at capture, their practice work came back complete or proficient, or a recall "
                + "check found it retained. Strongest evidence first, each line citing what the "
                + "evidence was. It proposes only and never writes — it closes with the exact "
                + "mark_mastered call for the list, to make once the guide says they assessed "
                + "these children. Never make that call on the strength of this list alone.",
            inputSchema: masteryCandidatesSchema,
            annotations: .readOnly,
            handler: { arguments in
                try describeMasteryCandidates(arguments: arguments, in: context())
            }
        )
    }

    private static let masteryCandidatesSchema: JSONValue = [
        "type": "object",
        "properties": [
            "student": [
                "type": "string",
                "description": "Only this child: a student id from list_students, a name, or a nickname"
            ],
            "area": [
                "type": "string",
                "description": "Only lessons in this curriculum area, e.g. \"Math\" (case-insensitive)"
            ],
            "group_by": [
                "type": "string",
                "enum": ["student", "lesson"],
                "description": .string("student (the default) lists each child's lessons; "
                    + "lesson lists each lesson's children, which is the shape of a group to assess")
            ],
            "limit": [
                "type": "integer",
                "description": "How many candidates to return, strongest evidence first (default 40, max 200)"
            ]
        ]
    ]

    // MARK: - Candidates

    /// One child on one lesson: given, unmarked, and with something in the
    /// record that suggests she has it.
    private struct MasteryCandidate {
        let student: CDStudent
        let lesson: CDLesson
        /// The evidence phrases, strongest first, as they print.
        let evidence: [String]
        /// The summed weight the ranking sorts on.
        let weight: Int
        /// The day she was first given the lesson; the tiebreak, oldest first.
        let presentedDay: Date?
    }

    private static func describeMasteryCandidates(
        arguments: [String: JSONValue], in modelContext: NSManagedObjectContext
    ) throws -> String {
        let students = try candidateStudents(arguments, in: modelContext)
        let lessons = try candidateLessons(arguments, in: modelContext)
        let limit = intArgument(arguments, "limit", default: 40, range: 1...200)
        let byLesson = (arguments["group_by"]?.stringValue?.trimmed().lowercased() == "lesson")

        let index = PresentationRecordIndex(in: modelContext)
        let evidence = MasteryEvidence(in: modelContext)
        var candidates: [MasteryCandidate] = []
        for student in students {
            guard let studentID = student.id?.uuidString else { continue }
            for (lessonID, given) in index.givenByStudent[studentID] ?? [:] {
                guard !given.mastered, let lesson = lessons[lessonID] else { continue }
                let found = evidence.forPair(student: studentID, lesson: lessonID, given: given)
                guard !found.isEmpty else { continue }
                candidates.append(MasteryCandidate(
                    student: student, lesson: lesson, evidence: found.map(\.phrase),
                    weight: found.reduce(0) { $0 + $1.weight }, presentedDay: given.days.first
                ))
            }
        }
        guard !candidates.isEmpty else {
            return "No candidates: every presented lesson with evidence is already marked, "
                + "or there is no evidence yet."
        }

        candidates.sort(by: strongestEvidenceFirst)
        let shown = Array(candidates.prefix(limit))
        return report(shown, of: candidates.count, byLesson: byLesson)
    }

    /// Strongest evidence first; between equals, the lesson given longest ago,
    /// which is the one that has been waiting to be assessed the longest.
    private static func strongestEvidenceFirst(_ lhs: MasteryCandidate, _ rhs: MasteryCandidate) -> Bool {
        if lhs.weight != rhs.weight { return lhs.weight > rhs.weight }
        let left = lhs.presentedDay ?? .distantFuture
        let right = rhs.presentedDay ?? .distantFuture
        if left != right { return left < right }
        if lhs.student.fullName != rhs.student.fullName {
            return lhs.student.fullName.localizedCaseInsensitiveCompare(rhs.student.fullName) == .orderedAscending
        }
        return lhs.lesson.name.localizedCaseInsensitiveCompare(rhs.lesson.name) == .orderedAscending
    }

    // MARK: - Universe

    private static func candidateStudents(
        _ arguments: [String: JSONValue], in modelContext: NSManagedObjectContext
    ) throws -> [CDStudent] {
        let enrolled = DataQueryService(context: modelContext)
            .fetchAllStudents(excludeTest: true, excludeWithdrawn: true)
            .filter { $0.id != nil }
            .sorted { ($0.lastName, $0.firstName) < ($1.lastName, $1.firstName) }
        guard let reference = arguments["student"]?.stringValue?.trimmed(), !reference.isEmpty else {
            return enrolled
        }
        let student = try resolveStudentReference(reference, in: modelContext)
        let named = enrolled.filter { $0.id == student.id }
        guard !named.isEmpty else {
            throw MCPToolError("\(student.fullName) is not an enrolled student, so she has no candidates.")
        }
        return named
    }

    /// The lessons a candidate may be about, by id string, narrowed by `area`.
    private static func candidateLessons(
        _ arguments: [String: JSONValue], in modelContext: NSManagedObjectContext
    ) throws -> [String: CDLesson] {
        let lessons = modelContext.safeFetch(CDFetchRequest(CDLesson.self))
        guard let area = arguments["area"]?.stringValue?.trimmed(), !area.isEmpty else {
            return Dictionary(lessons.compactMap { lesson in
                lesson.id.map { ($0.uuidString, lesson) }
            }, uniquingKeysWith: { first, _ in first })
        }
        let wanted = area.folding(options: .diacriticInsensitive, locale: .current).lowercased()
        let matching = lessons.filter {
            $0.area.folding(options: .diacriticInsensitive, locale: .current)
                .trimmed().lowercased() == wanted
        }
        guard !matching.isEmpty else {
            let areas = Set(lessons.map { $0.area.trimmed() }).filter { !$0.isEmpty }.sorted()
            throw MCPToolError(
                "No lessons are filed under area \"\(area)\". The areas on file are: "
                    + areas.joined(separator: ", ") + "."
            )
        }
        return Dictionary(matching.compactMap { lesson in
            lesson.id.map { ($0.uuidString, lesson) }
        }, uniquingKeysWith: { first, _ in first })
    }
}

// MARK: - Evidence

extension MCPNotebookTools {

    /// One reason to think a child has a lesson, and how much it counts.
    private struct MasteryEvidenceItem {
        let phrase: String
        let weight: Int
    }

    /// The latest recall check that found a lesson retained.
    private struct MasteryRecallCheck {
        let day: Date?
    }

    /// What the notebook holds, besides the presentation itself, that says a
    /// child has a lesson. Read once for the whole class: two small fetches,
    /// each narrowed by the state that makes it evidence at all. Confirmation
    /// is not fetched here — it already rides on the record index.
    private struct MasteryEvidence {

        /// "studentID|lessonID" → did her completed practice work come back
        /// proficient, or only complete.
        private let practice: [String: Bool]
        /// "studentID|lessonID" → her latest retained recall check.
        private let recall: [String: MasteryRecallCheck]

        init(in modelContext: NSManagedObjectContext) {
            var practice: [String: Bool] = [:]
            let works = CDFetchRequest(CDWorkModel.self)
            works.predicate = NSPredicate(format: "kindRaw == %@", WorkKind.practiceLesson.rawValue)
            for work in modelContext.safeFetch(works) where work.isCompleted || work.status == .complete {
                guard let key = Self.key(work.studentID, work.lessonID) else { continue }
                if practice[key] == true { continue }
                practice[key] = work.completionOutcome == .proficient
            }

            var recall: [String: MasteryRecallCheck] = [:]
            let checks = CDFetchRequest(CDLessonRecallCheck.self)
            checks.predicate = NSPredicate(format: "outcomeRaw == %@", RecallOutcome.retained.rawValue)
            for check in modelContext.safeFetch(checks) {
                guard let key = Self.key(check.studentID, check.lessonID) else { continue }
                let day = check.checkedAt
                if let held = recall[key], (held.day ?? .distantPast) >= (day ?? .distantPast) { continue }
                recall[key] = MasteryRecallCheck(day: day)
            }

            self.practice = practice
            self.recall = recall
        }

        /// The evidence for one child on one lesson, strongest first. Empty
        /// means she is not a candidate: a presentation on its own says she
        /// was shown the lesson, never that she has it.
        func forPair(
            student studentID: String, lesson lessonID: String, given: PresentationRecordIndex.Given
        ) -> [MasteryEvidenceItem] {
            let key = Self.key(studentID, lessonID)
            var items: [MasteryEvidenceItem] = []
            if given.confirmed {
                items.append(MasteryEvidenceItem(
                    phrase: "confirmed ready" + Self.suffix(given.days.last), weight: 3
                ))
            }
            if let proficient = key.flatMap({ practice[$0] }) {
                items.append(proficient
                    ? MasteryEvidenceItem(phrase: "practice complete (proficient)", weight: 3)
                    : MasteryEvidenceItem(phrase: "practice complete", weight: 2))
            }
            if let check = key.flatMap({ recall[$0] }) {
                items.append(MasteryEvidenceItem(
                    phrase: "recall retained" + Self.suffix(check.day), weight: 1
                ))
            }
            return items.enumerated().sorted { lhs, rhs in
                lhs.element.weight == rhs.element.weight
                    ? lhs.offset < rhs.offset
                    : lhs.element.weight > rhs.element.weight
            }.map(\.element)
        }

        private static func key(_ studentID: String, _ lessonID: String) -> String? {
            guard !studentID.isEmpty, !lessonID.isEmpty else { return nil }
            return studentID + "|" + lessonID
        }

        private static func suffix(_ day: Date?) -> String {
            day.map { " " + MCPNotebookTools.dayString($0) } ?? ""
        }
    }
}

// MARK: - Report

extension MCPNotebookTools {

    private static func report(_ shown: [MasteryCandidate], of total: Int, byLesson: Bool) -> String {
        var lines = ["Mastery candidates (\(shown.count)) — presented, not yet marked, with evidence:"]
        for section in byLesson ? lessonSections(shown) : studentSections(shown) {
            lines.append("")
            lines.append(contentsOf: section)
        }
        if shown.count < total {
            lines.append("")
            lines.append("\(total - shown.count) more candidate(s) not shown; raise limit to see them.")
        }
        lines.append("")
        lines.append("Nothing has been marked. To confirm these as assessed, call mark_mastered with:")
        lines.append(marksJSON(shown))
        return lines.joined(separator: "\n")
    }

    /// "Avital Beyderman:" then one line per lesson she is a candidate for.
    private static func studentSections(_ candidates: [MasteryCandidate]) -> [[String]] {
        grouped(candidates) { $0.student.id?.uuidString ?? $0.student.fullName }.map { group in
            ["\(group.items[0].student.fullName):"]
                + group.items.map { "- \(lessonCitation($0.lesson)) — \($0.evidence.joined(separator: "; "))" }
        }
    }

    /// The same rows the other way up: one lesson and the children ready for
    /// it, which is the shape of a group the guide can sit down and assess.
    private static func lessonSections(_ candidates: [MasteryCandidate]) -> [[String]] {
        grouped(candidates) { $0.lesson.id?.uuidString ?? $0.lesson.name }.map { group in
            ["\(describeLesson(group.items[0].lesson)):"]
                + group.items.map { "- \($0.student.fullName) — \($0.evidence.joined(separator: "; "))" }
        }
    }

    /// Groups in rank order: a group appears where its strongest member does,
    /// and its rows keep the ranking they were sorted into.
    private static func grouped(
        _ candidates: [MasteryCandidate], by key: (MasteryCandidate) -> String
    ) -> [(key: String, items: [MasteryCandidate])] {
        var order: [String] = []
        var items: [String: [MasteryCandidate]] = [:]
        for candidate in candidates {
            let identifier = key(candidate)
            if items[identifier] == nil { order.append(identifier) }
            items[identifier, default: []].append(candidate)
        }
        return order.compactMap { identifier in
            guard let group = items[identifier], !group.isEmpty else { return nil }
            return (identifier, group)
        }
    }

    /// The call to make, as valid JSON: one item per lesson with its children
    /// gathered, ready to hand straight back to mark_mastered.
    private static func marksJSON(_ candidates: [MasteryCandidate]) -> String {
        let marks: [JSONValue] = grouped(candidates) { $0.lesson.id?.uuidString ?? $0.lesson.name }
            .map { group in
                .object([
                    "lesson": .string(group.key),
                    "student_names": .array(group.items.map { .string($0.student.fullName) })
                ])
            }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(JSONValue.object(["marks": .array(marks)])),
              let text = String(data: data, encoding: .utf8) else {
            return "{\"marks\":[]}"
        }
        return text
    }

    /// The lesson's citation without its filing: on a child's line the
    /// evidence already follows an em dash.
    private static func lessonCitation(_ lesson: CDLesson) -> String {
        "[lesson id=\(lesson.id?.uuidString ?? "unknown")] \(lesson.name)"
    }
}
