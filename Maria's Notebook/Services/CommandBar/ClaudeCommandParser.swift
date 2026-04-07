// ClaudeCommandParser.swift
// Claude API fallback parser for natural language commands

import Foundation
import OSLog

// MARK: - Claude Parse Response

private struct ClaudeParseResponse: Codable {
    let intent: String
    let studentNames: [String]
    let lessonName: String?
    let freeText: String
    let confidence: Double
}

// MARK: - Claude Command Parser

@MainActor
final class ClaudeCommandParser {
    private static let logger = Logger.app_
    private let mcpClient: MCPClientProtocol

    init(mcpClient: MCPClientProtocol) {
        self.mcpClient = mcpClient
    }

    func parse(
        input: String,
        studentNames: [String],
        lessonNames: [String],
        students: [StudentData],
        lessons: [LessonData]
    ) async throws -> ParsedCommand {
        let studentList = studentNames.joined(separator: ", ")
        // Limit lesson list to avoid exceeding context
        let lessonList = lessonNames.prefix(200).joined(separator: ", ")

        let userPrompt = """
        Parse this teacher command: "\(input)"

        Available students: \(studentList)
        Available lessons: \(lessonList)
        """

        let jsonString = try await mcpClient.generateStructuredJSON(
            prompt: userPrompt,
            systemMessage: AIPrompts.commandBarParser,
            temperature: 0.0,
            maxTokens: 256,
            model: "claude-sonnet-4-20250514",
            timeout: nil
        )

        let data = Data(jsonString.utf8)
        let response = try JSONDecoder().decode(ClaudeParseResponse.self, from: data)

        // Map intent string to enum
        guard let intent = RecordIntent(rawValue: response.intent) else {
            throw ClaudeParserError.invalidIntent(response.intent)
        }

        // Map student names back to UUIDs via fuzzy matching
        let resolvedStudentIDs = resolveStudentIDs(from: response.studentNames, in: students)

        // Map lesson name back to UUID
        let resolvedLessonID = resolveLessonID(named: response.lessonName, in: lessons)

        return ParsedCommand(
            intent: intent,
            studentIDs: resolvedStudentIDs,
            lessonID: resolvedLessonID,
            rawStudentNames: response.studentNames,
            rawLessonName: response.lessonName,
            freeText: response.freeText,
            inferredTags: [],
            confidence: response.confidence
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

    private func resolveLessonID(named lessonName: String?, in lessons: [LessonData]) -> UUID? {
        guard let lessonName else { return nil }
        let nameLower = lessonName.lowercased()
        if let lesson = lessons.first(where: { $0.name.lowercased() == nameLower }) {
            return lesson.id
        }
        if let lesson = lessons.first(where: { $0.name.localizedCaseInsensitiveContains(lessonName) }) {
            return lesson.id
        }
        return nil
    }
}

// MARK: - Errors

enum ClaudeParserError: LocalizedError {
    case invalidIntent(String)

    var errorDescription: String? {
        switch self {
        case .invalidIntent(let intent):
            return "Claude returned an unrecognized intent: \(intent)"
        }
    }
}
