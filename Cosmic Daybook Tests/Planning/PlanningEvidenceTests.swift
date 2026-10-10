import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

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

    @Test("One child's own Re-present on a group presentation reads as reteaching for her alone")
    func ownRepresentIsPerChild() throws {
        let fixture = try makeFixture()
        let ada = try #require(fixture.student.id)
        let ben = CoreDataTestHelpers.seedStudent(in: fixture.context, firstName: "Ben", lastName: "Adler")
        let benID = try #require(ben.id)
        let group = PresentationFactory.makePresented(
            lessonID: try #require(fixture.currentLesson.id),
            studentIDs: [ada, benID],
            presentedAt: Date(timeIntervalSince1970: 1_700_100_000),
            context: fixture.context
        )
        // A meeting's Re-present for Ada: her own row, not the shared flag.
        let row = try LifecycleService.upsertLessonPresentation(
            presentationID: try #require(group.id).uuidString, studentID: ada.uuidString,
            lessonID: group.lessonID, presentedAt: try #require(group.presentedAt), context: fixture.context
        )
        PresentationFollowUpService.beginFollowing(row, at: Date())
        PresentationFollowUpService.resolve(.supportOrRepresent, row: row)
        #expect(!group.needsAnotherPresentation)

        let profiles = StudentReadinessAssessor.assessReadiness(for: [fixture.student, ben], context: fixture.context)
        func signal(_ id: UUID) throws -> ProficiencySignal {
            let profile = try #require(profiles.first { $0.studentID == id })
            return try #require(profile.areaReadiness.first { $0.sequence == "Decimal System" }).proficiencySignal
        }
        #expect(try signal(ada) == .needsReteaching)
        #expect(try signal(benID) == .presented)

        let map = CurriculumDataAssembler.assembleCurriculumMap(for: [fixture.student, ben], context: fixture.context)
        let position = try #require(map.areas.flatMap(\.groups).flatMap(\.lessons).first {
            $0.lessonID == fixture.currentLesson.id
        })
        #expect(position.studentStatuses.first { $0.studentID == ada }?.proficiency == .needsReteaching)
        #expect(position.studentStatuses.first { $0.studentID == benID }?.proficiency == .presented)
    }

    @Test("Group evidence uses the least-supported student")
    func groupEvidenceIsConservative() {
        #expect(EvidenceAvailability.combined([.strong, .some]) == .some)
        #expect(EvidenceAvailability.combined([.strong, .insufficient]) == .insufficient)
        #expect(EvidenceAvailability.combined([]) == .insufficient)
    }
}
