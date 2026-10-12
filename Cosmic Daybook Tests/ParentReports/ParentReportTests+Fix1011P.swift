import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

// Bug hunt 2026-10-11, Parent Reports.
// - #67: "Draft All Missing" could redraft a report that wasn't missing any
//   more, a sent one included, and the upsert reset any report to Draft.
// - #68: Regenerate replaced an edited report with no warning.
// - #69: a report typed by hand before any draft was never saved.
// - #74: the attendance line counted duplicate records, and called going
//   home early after arriving on time a tardy.
// - #76: a shared project follow-up showed only in its first chooser's report.
// - #77: a guardian email field took two addresses as one broken recipient.

/// Always fails, so drafts come from the deterministic fallback.
private struct OfflineModelClient: MCPClientProtocol {
    struct Offline: Error {}
    func generateText(prompt: String, temperature: Double) async throws -> String { throw Offline() }
    func generateStructuredJSON(prompt: String, temperature: Double) async throws -> String { throw Offline() }
    func sendConversation(
        messages: [[String: String]], systemMessage: String?, temperature: Double,
        maxTokens: Int, timeout: TimeInterval?
    ) async throws -> String { throw Offline() }
    // swiftlint:disable:next function_parameter_count
    func streamConversation(
        messages: [[String: String]], systemMessage: String?, temperature: Double,
        maxTokens: Int, timeout: TimeInterval?,
        onText: @escaping @MainActor @Sendable (String) -> Void
    ) async throws -> String { throw Offline() }
}

@Suite("Parent reports (Fix1011P)")
@MainActor
struct ParentReportTests {

    private let month = ReportMonth(year: 2026, month: 9)

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York") ?? .current
        return calendar
    }

    private func date(_ day: Int, hour: Int = 10) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour)) ?? .distantPast
    }

    private func makeService(_ context: NSManagedObjectContext) -> MonthlyReportDraftService {
        MonthlyReportDraftService(
            modelContext: context,
            mcpClient: OfflineModelClient(),
            reportService: ReportGeneratorService()
        )
    }

    private func makeBuilder(_ context: NSManagedObjectContext) -> MonthlyReportContextBuilder {
        MonthlyReportContextBuilder(context: context, reportService: ReportGeneratorService(), calendar: calendar)
    }

    /// A child with a lesson presented in September, so a draft has evidence.
    private func seedChild(_ context: NSManagedObjectContext, firstName: String = "Miriam") throws -> CDStudent {
        let student = CoreDataTestHelpers.seedStudent(
            in: context, firstName: firstName, lastName: "Vale", level: .upper
        )
        let lesson = CoreDataTestHelpers.seedLesson(in: context, name: "Fraction Insets")
        let presentation = CDLessonPresentation(context: context)
        presentation.id = UUID()
        presentation.studentID = try #require(student.id).uuidString
        presentation.lessonID = try #require(lesson.id).uuidString
        presentation.stateRaw = LessonPresentationState.presented.rawValue
        presentation.presentedAt = date(3)
        return student
    }

    // MARK: - #67

    @Test("A new draft never overwrites a report that was already sent")
    func upsertKeepsSentReport() async throws {
        let context = try CoreDataTestHelpers.makeContext()
        let student = try seedChild(context)
        let service = makeService(context)
        let first = await service.generateDraft(for: student, month: month, includeStudentReflection: false)
        let report = service.upsertReport(for: student, month: month, draft: first)
        report.body = "The words that went home."
        service.markSent(report, recipients: ["family@example.com"])
        let sentAt = report.sentAt

        let redraft = MonthlyReportDraftService.Draft(narrative: "A fresh draft.", aiGenerated: true, includedRefs: [])
        service.upsertReport(for: student, month: month, draft: redraft)

        #expect(report.status == .sent)
        #expect(report.body == "The words that went home.")
        #expect(report.sentAt == sentAt)
        #expect(report.aiGenerated == false)
    }

    @Test("Draft All Missing skips a child whose report appeared after the list was made")
    func draftMissingSkipsExistingReport() async throws {
        let context = try CoreDataTestHelpers.makeContext()
        let sent = try seedChild(context, firstName: "Miriam")
        let missing = try seedChild(context, firstName: "Avital")
        let service = makeService(context)

        // The list was made before Miriam's report was written and sent.
        let list = [sent, missing]
        let report = service.upsertReport(
            for: sent, month: month,
            draft: .init(narrative: "Sent text.", aiGenerated: false, includedRefs: [])
        )
        service.markSent(report, recipients: ["family@example.com"])

        let drafted = await service.draftMissingReports(for: list, month: month)

        #expect(drafted == 1)
        #expect(report.body == "Sent text.")
        #expect(report.status == .sent)
        let avitalID = try #require(missing.id).uuidString
        #expect(service.existingReport(studentID: avitalID, monthKey: month.monthKey)?.status == .draft)
    }

    // MARK: - #68

    @Test("Regenerate asks before replacing text that isn't the last draft")
    func regenerateConfirmation() {
        typealias Service = MonthlyReportDraftService
        #expect(Service.replacingNeedsConfirmation(current: "Edited by hand.", lastGenerated: "The draft."))
        #expect(Service.replacingNeedsConfirmation(current: "Typed before any draft.", lastGenerated: nil))
        #expect(!Service.replacingNeedsConfirmation(current: "The draft.", lastGenerated: "The draft."))
        #expect(!Service.replacingNeedsConfirmation(current: "  ", lastGenerated: nil))
    }

    // MARK: - #69

    @Test("Typing a report with no draft yet makes the report, written by the guide")
    func typedReportCreatesRow() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let student = try seedChild(context)
        let service = makeService(context)

        let report = try #require(service.saveTypedNarrative("Miriam built the cube.", for: student, month: month))
        #expect(report.body == "Miriam built the cube.")
        #expect(report.aiGenerated == false)
        #expect(report.status == .draft)
        #expect(report.monthKey == month.monthKey)
        #expect(CoreDataTestHelpers.save(context))

        let studentID = try #require(student.id).uuidString
        #expect(service.existingReport(studentID: studentID, monthKey: month.monthKey)?.objectID == report.objectID)
        #expect(service.saveTypedNarrative("", for: try seedChild(context, firstName: "Ora"), month: month) == nil)
    }

    // MARK: - #74

    @Test("The attendance line counts each school day once, and only late arrivals as tardy")
    func attendanceCountsDaysOnce() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let student = try seedChild(context)
        let studentID = try #require(student.id)
        func mark(_ day: Int, _ status: AttendanceStatus, before: AttendanceStatus? = nil) {
            let record = CoreDataTestHelpers.seedAttendance(in: context, studentID: studentID, date: date(day, hour: 0))
            record.status = status
            record.statusBeforeLeavingRaw = before?.rawValue
        }
        // Two devices marked the 1st before syncing.
        mark(1, .present)
        mark(1, .present)
        mark(2, .absent)
        mark(3, .leftEarly, before: .present)
        mark(4, .leftEarly, before: .tardy)
        mark(5, .tardy)
        #expect(CoreDataTestHelpers.save(context))

        let attendance = try #require(
            makeBuilder(context).buildContext(for: student, month: month, includeStudentReflection: false).attendance
        )
        #expect(attendance.daysPresent == 4)
        #expect(attendance.daysAbsent == 1)
        #expect(attendance.markedDays == 5)
        #expect(attendance.tardies == 2)
    }

    // MARK: - #76

    @Test("A shared project follow-up shows in every participant's report, a classmate's copy in none")
    func sharedWorkReachesEveryParticipant() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let chooser = try seedChild(context, firstName: "Etty")
        let partner = try seedChild(context, firstName: "Sarah")
        let chooserID = try #require(chooser.id)
        let partnerID = try #require(partner.id)
        func addParticipant(_ id: UUID, to work: CDWorkModel) {
            let participant = CDWorkParticipantEntity(context: context)
            participant.studentID = id.uuidString
            participant.work = work
        }

        let shared = CoreDataTestHelpers.seedWorkModel(in: context, title: "Volcano model", studentID: chooserID)
        shared.sourceContextType = .projectSession
        shared.sourceContextID = UUID().uuidString
        addParticipant(chooserID, to: shared)
        addParticipant(partnerID, to: shared)
        shared.status = .done
        shared.completedAt = date(10)

        // Linked copies: one row each, each naming both children.
        let lessonID = UUID()
        let copies = [chooserID, partnerID].map { owner in
            let copy = CoreDataTestHelpers.seedWorkModel(
                in: context, title: "Map of rivers", studentID: owner, lessonID: lessonID
            )
            copy.kind = .practiceLesson
            addParticipant(chooserID, to: copy)
            addParticipant(partnerID, to: copy)
            copy.status = .done
            copy.completedAt = date(12)
            return copy
        }
        #expect(CoreDataTestHelpers.save(context))

        let report = makeBuilder(context).buildContext(for: partner, month: month, includeStudentReflection: false)
        let refs = Set(report.workEvidence.map(\.ref))
        #expect(refs.contains("work:\(try #require(shared.id).uuidString)"))
        #expect(refs.contains("work:\(try #require(copies[1].id).uuidString)"))
        #expect(!refs.contains("work:\(try #require(copies[0].id).uuidString)"), "her own copy, not Etty's")
    }

    // MARK: - #77 Guardian email

    @Test("A guardian's email must be one address")
    func guardianEmailIsOneAddress() {
        #expect(GuardianEditSheet.emailProblem("") == nil)
        #expect(GuardianEditSheet.emailProblem("parent@example.com") == nil)
        #expect(GuardianEditSheet.emailProblem("mom@example.com, dad@example.com") != nil)
        #expect(GuardianEditSheet.emailProblem("mom@example.com dad@example.com") != nil)
        #expect(GuardianEditSheet.emailProblem("not an address") != nil)
    }
}
