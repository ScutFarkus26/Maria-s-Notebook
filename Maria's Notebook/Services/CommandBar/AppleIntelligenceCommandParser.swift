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

// MARK: - Apple Intelligence Command Parser

@available(macOS 26.0, iOS 26.0, *)
@MainActor
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
        guard isAvailable else {
            throw LocalModelError.unavailable("Apple Intelligence is not available.")
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
            throw ClaudeParserError.invalidIntent(parsed.intent)
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
            confidence: min(confidence, 1.0)
        )
    }

    // MARK: - Private Helpers

    private func resolveStudentIDs(from names: [String], in students: [StudentData]) -> [UUID] {
        names.compactMap { name -> UUID? in
            let nameLower = name.lowercased()
            if let student = students.first(where: {
                "\($0.firstName) \($0.lastName)".lowercased() == nameLower
            }) {
                return student.id
            }
            if let student = students.first(where: {
                $0.firstName.lowercased() == nameLower
            }) {
                return student.id
            }
            if let student = students.first(where: {
                "\($0.firstName) \($0.lastName)".localizedCaseInsensitiveContains(name)
            }) {
                return student.id
            }
            return nil
        }
    }

    private func resolveLessonID(named lessonName: String, in lessons: [LessonData]) -> UUID? {
        guard !lessonName.isEmpty else { return nil }
        if let lesson = lessons.first(where: { $0.name.lowercased() == lessonName.lowercased() }) {
            return lesson.id
        }
        if let lesson = lessons.first(where: {
            $0.name.localizedCaseInsensitiveContains(lessonName)
        }) {
            return lesson.id
        }
        return nil
    }
}

#endif
