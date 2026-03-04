//
//  DatabaseAnalysisService.swift
//  Maria's Notebook
//
//  Serializes the classroom database and runs AI analysis via map-reduce chunking.
//  Supports configurable time windows to control scope and cost.
//

import Foundation
import SwiftData
import OSLog

/// Runs AI-powered analysis across the full classroom database.
/// Uses a map-reduce approach: serialize → chunk → analyze each chunk → synthesize.
@MainActor
final class DatabaseAnalysisService {
    private static let logger = Logger.ai

    private let modelContext: ModelContext
    private let mcpClient: MCPClientProtocol

    init(modelContext: ModelContext, mcpClient: MCPClientProtocol) {
        self.modelContext = modelContext
        self.mcpClient = mcpClient
    }

    // MARK: - Public API

    /// Runs a full classroom analysis within the given time window.
    func analyzeClassroom(
        timeWindow: AnalysisTimeWindow = .thisSemester,
        question: String? = nil,
        onProgress: ((AnalysisProgress) -> Void)? = nil
    ) async throws -> ClassroomAnalysisResult {
        mcpClient.configureForFeature(.backgroundTasks)

        // Step 1: Serialize
        onProgress?(.serializing)
        let snapshot = serializeDatabase(timeWindow: timeWindow)

        // Step 2: Determine chunk size based on selected model
        let isLocal = AIFeatureArea.backgroundTasks.resolvedModel().isLocal
        let tokenBudget = isLocal ? 3_000 : 100_000

        // Step 3: Chunk
        let chunks = ChunkSplitter.split(snapshot, tokenBudget: tokenBudget)
        Self.logger.info("Database analysis: \(chunks.count) chunks, tokenBudget=\(tokenBudget)")

        if chunks.isEmpty {
            return ClassroomAnalysisResult(
                summary: "No data found in the selected time window.",
                studentHighlights: [],
                classroomTrends: [],
                actionItems: [],
                dataGaps: ["No records found for the selected period."]
            )
        }

        // Step 4: Map — analyze each chunk
        var partialResults: [String] = []
        for (index, chunk) in chunks.enumerated() {
            onProgress?(.analyzing(chunk: index + 1, total: chunks.count))

            let prompt = buildChunkPrompt(chunk: chunk, index: index, total: chunks.count, question: question)
            let result = try await mcpClient.generateStructuredJSON(
                prompt: prompt,
                systemMessage: AIPrompts.chatAssistant,
                temperature: 0.3,
                maxTokens: 2048
            )
            partialResults.append(result)
        }

        // Step 5: Reduce — synthesize
        onProgress?(.synthesizing)
        let synthesisPrompt = buildSynthesisPrompt(partials: partialResults, question: question)
        let finalJSON = try await mcpClient.generateStructuredJSON(
            prompt: synthesisPrompt,
            systemMessage: AIPrompts.chatAssistant,
            temperature: 0.3,
            maxTokens: 4096
        )

        return try parseResult(from: finalJSON)
    }

    // MARK: - Serialization

    private func serializeDatabase(timeWindow: AnalysisTimeWindow) -> DatabaseSnapshot {
        let queryService = DataQueryService(context: modelContext)
        let cutoff = timeWindow.cutoffDate
        let students = queryService.fetchAllStudents(excludeTest: true)

        return DatabaseSnapshot(
            students: serializeStudents(students),
            lessons: serializeLessons(cutoff: cutoff),
            presentations: serializePresentations(cutoff: cutoff),
            notes: serializeNotes(cutoff: cutoff),
            work: serializeWork(cutoff: cutoff),
            attendance: serializeAttendance(cutoff: cutoff)
        )
    }

    private func serializeStudents(_ students: [Student]) -> String {
        guard !students.isEmpty else { return "" }
        var lines = ["=== STUDENTS (\(students.count)) ==="]
        for s in students.sorted(by: { $0.firstName < $1.firstName }) {
            let age = Calendar.current.dateComponents([.year, .month], from: s.birthday, to: Date())
            let ageStr = "\(age.year ?? 0)y\(age.month ?? 0)m"
            let started = s.dateStarted?.formatted(date: .numeric, time: .omitted) ?? "?"
            lines.append("\(s.firstName) \(s.lastName.prefix(1))|lv:\(s.level.rawValue)|age:\(ageStr)|started:\(started)")
        }
        return lines.joined(separator: "\n")
    }

    private func serializeLessons(cutoff: Date?) -> String {
        var descriptor = FetchDescriptor<Lesson>(sortBy: [SortDescriptor(\.subject), SortDescriptor(\.sortIndex)])
        let lessons = (try? modelContext.fetch(descriptor)) ?? []
        guard !lessons.isEmpty else { return "" }

        var lines = ["=== LESSONS (\(lessons.count)) ==="]
        var currentSubject = ""
        for l in lessons {
            if l.subject != currentSubject {
                currentSubject = l.subject
                lines.append("--- \(currentSubject) ---")
            }
            lines.append("\(l.name)|\(l.group)|order:\(l.orderInGroup)")
        }
        return lines.joined(separator: "\n")
    }

    private func serializePresentations(cutoff: Date?) -> String {
        var descriptor = FetchDescriptor<LessonAssignment>(sortBy: [SortDescriptor(\.presentedAt, order: .reverse)])
        let all = (try? modelContext.fetch(descriptor)) ?? []
        let presentations = cutoff.map { date in all.filter { ($0.presentedAt ?? .distantPast) >= date } } ?? all
        guard !presentations.isEmpty else { return "" }

        var lines = ["=== PRESENTATIONS (\(presentations.count)) ==="]
        for p in presentations.prefix(500) { // Cap at 500 for token sanity
            let date = p.presentedAt?.formatted(date: .numeric, time: .omitted) ?? "scheduled"
            let title = p.lessonTitleSnapshot ?? "?"
            let flags = [
                p.needsPractice ? "NP" : nil,
                p.needsAnotherPresentation ? "NRP" : nil,
                (!p.followUpWork.isEmpty) ? "FU" : nil
            ].compactMap { $0 }.joined(separator: ",")
            lines.append("\(title)|\(date)|\(p.stateRaw)|\(flags)")
        }
        return lines.joined(separator: "\n")
    }

    private func serializeNotes(cutoff: Date?) -> String {
        var descriptor = FetchDescriptor<Note>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        let all = (try? modelContext.fetch(descriptor)) ?? []
        let notes = cutoff.map { date in all.filter { $0.createdAt >= date } } ?? all
        guard !notes.isEmpty else { return "" }

        var lines = ["=== NOTES (\(notes.count)) ==="]
        for n in notes.prefix(1000) { // Cap
            let date = n.createdAt.formatted(date: .numeric, time: .omitted)
            let category = n.category.rawValue
            let body = String(n.body.prefix(200)).replacingOccurrences(of: "\n", with: " ")
            lines.append("\(date)|\(category)|\(body)")
        }
        return lines.joined(separator: "\n")
    }

    private func serializeWork(cutoff: Date?) -> String {
        var descriptor = FetchDescriptor<WorkModel>(sortBy: [SortDescriptor(\.assignedAt, order: .reverse)])
        let all = (try? modelContext.fetch(descriptor)) ?? []
        let work = cutoff.map { date in all.filter { $0.assignedAt >= date } } ?? all
        guard !work.isEmpty else { return "" }

        var lines = ["=== WORK (\(work.count)) ==="]
        for w in work.prefix(500) {
            let assigned = w.assignedAt.formatted(date: .numeric, time: .omitted)
            let status = w.status.rawValue
            let outcome = w.completionOutcome?.rawValue ?? ""
            lines.append("\(w.title)|\(status)|\(assigned)|\(outcome)")
        }
        return lines.joined(separator: "\n")
    }

    private func serializeAttendance(cutoff: Date?) -> String {
        var descriptor = FetchDescriptor<AttendanceRecord>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        let all = (try? modelContext.fetch(descriptor)) ?? []
        let records = cutoff.map { date in all.filter { $0.date >= date } } ?? all
        guard !records.isEmpty else { return "" }

        // Summarize instead of listing every record
        let totalDays = Set(records.map { Calendar.current.startOfDay(for: $0.date) }).count
        let absent = records.filter { $0.status == .absent }.count
        let tardy = records.filter { $0.status == .tardy }.count
        let present = records.filter { $0.status == .present }.count

        return """
        === ATTENDANCE (across \(totalDays) days) ===
        Present: \(present) | Absent: \(absent) | Tardy: \(tardy)
        """
    }

    // MARK: - Prompt Building

    private func buildChunkPrompt(chunk: String, index: Int, total: Int, question: String?) -> String {
        let questionLine = question.map { "\nTeacher's question: \($0)" } ?? ""
        return """
        You are analyzing classroom data for a Montessori guide (chunk \(index + 1) of \(total)).
        \(questionLine)

        Analyze the following data and return a JSON object with these fields:
        - "keyFindings": array of 3-5 important observations from this data
        - "studentNotes": array of {"name": string, "observation": string} for notable students
        - "concerns": array of any issues or gaps you notice
        - "trends": array of patterns you see

        DATA:
        \(chunk)
        """
    }

    private func buildSynthesisPrompt(partials: [String], question: String?) -> String {
        let questionLine = question.map { "\nTeacher's question: \($0)" } ?? ""
        let combined = partials.enumerated().map { "--- Chunk \($0.offset + 1) ---\n\($0.element)" }.joined(separator: "\n\n")
        return """
        You are synthesizing a classroom analysis from \(partials.count) partial analyses.
        \(questionLine)

        Combine the partial results below into a final JSON with these fields:
        - "summary": 2-3 sentence overall summary
        - "studentHighlights": array of {"name": string, "highlights": [string], "concerns": [string]}
        - "classroomTrends": array of observed patterns
        - "actionItems": array of recommended next steps for the teacher
        - "dataGaps": array of areas where more data would be helpful

        PARTIAL ANALYSES:
        \(combined)
        """
    }

    // MARK: - Parsing

    private func parseResult(from json: String) throws -> ClassroomAnalysisResult {
        let data = Data(json.utf8)
        return try JSONDecoder().decode(ClassroomAnalysisResult.self, from: data)
    }
}

// MARK: - Chunk Splitter

enum ChunkSplitter {
    /// Splits a DatabaseSnapshot into text chunks, each within tokenBudget.
    static func split(_ snapshot: DatabaseSnapshot, tokenBudget: Int) -> [String] {
        let sections = [
            snapshot.students,
            snapshot.lessons,
            snapshot.presentations,
            snapshot.notes,
            snapshot.work,
            snapshot.attendance
        ].filter { !$0.isEmpty }

        var chunks: [String] = []
        var currentChunk = ""
        var currentTokens = 0

        for section in sections {
            let sectionTokens = estimateTokens(section)

            if sectionTokens > tokenBudget {
                // Flush current, then sub-split this large section
                if !currentChunk.isEmpty {
                    chunks.append(currentChunk)
                    currentChunk = ""
                    currentTokens = 0
                }
                chunks.append(contentsOf: splitByLines(section, tokenBudget: tokenBudget))
            } else if currentTokens + sectionTokens > tokenBudget {
                chunks.append(currentChunk)
                currentChunk = section
                currentTokens = sectionTokens
            } else {
                currentChunk += (currentChunk.isEmpty ? "" : "\n\n") + section
                currentTokens += sectionTokens
            }
        }

        if !currentChunk.isEmpty {
            chunks.append(currentChunk)
        }

        return chunks
    }

    private static func splitByLines(_ text: String, tokenBudget: Int) -> [String] {
        let lines = text.components(separatedBy: "\n")
        var chunks: [String] = []
        var current: [String] = []
        var tokens = 0

        for line in lines {
            let lineTokens = estimateTokens(line)
            if tokens + lineTokens > tokenBudget && !current.isEmpty {
                chunks.append(current.joined(separator: "\n"))
                current = [line]
                tokens = lineTokens
            } else {
                current.append(line)
                tokens += lineTokens
            }
        }
        if !current.isEmpty {
            chunks.append(current.joined(separator: "\n"))
        }
        return chunks
    }

    /// Rough token estimate: ~4 characters per token.
    static func estimateTokens(_ text: String) -> Int {
        max(1, text.count / 4)
    }
}

// MARK: - Supporting Types

struct DatabaseSnapshot {
    let students: String
    let lessons: String
    let presentations: String
    let notes: String
    let work: String
    let attendance: String
}

enum AnalysisTimeWindow: String, CaseIterable, Identifiable {
    case last30Days = "Last 30 Days"
    case thisSemester = "This Semester"
    case thisYear = "This School Year"
    case allTime = "All Time"

    var id: String { rawValue }

    var cutoffDate: Date? {
        let cal = Calendar.current
        let now = Date()
        switch self {
        case .last30Days:
            return cal.date(byAdding: .day, value: -30, to: now)
        case .thisSemester:
            // Approximate: August 1 or January 1 of current semester
            let month = cal.component(.month, from: now)
            let year = cal.component(.year, from: now)
            if month >= 8 {
                return cal.date(from: DateComponents(year: year, month: 8, day: 1))
            } else {
                return cal.date(from: DateComponents(year: year, month: 1, day: 1))
            }
        case .thisYear:
            let year = cal.component(.year, from: now)
            let month = cal.component(.month, from: now)
            // School year starts in August
            let startYear = month >= 8 ? year : year - 1
            return cal.date(from: DateComponents(year: startYear, month: 8, day: 1))
        case .allTime:
            return nil
        }
    }
}

enum AnalysisProgress: Equatable {
    case serializing
    case analyzing(chunk: Int, total: Int)
    case synthesizing
}

struct ClassroomAnalysisResult: Codable {
    let summary: String
    let studentHighlights: [StudentHighlight]
    let classroomTrends: [String]
    let actionItems: [String]
    let dataGaps: [String]

    struct StudentHighlight: Codable {
        let name: String
        let highlights: [String]
        let concerns: [String]
    }
}
