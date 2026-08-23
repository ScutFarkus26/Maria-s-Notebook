// ParentReportDraftEditorView.swift
// Review-and-edit surface for one student's monthly report. The guide reads,
// edits, and sends; AI output is labeled and never leaves without review.

import SwiftUI
import CoreData
#if os(iOS)
import MessageUI
#endif

struct ParentReportDraftEditorView: View {
    let student: CDStudent
    let month: ReportMonth
    var onChange: () -> Void = {}

    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dependencies) private var dependencies
    @Environment(\.dismiss) private var dismiss

    @State private var report: CDParentCommunication?
    @State private var narrative = ""
    @State private var includeReflection = false
    @State private var attachPDF = false
    @State private var isGenerating = false
    @State private var evidence: [MonthlyReportEvidenceItem] = []
    @State private var guardianEmails: [String] = []
    @State private var showingMailComposer = false
    @State private var showingMacSentConfirmation = false
    @State private var sendErrorMessage: String?

    private var studentName: String { StudentFormatter.displayName(for: student) }
    private var hasDraft: Bool { report != nil && !narrative.isEmpty }
    private var isSent: Bool { report?.status == .sent }

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
            .sheet(isPresented: $showingMailComposer, onDismiss: { onChange() }) {
                mailComposer
            }
            #endif
            .confirmationDialog(
                "Did the email send?",
                isPresented: $showingMacSentConfirmation,
                titleVisibility: .visible
            ) {
                Button("Yes, mark as sent") { recordSent() }
                Button("Not yet", role: .cancel) {}
            } message: {
                Text("Mail doesn't confirm delivery back to the app.")
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
                .onChange(of: narrative) { _, _ in persistNarrative() }
            Button {
                generateDraft()
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
                    viewContext.safeSave()
                }
                .disabled(isSent)
        } footer: {
            Text("Adolescents may speak for themselves: weaves their own meeting reflection into the note. Regenerate the draft to apply.")
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

    private var sendSection: some View {
        Section {
            Toggle("Attach PDF report", isOn: $attachPDF)
                .onChange(of: attachPDF) { _, newValue in
                    report?.attachPDF = newValue
                    viewContext.safeSave()
                }
                .disabled(isSent)

            if guardianEmails.isEmpty {
                Label("Add a guardian with an email on \(studentName)'s profile to send.", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(AppColors.warning)
            } else {
                LabeledContent("To") {
                    Text(guardianEmails.joined(separator: ", "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let report, report.status == .draft, hasDraft {
                Button("Mark Reviewed") {
                    dependencies.monthlyReportDraftService.markReviewed(report)
                    onChange()
                }
            }

            if isSent {
                Label(
                    "Sent \(report?.sentAt?.formatted(date: .abbreviated, time: .shortened) ?? "")",
                    systemImage: "checkmark.circle.fill"
                )
                .foregroundStyle(AppColors.success)
            } else {
                Button {
                    send()
                } label: {
                    Label("Send to Family…", systemImage: "paperplane")
                }
                .disabled(!hasDraft || guardianEmails.isEmpty)
            }
        } header: {
            Text("Send")
        }
    }

    // MARK: - Data

    private func load() {
        let studentID = student.id?.uuidString ?? ""
        let service = dependencies.monthlyReportDraftService
        report = service.existingReport(studentID: studentID, monthKey: month.monthKey)
        narrative = report?.body ?? ""
        includeReflection = report?.includeStudentReflection ?? false
        attachPDF = report?.attachPDF ?? false

        let request = CDGuardian.fetchRequest(studentID: studentID)
        guardianEmails = viewContext.safeFetch(request)
            .filter { $0.receivesReports && !$0.email.isEmpty }
            .map(\.email)

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

    private func persistNarrative() {
        guard let report, report.body != narrative else { return }
        report.body = narrative
        report.modifiedAt = Date()
        viewContext.safeSave()
    }

    private func generateDraft() {
        isGenerating = true
        Task {
            let service = dependencies.monthlyReportDraftService
            let draft = await service.generateDraft(
                for: student,
                month: month,
                includeStudentReflection: includeReflection
            )
            let updated = service.upsertReport(for: student, month: month, draft: draft)
            updated.includeStudentReflection = includeReflection
            updated.attachPDF = attachPDF
            viewContext.safeSave()
            report = updated
            narrative = draft.narrative
            isGenerating = false
            reloadEvidence()
            onChange()
        }
    }

    // MARK: - Sending

    private func makePDFData() -> Data? {
        guard attachPDF else { return nil }
        let reportService = dependencies.reportGeneratorService
        let range = month.closedRange(calendar: Calendar.current)
        let notes = reportService.fetchReportNotes(for: student, dateRange: range, context: viewContext)
        return reportService.generatePDF(
            student: student,
            notes: notes,
            style: .progressReport,
            dateRange: range,
            aiNarrative: narrative.isEmpty ? nil : narrative
        )
    }

    private func recordSent() {
        guard let report else { return }
        dependencies.monthlyReportDraftService.markSent(report, recipients: guardianEmails)
        onChange()
    }

    private var emailSubject: String {
        report?.subject.isEmpty == false
            ? (report?.subject ?? "")
            : "\(studentName) — \(month.displayName) update"
    }

    #if os(iOS)
    @ViewBuilder
    private var mailComposer: some View {
        let attachments: [MailComposerView.Attachment] = makePDFData().map {
            [MailComposerView.Attachment(
                data: $0,
                mimeType: "application/pdf",
                fileName: "\(studentName) \(month.monthKey).pdf"
            )]
        } ?? []
        MailComposerView(
            toRecipients: guardianEmails,
            subject: emailSubject,
            body: narrative,
            preferredSender: AttendanceEmail.storedFromAddress(),
            attachments: attachments
        ) { result, _ in
            showingMailComposer = false
            if result == .sent {
                recordSent()
            }
        }
    }

    private func send() {
        persistNarrative()
        if MFMailComposeViewController.canSendMail() {
            showingMailComposer = true
        } else if let url = AttendanceEmail.makeMailtoURL(
            to: guardianEmails,
            subject: emailSubject,
            body: narrative
        ) {
            UIApplication.shared.open(url)
            showingMacSentConfirmation = true
        } else {
            sendErrorMessage = "No mail account is configured on this device."
        }
    }
    #elseif os(macOS)
    private func send() {
        persistNarrative()
        var attachmentURL: URL?
        if let pdfData = makePDFData() {
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("\(studentName) \(month.monthKey).pdf")
            if (try? pdfData.write(to: url)) != nil {
                attachmentURL = url
            }
        }
        MacOSMailSender.send(
            to: guardianEmails.joined(separator: ", "),
            subject: emailSubject,
            body: narrative,
            attachmentURL: attachmentURL
        ) { success in
            if success {
                recordSent()
            } else {
                // The compose window may still have opened; let the guide decide.
                showingMacSentConfirmation = true
            }
        }
    }
    #endif
}
