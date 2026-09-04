// AppleIntelligenceCommandParser.swift
// On-device Apple Intelligence parser for natural language commands

import Foundation
import OSLog

#if ENABLE_FOUNDATION_MODELS && canImport(FoundationModels)
import FoundationModels

// MARK: - Generable Struct

@available(macOS 26.0, iOS 26.0, *)
@Generable(description: "Parsed teacher command from natural language input")
struct ParsedTeacherCommand {
    // swiftlint:disable:next line_length
    @Guide(description: "The intent: recordPresentation (gave/showed a lesson), assignWork (assign practice/follow-up), addNote (observation about a student), or addTodo (reminder/task for the teacher)")
    var intent: String

    @Guide(description: "Student names mentioned in the command, matching the provided student list")
    var studentNames: [String]

    @Guide(description: "The lesson name mentioned, matching the provided lesson list, or empty if none")
    var lessonName: String

    @Guide(description: "Any remaining text not captured by intent, student, or lesson extraction")
    var freeText: String
}

@available(macOS 26.0, iOS 26.0, *)
@Generable(description: "A guide's explicitly stated next step for one child")
enum GeneratedCaptureFollowUp {
    case none
    case continueObserving
    case practice
    case represent
    case readyForNextLesson
    case followUpWork
}

@available(macOS 26.0, iOS 26.0, *)
@Generable(description: "One child's explicitly stated observation and next step")
struct GeneratedStudentCapture {
    @Guide(description: "One exact student name from the provided roster")
    var studentName: String

    @Guide(description: "A concise factual observation, without interpretation or diagnosis")
    var observation: String

    @Guide(description: "The exact words in the teacher's input supporting the observation, or empty")
    var observationEvidence: String

    @Guide(description: "An explicitly stated next step; use none whenever the teacher did not state one")
    var followUp: GeneratedCaptureFollowUp

    @Guide(description: "The practice or work detail explicitly stated by the teacher, or empty")
    var followUpDetail: String

    @Guide(description: "The exact words in the teacher's input supporting the next step, or empty")
    var followUpEvidence: String
}

@available(macOS 26.0, iOS 26.0, *)
@Generable(description: "An editable proposal organized from one Montessori classroom account")
struct GeneratedClassroomCapture {
    @Guide(description: "True only when the teacher says the lesson was given, shown, or presented")
    var recordsPresentation: Bool

    @Guide(description: "One exact lesson name from the provided lesson list, or empty")
    var lessonName: String

    @Guide(description: "Exact roster names of all children who received the presentation")
    var presentationStudentNames: [String]

    @Guide(description: "A factual observation shared by the whole named group, or empty")
    var groupObservation: String

    @Guide(description: "The exact words in the teacher's input supporting the group observation, or empty")
    var groupObservationEvidence: String

    @Guide(description: "Child-specific observations or explicitly stated next steps")
    var studentCaptures: [GeneratedStudentCapture]
}

// MARK: - Apple Intelligence Command Parser

@available(macOS 26.0, iOS 26.0, *)
final class AppleIntelligenceCommandParser {
    private static let logger = Logger.ai

    /// Returns true if Apple Intelligence is available on this device.
    var isAvailable: Bool {
        SystemLanguageModel.default.isAvailable
    }

    func parse(
        input: String,
        studentNames: [String],
        lessonNames: [String],
        students: [StudentData],
        lessons: [LessonData]
    ) async throws -> ParsedCommand {
        let model = SystemLanguageModel.default
        guard model.isAvailable else {
            throw LocalModelError.unavailable("Apple Intelligence is not available.")
        }
        guard model.supportsLocale() else {
            throw LocalModelError.unavailable("Apple Intelligence does not support the current language.")
        }

        let studentList = studentNames.joined(separator: ", ")
        let lessonList = lessonNames.prefix(100).joined(separator: ", ")

        let instructions = """
        You are a command parser for a Montessori classroom app. \
        Parse the teacher's input into structured data.

        Available intents:
        - recordPresentation: Teacher gave/presented/showed a lesson to student(s)
        - assignWork: Teacher assigns follow-up work or practice to student(s)
        - addNote: Teacher wants to record an observation about student(s)
        - addTodo: Teacher wants to create a reminder/task for themselves

        Available students: \(studentList)
        Available lessons: \(lessonList)

        Match student and lesson names fuzzily. Use exact names from the lists.
        """

        let session = LanguageModelSession(instructions: instructions)

        let response = try await session.respond(
            to: "Parse this command: \"\(input)\"",
            generating: ParsedTeacherCommand.self,
            options: .init(temperature: 0.0)
        )

        let parsed = response.content

        // Map intent string to enum
        guard let intent = RecordIntent(rawValue: parsed.intent) else {
            Self.logger.warning("Apple Intelligence returned unrecognized intent: \(parsed.intent)")
            throw AppleIntelligenceParserError.invalidIntent(parsed.intent)
        }

        // Map student names back to UUIDs
        let resolvedStudentIDs = resolveStudentIDs(from: parsed.studentNames, in: students)

        // Map lesson name to UUID
        let resolvedLessonID = resolveLessonID(named: parsed.lessonName, in: lessons)

        // Apple Intelligence with @Generable is reliable, give it decent confidence
        var confidence = 0.7
        if !resolvedStudentIDs.isEmpty { confidence += 0.1 }
        if resolvedLessonID != nil { confidence += 0.1 }

        return ParsedCommand(
            intent: intent,
            studentIDs: resolvedStudentIDs,
            lessonID: resolvedLessonID,
            rawStudentNames: parsed.studentNames,
            rawLessonName: parsed.lessonName.isEmpty ? nil : parsed.lessonName,
            freeText: parsed.freeText,
            inferredTags: [],
            confidence: min(confidence, 1.0)
        )
    }

    /// Uses structured, on-device generation to turn one classroom account into
    /// an editable proposal. This method returns values only; it has no access to
    /// Core Data and cannot save anything.
    func parseCapture(
        input: String,
        students: [StudentData],
        lessons: [LessonData]
    ) async throws -> CaptureProposal {
        let model = SystemLanguageModel.default
        guard model.isAvailable else {
            throw LocalModelError.unavailable("Apple Intelligence is not available.")
        }
        guard model.supportsLocale() else {
            throw LocalModelError.unavailable("Apple Intelligence does not support the current language.")
        }

        let studentList = students
            .map { "\($0.firstName) \($0.lastName)" }
            .joined(separator: ", ")
        let lessonList = Self.candidateLessonNames(for: input, lessons: lessons)
            .joined(separator: ", ")

        let instructions = """
        Organize a Montessori guide's classroom account into a reviewable proposal.
        Work only with facts the guide actually stated. Do not infer concentration,
        understanding, mastery, emotion, readiness, intent, or a next lesson.

        Important rules:
        - Use exact student and lesson names from the lists below.
        - A shared observation applies to every named child. Put individual differences
          in the matching child's entry.
        - Choose a next step only when the guide explicitly stated it. Otherwise use none.
        - Copy the exact supporting words into each evidence field. Use an empty evidence
          field when there is no support in the input.
        - Do not add advice and do not create records.

        Students: \(studentList)
        Lessons: \(lessonList)
        """

        let session = LanguageModelSession(model: model, instructions: instructions)
        let response = try await session.respond(
            to: "Organize this account: \"\(input)\"",
            generating: GeneratedClassroomCapture.self,
            options: .init(temperature: 0.0)
        )

        return makeCaptureProposal(from: response.content, input: input, students: students, lessons: lessons)
    }

    // MARK: - Private Helpers

    private func resolveStudentIDs(from names: [String], in students: [StudentData]) -> [UUID] {
        names.compactMap { resolveUniqueStudentID(named: $0, in: students) }
    }

    private func resolveLessonID(named lessonName: String, in lessons: [LessonData]) -> UUID? {
        guard !lessonName.isEmpty else { return nil }
        if let lesson = lessons.first(where: { $0.name.lowercased() == lessonName.lowercased() }) {
            return lesson.id
        }
        let matches = lessons.filter {
            $0.name.localizedCaseInsensitiveContains(lessonName)
        }
        return matches.count == 1 ? matches[0].id : nil
    }

    private func resolveUniqueStudentID(named name: String, in students: [StudentData]) -> UUID? {
        let foldedName = Self.fold(name)
        guard !foldedName.isEmpty else { return nil }

        let fullNameMatches = students.filter {
            Self.fold("\($0.firstName) \($0.lastName)") == foldedName
        }
        if fullNameMatches.count == 1 { return fullNameMatches[0].id }

        let singleNameMatches = students.filter {
            Self.fold($0.firstName) == foldedName || Self.fold($0.nickname ?? "") == foldedName
        }
        if singleNameMatches.count == 1 { return singleNameMatches[0].id }

        let containsMatches = students.filter {
            Self.fold("\($0.firstName) \($0.lastName)").contains(foldedName)
        }
        return containsMatches.count == 1 ? containsMatches[0].id : nil
    }

    private func makeCaptureProposal(
        from generated: GeneratedClassroomCapture,
        input: String,
        students: [StudentData],
        lessons: [LessonData]
    ) -> CaptureProposal {
        let allNames = generated.presentationStudentNames + generated.studentCaptures.map(\.studentName)
        var resolvedIDs: [UUID] = []
        var unresolvedNames: [String] = []

        for name in allNames where !name.trimmed().isEmpty {
            if let id = resolveUniqueStudentID(named: name, in: students) {
                if !resolvedIDs.contains(id) { resolvedIDs.append(id) }
            } else if !unresolvedNames.contains(where: { Self.fold($0) == Self.fold(name) }) {
                unresolvedNames.append(name)
            }
        }

        var entries = resolvedIDs.compactMap { id -> StudentCaptureProposal? in
            guard let student = students.first(where: { $0.id == id }) else { return nil }
            let generatedEntry = generated.studentCaptures.first {
                resolveUniqueStudentID(named: $0.studentName, in: students) == id
            }
            let observation = generatedEntry.flatMap {
                Self.isGrounded($0.observationEvidence, in: input) ? $0.observation.trimmed() : nil
            } ?? ""
            let followUp = generatedEntry.map {
                Self.isGrounded($0.followUpEvidence, in: input)
                    ? Self.mapFollowUp($0.followUp)
                    : .none
            } ?? .none
            let detail = followUp == .none ? "" : (generatedEntry?.followUpDetail.trimmed() ?? "")
            return StudentCaptureProposal(
                studentID: id,
                studentName: "\(student.firstName) \(student.lastName)",
                observation: observation,
                followUp: followUp,
                followUpDetail: detail
            )
        }

        // Keep the roster order stable so the review does not visually jump.
        let rosterOrder = Dictionary(uniqueKeysWithValues: students.enumerated().map { ($0.element.id, $0.offset) })
        entries.sort { (rosterOrder[$0.studentID] ?? .max) < (rosterOrder[$1.studentID] ?? .max) }

        let lessonName = generated.lessonName.trimmed()
        return CaptureProposal(
            rawText: input,
            recordsPresentation: generated.recordsPresentation,
            lessonID: resolveLessonID(named: lessonName, in: lessons),
            lessonName: lessonName.isEmpty ? nil : lessonName,
            groupObservation: Self.isGrounded(generated.groupObservationEvidence, in: input)
                ? generated.groupObservation.trimmed()
                : "",
            studentEntries: entries,
            unresolvedStudentNames: unresolvedNames,
            source: .appleIntelligence
        )
    }

    private static func mapFollowUp(_ value: GeneratedCaptureFollowUp) -> CaptureFollowUp {
        switch value {
        case .none: return .none
        case .continueObserving: return .continueObserving
        case .practice: return .practice
        case .represent: return .represent
        case .readyForNextLesson: return .readyForNextLesson
        case .followUpWork: return .followUpWork
        }
    }

    private static func isGrounded(_ evidence: String, in input: String) -> Bool {
        let evidence = evidence.trimmingCharacters(in: .whitespacesAndNewlines.union(.init(charactersIn: "\"'“”‘’")))
        guard !evidence.isEmpty else { return false }
        return fold(input).contains(fold(evidence))
    }

    private static func candidateLessonNames(for input: String, lessons: [LessonData]) -> [String] {
        let inputWords = Set(fold(input).split(separator: " ").map(String.init).filter { $0.count > 2 })
        let scored = lessons.compactMap { lesson -> (name: String, score: Int)? in
            let lessonWords = Set(fold(lesson.name).split(separator: " ").map(String.init).filter { $0.count > 2 })
            let overlap = inputWords.intersection(lessonWords).count
            let exact = fold(input).contains(fold(lesson.name)) ? 100 : 0
            let score = exact + overlap
            return score > 0 ? (lesson.name, score) : nil
        }
        let matches = scored.sorted {
            $0.score == $1.score ? $0.name < $1.name : $0.score > $1.score
        }.prefix(100).map(\.name)
        return matches.isEmpty ? Array(lessons.prefix(100).map(\.name)) : matches
    }

    private static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }
}

enum AppleIntelligenceParserError: LocalizedError {
    case invalidIntent(String)

    var errorDescription: String? {
        switch self {
        case .invalidIntent(let intent):
            return "Apple Intelligence returned an unrecognized command: \(intent)"
        }
    }
}

#endif
