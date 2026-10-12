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
    case capture(CaptureProposal)
    case error(String)
}

// MARK: - Command Bar Service

/// Private parsing cascade. Existing one-step work and todo commands keep their
/// old form-routing behavior. Classroom accounts are organized into an editable
/// proposal by Apple Intelligence on device, with a deterministic local fallback.
@Observable
final class CommandBarService {
    private static let logger = Logger.app_

    private let localParser = LocalCommandParser()

    var parseState: ParseState = .idle

    func parse(
        input: String,
        students: [StudentData],
        lessons: [LessonData]
    ) async {
        parseState = .parsing

        // Tier 1: Try local keyword + fuzzy matching parser
        let localResult = await localParser.parse(input: input, students: students, lessons: lessons)

        let localFallback: ParsedCommand? = switch localResult {
        case .parsed(let command): command
        case .ambiguous(let suggestions): suggestions.first
        case .failed: nil
        }

        // Preserve the existing quick forms for commands that are not accounts
        // of classroom activity. They remain explicitly confirmed in that form.
        if let localFallback,
           localFallback.intent == .addTodo
            || localFallback.intent == .assignWork
            || localFallback.intent == .recordPractice {
            parseState = .result(localFallback)
            return
        }

        await organizeCapture(
            input: input,
            students: students,
            lessons: lessons,
            localFallback: localFallback
        )
    }

    // MARK: - Capture Proposal

    /// Tries Apple Intelligence on device, then preserves the deterministic
    /// result. No network-backed model is used by this workflow.
    private func organizeCapture(
        input: String,
        students: [StudentData],
        lessons: [LessonData],
        localFallback: ParsedCommand?
    ) async {
        #if ENABLE_FOUNDATION_MODELS && canImport(FoundationModels)
        if #available(macOS 26.0, iOS 26.0, *) {
            // Off the main actor on purpose: the availability probe, the prompt
            // assembly over every lesson name, and the session open all happen
            // here, and none of it may run on the thread AppKit is laying out
            // the sheet's toolbar on. Only the Sendable proposal comes back.
            let outcome: Result<CaptureProposal, Error>? = await Task.detached(priority: .userInitiated) {
                let appleParser = AppleIntelligenceCommandParser()
                guard appleParser.isAvailable else { return nil }
                do {
                    return .success(try await appleParser.parseCapture(
                        input: input,
                        students: students,
                        lessons: lessons
                    ))
                } catch {
                    return .failure(error)
                }
            }.value
            switch outcome {
            case .success(var proposal):
                Self.logger.info("Apple Intelligence organized an editable classroom capture")
                proposal.presentedOn = CaptureDateParser.day(in: input, today: Date())
                parseState = .capture(proposal)
                return
            case .failure(let error):
                Self.logger.warning("On-device capture organization failed: \(error)")
            case nil:
                break
            }
        }
        #endif

        if let localFallback {
            parseState = .capture(Self.makeDeterministicProposal(
                input: input,
                command: localFallback,
                students: students
            ))
        } else {
            parseState = .error(
                "I couldn't identify a student or lesson. Nothing was saved. "
                + "Try something like 'I gave the binomial cube to Sarah'."
            )
        }
    }

    /// Exposed internally so the fallback's conservative behavior can be tested
    /// without requiring Apple Intelligence availability.
    static func makeDeterministicProposal(
        input: String,
        command: ParsedCommand,
        students: [StudentData]
    ) -> CaptureProposal {
        // One child only when nobody else was named: a name it couldn't place
        // ("Sarah", two Sarahs) is someone too, so "Maya and Sarah built the
        // cube" isn't all Maya's (review (b) 2026-10-11).
        let placedCount = command.studentIDs.filter { id in students.contains { $0.id == id } }.count
        let isOneChild = placedCount + command.unresolvedStudentNames.count == 1
        let presentationObservation = command.intent == .recordPresentation && isOneChild
            ? observationAfterFirstSentence(in: input)
            : ""
        let oneChildObservation = command.intent == .addNote ? command.freeText : presentationObservation
        let entries = command.studentIDs.compactMap { id -> StudentCaptureProposal? in
            guard let student = students.first(where: { $0.id == id }) else { return nil }
            return StudentCaptureProposal(
                studentID: id,
                studentName: "\(student.firstName) \(student.lastName)",
                observation: isOneChild ? oneChildObservation : "",
                followUp: .none
            )
        }

        var proposal = CaptureProposal(
            rawText: input,
            recordsPresentation: command.intent == .recordPresentation,
            lessonID: command.lessonID,
            lessonName: command.rawLessonName,
            groupObservation: command.intent == .addNote && !isOneChild ? command.freeText : "",
            studentEntries: entries,
            unresolvedStudentNames: command.unresolvedStudentNames,
            source: .deterministic,
            presentedOn: CaptureDateParser.day(in: input, today: Date())
        )
        // The one child named is the one it couldn't place: what was said
        // waits with her name and goes to whoever the guide picks.
        if isOneChild, entries.isEmpty, let name = command.unresolvedStudentNames.first,
           !oneChildObservation.isEmpty {
            proposal.unplacedWords[name] = UnplacedStudentWords(observation: oneChildObservation)
        }
        return proposal
    }

    /// A conservative fallback can safely retain a separately spoken second
    /// sentence for one child because it copies the guide's words verbatim. It
    /// never interprets those words as a readiness or follow-up decision.
    private static func observationAfterFirstSentence(in input: String) -> String {
        guard let boundary = input.firstIndex(where: { ".!?".contains($0) }) else { return "" }
        return String(input[input.index(after: boundary)...]).trimmed()
    }

    func reset() {
        parseState = .idle
    }
}
