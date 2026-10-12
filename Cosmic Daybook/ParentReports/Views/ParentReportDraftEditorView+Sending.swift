// ParentReportDraftEditorView+Sending.swift
// The report editor's Send section and the platform mail paths.
//
// Nothing in Mail tells the app that a message went: on the Mac the sharing
// service reports only that the message reached Mail, and another mail app on
// the iPhone says nothing. So outside the iPhone's own composer the guide is
// asked "Did the email send?", and the report is marked sent only on her yes
// (bug hunt 2026-10-11 #75, as Draft Request does since 10-09 #25).

import OSLog
import SwiftUI
#if os(iOS)
import MessageUI
#endif

extension ParentReportDraftEditorView {

    var sendSection: some View {
        Section {
            Toggle("Attach PDF report", isOn: $attachPDF)
                .onChange(of: attachPDF) { _, newValue in
                    report?.attachPDF = newValue
                    dependencies.saveCoordinator.save(viewContext, reason: "Update report options")
                }
                .disabled(isSent)

            if guardianEmails.isEmpty {
                Label(
                    "Add a guardian with an email on \(studentName)'s profile to send.",
                    systemImage: "exclamationmark.triangle"
                )
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

            // The PDF a mail link couldn't carry, to send another way.
            if let sharedPDFURL {
                ShareLink(item: sharedPDFURL) {
                    Label("Share PDF…", systemImage: "square.and.arrow.up")
                }
            }
        } header: {
            Text("Send")
        }
    }

    // MARK: - The PDF

    private func makePDFData() -> Data? {
        guard attachPDF else { return nil }
        let reportService = dependencies.reportGeneratorService
        let range = month.closedRange(calendar: AppCalendar.shared)
        let notes = reportService.fetchReportNotes(for: student, dateRange: range, context: viewContext)
        return reportService.generatePDF(
            student: student,
            notes: notes,
            style: .progressReport,
            dateRange: range,
            aiNarrative: narrative.isEmpty ? nil : narrative
        )
    }

    /// The report's PDF written to a temporary file, when it is to go with
    /// the email; nil when it isn't, or couldn't be written.
    private func writePDFFile() -> URL? {
        guard let pdfData = makePDFData() else { return nil }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(studentName) \(month.monthKey).pdf")
        do {
            try pdfData.write(to: url)
            return url
        } catch {
            Logger.reports.warning("Couldn't write the report PDF: \(error)")
            return nil
        }
    }

    func recordSent() {
        guard let report else { return }
        dependencies.monthlyReportDraftService.markSent(report, recipients: guardianEmails)
        onChange()
    }

    private var emailSubject: String {
        report?.subject.isEmpty == false
            ? (report?.subject ?? "")
            : "\(studentName) — \(month.displayName) update"
    }

    // MARK: - Mail

    #if os(iOS)
    @ViewBuilder
    var mailComposer: some View {
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

    /// Mail's own composer when this device has an account (it carries the
    /// PDF). Otherwise a mail link, which another mail app may take: only an
    /// app that took it can have sent anything, and the link carries text
    /// only, so the PDF waits under Share PDF.
    private func send() {
        persistNarrative()
        if MFMailComposeViewController.canSendMail() {
            showingMailComposer = true
            return
        }
        guard let url = AttendanceEmail.makeMailtoURL(
            to: guardianEmails,
            subject: emailSubject,
            body: narrative
        ) else {
            sendErrorMessage = AppErrorMessages.ParentReports.noMailApp
            return
        }
        sharedPDFURL = writePDFFile()
        Task {
            if await UIApplication.shared.open(url) {
                askingWhetherSent = true
            } else {
                sendErrorMessage = AppErrorMessages.ParentReports.noMailApp
            }
        }
    }
    #elseif os(macOS)
    private func send() {
        persistNarrative()
        MacOSMailSender.compose(
            to: guardianEmails.joined(separator: ", "),
            subject: emailSubject,
            body: narrative,
            attachmentURL: writePDFFile()
        ) { outcome in
            switch outcome {
            case .handedToMail, .failed:
                // Reaching Mail isn't sending, and a failure may come after
                // the compose window opened: she says whether it went.
                askingWhetherSent = true
            case .cancelled:
                break
            case .unavailable:
                sendErrorMessage = AppErrorMessages.ParentReports.mailCouldNotOpen
            }
        }
    }
    #else
    private func send() {
        sendErrorMessage = AppErrorMessages.ParentReports.mailCouldNotOpen
    }
    #endif
}
