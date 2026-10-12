// ParentReportDraftEditorView.swift
// Review-and-edit surface for one student's monthly report. The guide reads,
// edits, and sends; AI output is labeled and never leaves without review.
// Sending lives in ParentReportDraftEditorView+Sending.swift.

import SwiftUI
import CoreData

struct ParentReportDraftEditorView: View {
    let student: CDStudent
    let month: ReportMonth
    var onChange: () -> Void = {}

    @Environment(\.managedObjectContext) var viewContext
    @Environment(\.dependencies) var dependencies
    @Environment(\.dismiss) private var dismiss

    @State var report: CDParentCommunication?
    @State var narrative = ""
    @State private var includeReflection = false
    @State var attachPDF = false
    @State private var isGenerating = false
    /// The draft this editor last generated: text that differs from it is the
    /// guide's, and Regenerate asks before replacing it (2026-10-11 #68).
    @State private var lastGeneratedNarrative: String?
    @State private var confirmingRegenerate = false
    @State private var evidence: [MonthlyReportEvidenceItem] = []
    @State var guardianEmails: [String] = []
    @State var showingMailComposer = false
    /// "Did the email send?" Mail never tells the app, so the guide says.
    @State var askingWhetherSent = false
    @State var sendErrorMessage: String?
    /// The PDF written out for Share PDF when a mail link can't carry it.
    @State var sharedPDFURL: URL?

    var studentName: String { student.shortName }
    var hasDraft: Bool { report != nil && !narrative.isEmpty }
    var isSent: Bool { report?.status == .sent }

    var body: some View {
        NavigationStack {
            Form {
                narrativeSection
                if student.level == .adolescent {
                    reflectionSection
                }
                evidenceSection
                sendSection
            }
            .formStyle(.grouped)
            .navigationTitle("\(studentName) — \(month.displayName)")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        persistNarrative()
                        onChange()
                        dismiss()
                    }
                }
            }
            .onAppear(perform: load)
            #if os(iOS)
            .sheet(isPresented: $showingMailComposer, onDismiss: { onChange() }, content: {
                mailComposer
            })
            #endif
            .confirmationDialog(
                "Did the email send?",
                isPresented: $askingWhetherSent,
                titleVisibility: .visible
            ) {
                Button("Yes, mark as sent") { recordSent() }
                Button("Not yet", role: .cancel) {}
            } message: {
                Text(sharedPDFURL == nil
                     ? AppErrorMessages.ParentReports.didItSend
                     : AppErrorMessages.ParentReports.pdfNotAttached)
            }
            .alert("Couldn't Send", isPresented: .init(
                get: { sendErrorMessage != nil },
                set: { if !$0 { sendErrorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(sendErrorMessage ?? "")
            }
        }
        #if os(macOS)
        .frame(minWidth: 520, minHeight: 560)
        #endif
    }

    // MARK: - Sections

    private var narrativeSection: some View {
        Section {
            if report?.aiGenerated == true {
                Label("AI draft — review before sending", systemImage: "sparkles")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            TextEditor(text: $narrative)
                .frame(minHeight: 140)
                // Typing while a draft is on its way would be replaced by it,
                // and a sent report reads as it went home.
                .disabled(isGenerating || report?.status == .sent)
                .onChange(of: narrative) { _, _ in persistNarrative() }
            Button {
                requestDraft()
            } label: {
                if isGenerating {
                    HStack {
                        ProgressView()
                        Text("Drafting from this month's records…")
                    }
                } else {
                    Label(hasDraft ? "Regenerate Draft" : "Generate Draft", systemImage: "wand.and.stars")
                }
            }
            .disabled(isGenerating || isSent)
            .confirmationDialog(
                "Replace the report with a new draft?",
                isPresented: $confirmingRegenerate,
                titleVisibility: .visible
            ) {
                Button("Replace with New Draft", role: .destructive) { generateDraft() }
                Button("Keep My Text", role: .cancel) {}
            } message: {
                Text("The new draft takes the place of the text you have now.")
            }
        } header: {
            Text("Narrative")
        } footer: {
            Text("3–6 sentences, drawn only from what you recorded. Edit freely — your words go to the family.")
        }
    }

    private var reflectionSection: some View {
        Section {
            Toggle("Include student's reflection", isOn: $includeReflection)
                .onChange(of: includeReflection) { _, newValue in
                    report?.includeStudentReflection = newValue
                    dependencies.saveCoordinator.save(viewContext, reason: "Update report options")
                }
                .disabled(isSent)
        } footer: {
            Text("Adds the student's own words from their meeting. Draft the note again to include them.")
        }
    }

    private var evidenceSection: some View {
        Section {
            if evidence.isEmpty {
                Text("Nothing recorded for \(studentName) in \(month.displayName) yet.")
                    .foregroundStyle(.secondary)
            } else {
                DisclosureGroup("\(evidence.count) recorded items") {
                    ForEach(evidence) { item in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.date.formatted(date: .abbreviated, time: .omitted))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(item.phrase)
                                .font(.caption)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        } header: {
            Text("This Month's Records")
        }
    }

    // MARK: - Data

    private func load() {
        let studentID = student.id?.uuidString ?? ""
        let service = dependencies.monthlyReportDraftService
        report = service.existingReport(studentID: studentID, monthKey: month.monthKey)
        narrative = report?.body ?? ""
        // An AI draft she hasn't typed into is replaced without asking.
        lastGeneratedNarrative = report?.aiGenerated == true ? report?.body : nil
        includeReflection = report?.includeStudentReflection ?? false
        attachPDF = report?.attachPDF ?? false

        // Each address on its own: a field holding two used to reach Mail as
        // one broken recipient (2026-10-11 #77).
        let request = CDGuardian.fetchRequest(studentID: studentID)
        guardianEmails = viewContext.safeFetch(request)
            .filter(\.receivesReports)
            .flatMap { AttendanceEmail.parseRecipients(from: $0.email) }

        reloadEvidence()
    }

    private func reloadEvidence() {
        let builder = MonthlyReportContextBuilder(
            context: viewContext,
            reportService: dependencies.reportGeneratorService
        )
        evidence = builder.buildContext(
            for: student,
            month: month,
            includeStudentReflection: includeReflection
        ).allItems.sorted { $0.date < $1.date }
    }

    /// Saves what she typed, making the report on her first words when there
    /// is no draft yet (2026-10-11 #69).
    func persistNarrative() {
        let service = dependencies.monthlyReportDraftService
        guard let saved = service.saveTypedNarrative(narrative, for: student, month: month) else { return }
        if saved.isInserted {
            saved.includeStudentReflection = includeReflection
            saved.attachPDF = attachPDF
        }
        report = saved
        guard saved.hasChanges else { return }
        dependencies.saveCoordinator.save(viewContext, reason: "Save report narrative")
    }

    /// Drafts, asking first when that would replace her own text.
    private func requestDraft() {
        if MonthlyReportDraftService.replacingNeedsConfirmation(
            current: narrative, lastGenerated: lastGeneratedNarrative
        ) {
            confirmingRegenerate = true
        } else {
            generateDraft()
        }
    }

    private func generateDraft() {
        persistNarrative()
        isGenerating = true
        Task {
            let service = dependencies.monthlyReportDraftService
            let draft = await service.generateDraft(
                for: student,
                month: month,
                includeStudentReflection: includeReflection
            )
            let updated = service.upsertReport(for: student, month: month, draft: draft)
            report = updated
            isGenerating = false
            // Sent meanwhile, from another device: what went home stays.
            guard updated.status != .sent else {
                narrative = updated.body
                onChange()
                return
            }
            updated.includeStudentReflection = includeReflection
            updated.attachPDF = attachPDF
            dependencies.saveCoordinator.save(viewContext, reason: "Save report draft")
            lastGeneratedNarrative = draft.narrative
            narrative = draft.narrative
            reloadEvidence()
            onChange()
        }
    }
}
