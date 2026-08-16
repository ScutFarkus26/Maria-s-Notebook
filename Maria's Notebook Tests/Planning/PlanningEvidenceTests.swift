import CoreData
import Foundation
import Testing
@testable import Maria_s_Notebook

@Suite("Lesson planning evidence")
@MainActor
final class PlanningEvidenceTests {
    private struct Fixture {
        let context: NSManagedObjectContext
        let student: CDStudent
        let currentLesson: CDLesson
        let nextLesson: CDLesson
        let presentation: CDLessonAssignment
    }

    private func makeFixture() throws -> Fixture {
        let context = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        let student = CoreDataTestHelpers.seedStudent(
            in: context,
            firstName: "Ada",
            lastName: "Lovelace"
        )
        let currentLesson = CoreDataTestHelpers.seedLesson(
            in: context,
            name: "Golden Beads",
            area: "Mathematics",
            sequence: "Decimal System"
        )
        currentLesson.orderInSequence = 1
        let nextLesson = CoreDataTestHelpers.seedLesson(
            in: context,
            name: "Stamp Game",
            area: "Mathematics",
            sequence: "Decimal System"
        )
        nextLesson.orderInSequence = 2

        let presentation = PresentationFactory.makePresented(
            lessonID: try #require(currentLesson.id),
            studentIDs: [try #require(student.id)],
            presentedAt: Date(timeIntervalSince1970: 1_700_000_000),
            context: context
        )

        return Fixture(
            context: context,
            student: student,
            currentLesson: currentLesson,
            nextLesson: nextLesson,
            presentation: presentation
        )
    }

    @Test("Work outcomes and practice ratings do not become proficiency")
    func ratingsDoNotInferProficiency() throws {
        let fixture = try makeFixture()
        let studentID = try #require(fixture.student.id)
        let lessonID = try #require(fixture.currentLesson.id)

        let work = CoreDataTestHelpers.seedWorkModel(
            in: fixture.context,
            title: "Golden Beads practice",
            studentID: studentID,
            lessonID: lessonID
        )
        work.status = .review
        work.completionOutcome = .proficient

        let practice = CDPracticeSession(context: fixture.context)
        practice.studentIDsArray = [studentID.uuidString]
        practice.workItemIDsArray = [try #require(work.id).uuidString]
        practice.practiceQualityValue = 5
        practice.independenceLevelValue = 5
        practice.readyForAssessment = true
        practice.madeBreakthrough = true

        let note = CoreDataTestHelpers.seedNote(
            in: fixture.context,
            body: "Appeared anxious during the work cycle."
        )
        note.searchIndexStudentID = studentID
        note.tagsArray = ["behavioral", "emotional"]

        let profile = StudentReadinessAssessor.assessReadiness(
            for: fixture.student,
            context: fixture.context
        )
        let area = try #require(profile.areaReadiness.first {
            $0.area == "Mathematics" && $0.sequence == "Decimal System"
        })

        #expect(area.currentLessonID == lessonID)
        #expect(area.nextLessonID == fixture.nextLesson.id)
        #expect(area.proficiencySignal == .presented)
        #expect(area.evidenceAvailability == .some)
        #expect(area.activeWorkCount == 1)

        let promptSummary = StudentReadinessAssessor.compressedSummary(of: [profile]).lowercased()
        #expect(!promptSummary.contains("behavioral"))
        #expect(!promptSummary.contains("emotional"))
        #expect(!promptSummary.contains("anxious"))

        let curriculum = CurriculumDataAssembler.assembleCurriculumMap(
            for: [fixture.student],
            context: fixture.context
        )
        let status = curriculum.areas
            .flatMap(\.groups)
            .flatMap(\.lessons)
            .first { $0.lessonID == lessonID }?
            .studentStatuses
            .first { $0.studentID == studentID }

        #expect(status?.proficiency == .presented)
    }

    @Test("Guide confirmation is preserved as strong factual evidence")
    func guideConfirmationIsStrongEvidence() throws {
        let fixture = try makeFixture()
        fixture.presentation.confirmStudent(try #require(fixture.student.id))

        let profile = StudentReadinessAssessor.assessReadiness(
            for: fixture.student,
            context: fixture.context
        )
        let area = try #require(profile.areaReadiness.first {
            $0.area == "Mathematics" && $0.sequence == "Decimal System"
        })

        #expect(area.proficiencySignal == .proficient)
        #expect(area.evidenceAvailability == .strong)
    }

    @Test("Guide request for another presentation is preserved")
    func guideRePresentationDecisionIsStrongEvidence() throws {
        let fixture = try makeFixture()
        fixture.presentation.needsPractice = true
        fixture.presentation.needsAnotherPresentation = true

        let profile = StudentReadinessAssessor.assessReadiness(
            for: fixture.student,
            context: fixture.context
        )
        let area = try #require(profile.areaReadiness.first {
            $0.area == "Mathematics" && $0.sequence == "Decimal System"
        })

        #expect(area.proficiencySignal == .needsReteaching)
        #expect(area.evidenceAvailability == .strong)
    }

    @Test("Group evidence uses the least-supported student")
    func groupEvidenceIsConservative() {
        #expect(EvidenceAvailability.combined([.strong, .some]) == .some)
        #expect(EvidenceAvailability.combined([.strong, .insufficient]) == .insufficient)
        #expect(EvidenceAvailability.combined([]) == .insufficient)
    }
}
