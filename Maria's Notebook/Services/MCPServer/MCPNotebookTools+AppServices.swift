//
//  MCPNotebookTools+AppServices.swift
//  Maria's Notebook
//
//  The two tools that reach past Core Data into app-level services: writing
//  a backup archive, and drafting a family's monthly report. Both find their
//  service through MCPAppServices, which the app registers at startup; under
//  tests the provider hands them a container built on an in-memory stack.
//

import CoreData
import Foundation

extension MCPNotebookTools {

    // MARK: - Backup

    static func createBackupTool(dependencies: @escaping MCPDependenciesProvider) -> MCPToolDefinition {
        MCPToolDefinition(
            name: "create_backup",
            title: "Create Backup",
            description: "Write a full backup archive of the notebook now, the same file the app's "
                + "Back Up Now button writes. Call it before a bulk change (many presentations, "
                + "attendance for the class, skipping or clearing a year plan) so there is a "
                + "point to restore to. Returns the archive's path and size.",
            inputSchema: ["type": "object", "properties": [:]],
            handler: { _ in
                guard let container = dependencies() else {
                    throw MCPToolError("The app is still starting; backups are not available yet.")
                }
                let result = await container.autoBackupManager.performManualBackup(
                    viewContext: container.viewContext
                )
                return describeBackup(result)
            }
        )
    }

    private static func describeBackup(_ result: AutoBackupManager.BackupResult) -> String {
        switch result {
        case .success(let date, let url):
            let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64)
                .map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) }
            let sizeText = size.map { " (\($0))" } ?? ""
            return "Backup written \(dayString(date)) at \(timeString(date)): "
                + "[backup path=\(url.path)]\(sizeText)"
        case .failure(_, let error):
            return "The backup could not be written: \(error.localizedDescription)"
        case .skippedNoChanges:
            // Manual backups are never change-gated, so this is defensive.
            return "Nothing has changed since the last backup, so no new file was written."
        }
    }

    // MARK: - Parent Report Draft

    static func draftParentReportTool(
        context: @escaping MCPContextProvider,
        dependencies: @escaping MCPDependenciesProvider
    ) -> MCPToolDefinition {
        MCPToolDefinition(
            name: "draft_parent_report",
            title: "Draft Parent Report",
            description: "Draft one child's monthly report from the month's recorded evidence "
                + "(presentations, work, observations marked for the report, attendance) and file "
                + "it as a draft parent communication, exactly as the Parent Reports screen's "
                + "Generate button does. Never sends anything. Refuses to replace a report that "
                + "already has text unless overwrite is true; a reviewed or sent report is never "
                + "replaced.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "student_name": [
                        "type": "string",
                        "description": "The student's first name, full name, nickname, or id"
                    ],
                    "month": [
                        "type": "string",
                        "description": "The report month, YYYY-MM (default: the current month)"
                    ],
                    "include_student_reflection": [
                        "type": "boolean",
                        "description": "Include the child's own reflections from meetings (default false)"
                    ],
                    "overwrite": [
                        "type": "boolean",
                        "description": "Replace an existing draft's text (default false)"
                    ]
                ],
                "required": ["student_name"]
            ],
            handler: { arguments in
                guard let container = dependencies() else {
                    throw MCPToolError("The app is still starting; report drafting is not available yet.")
                }
                let modelContext = context()
                let student = try resolveStudentReference(requireString(arguments, "student_name"), in: modelContext)
                let month = try reportMonthArgument(arguments, "month")
                let includeReflection = arguments["include_student_reflection"]?.boolValue ?? false
                let overwrite = arguments["overwrite"]?.boolValue ?? false
                return try await draftReport(
                    for: student, month: month, includeReflection: includeReflection,
                    overwrite: overwrite, container: container
                )
            }
        )
    }

    private static func draftReport(
        for student: CDStudent,
        month: ReportMonth,
        includeReflection: Bool,
        overwrite: Bool,
        container: AppDependencies
    ) async throws -> String {
        let service = container.monthlyReportDraftService
        let studentID = student.id?.uuidString ?? ""
        let name = student.fullName

        if let existing = service.existingReport(studentID: studentID, monthKey: month.monthKey) {
            let id = existing.id?.uuidString ?? "unknown"
            if existing.status != .draft {
                throw MCPToolError(
                    "\(name)'s \(month.displayName) report is already \(existing.status.displayName.lowercased()) "
                        + "[communication id=\(id)]; it is not replaced. Edit it with "
                        + "record_parent_communication if it needs changing."
                )
            }
            if !overwrite, !existing.body.trimmed().isEmpty {
                return "\(name)'s \(month.displayName) report already has a draft [communication id=\(id)]. "
                    + "Pass overwrite: true to replace its text."
            }
        }

        let draft = await service.generateDraft(
            for: student, month: month, includeStudentReflection: includeReflection
        )
        guard !draft.narrative.isEmpty else {
            return "No evidence was recorded for \(name) in \(month.displayName) — no presentations, "
                + "work, observations marked for the report, or attendance — so there is nothing to draft."
        }

        let report = service.upsertReport(for: student, month: month, draft: draft)
        report.includeStudentReflection = includeReflection
        guard container.viewContext.safeSave() else {
            container.viewContext.rollback()
            throw MCPToolError("The report draft could not be saved.")
        }

        let id = report.id?.uuidString ?? "unknown"
        let source = draft.aiGenerated ? "AI-drafted" : "assembled from the evidence (the model was unavailable)"
        return "Drafted [communication id=\(id)] \(name) — \(month.displayName), \(source), "
            + "from \(draft.includedRefs.count) record(s). Status: draft.\n\n\(draft.narrative)"
    }

    /// Parses a `YYYY-MM` argument, defaulting to the current month.
    static func reportMonthArgument(_ arguments: [String: JSONValue], _ key: String) throws -> ReportMonth {
        guard let text = nonEmpty(arguments[key]?.stringValue) else {
            let now = AppCalendar.shared.dateComponents([.year, .month], from: Date())
            return ReportMonth(year: now.year ?? 1970, month: now.month ?? 1)
        }
        let parts = text.split(separator: "-")
        guard parts.count == 2, let year = Int(parts[0]), let month = Int(parts[1]),
              (1...12).contains(month), year > 1970 else {
            throw MCPToolError("\(key) must be a month in YYYY-MM form, not \"\(text)\".")
        }
        return ReportMonth(year: year, month: month)
    }
}
