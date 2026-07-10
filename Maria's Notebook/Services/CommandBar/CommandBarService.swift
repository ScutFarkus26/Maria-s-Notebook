// CommandBarService.swift
// Orchestrates deterministic local parsing with Apple Intelligence assistance

import Foundation
import OSLog

#if ENABLE_FOUNDATION_MODELS && canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - Parse State

enum ParseState: Sendable {
    case idle
    case parsing
    case result(ParsedCommand)
    case error(String)
}

// MARK: - Command Bar Service

/// Private parsing cascade:
/// 1. Local keyword + fuzzy matching (instant, offline)
/// 2. Apple Intelligence on-device model (fast, free, no network)
@Observable
@MainActor
final class CommandBarService {
    private static let logger = Logger.app_

    private let localParser = LocalCommandParser()

    var parseState: ParseState = .idle

    func parse(
        input: String,
        students: [StudentData],
        lessons: [LessonData],
        mcpClient _: MCPClientProtocol?
    ) async {
        parseState = .parsing

        // Tier 1: Try local keyword + fuzzy matching parser
        let localResult = await localParser.parse(input: input, students: students, lessons: lessons)

        switch localResult {
        case .parsed(let cmd) where cmd.confidence >= ParsedCommand.confidenceThreshold:
            Self.logger.info("Local parser succeeded with confidence \(cmd.confidence)")
            parseState = .result(cmd)
            return

        case .parsed(let lowConfidenceCmd):
            Self.logger.info("Local parser low confidence (\(lowConfidenceCmd.confidence)), escalating")
            await tryAIFallback(
                input: input,
                students: students,
                lessons: lessons,
                localFallback: lowConfidenceCmd
            )

        case .ambiguous(let suggestions):
            if let best = suggestions.first {
                await tryAIFallback(
                    input: input,
                    students: students,
                    lessons: lessons,
                    localFallback: best
                )
            } else {
                parseState = .error("Could not understand command.")
            }

        case .failed(let reason):
            Self.logger.info("Local parser failed: \(reason), escalating")
            await tryAIFallback(
                input: input,
                students: students,
                lessons: lessons,
                localFallback: nil
            )
        }
    }

    // MARK: - Apple Intelligence Fallback

    /// Tries Apple Intelligence, then preserves the best deterministic result.
    private func tryAIFallback(
        input: String,
        students: [StudentData],
        lessons: [LessonData],
        localFallback: ParsedCommand?
    ) async {
        let studentNames = students.map { "\($0.firstName) \($0.lastName)" }
        let lessonNames = lessons.map(\.name)

        // Tier 2: Try Apple Intelligence (on-device, fast, free)
        #if ENABLE_FOUNDATION_MODELS && canImport(FoundationModels)
        if #available(macOS 26.0, iOS 26.0, *) {
            let appleParser = AppleIntelligenceCommandParser()
            if appleParser.isAvailable {
                do {
                    let cmd = try await appleParser.parse(
                        input: input,
                        studentNames: studentNames,
                        lessonNames: lessonNames,
                        students: students,
                        lessons: lessons
                    )
                    Self.logger.info("Apple Intelligence parser succeeded with confidence \(cmd.confidence)")
                    parseState = .result(cmd)
                    return
                } catch {
                    Self.logger.warning("Apple Intelligence parser failed: \(error)")
                }
            }
        }
        #endif

        if let localFallback {
            parseState = .result(localFallback)
        } else {
            parseState = .error(
                "Could not understand command. Try something like "
                + "'gave binomial cube to Sarah'."
            )
        }
    }

    func reset() {
        parseState = .idle
    }
}
