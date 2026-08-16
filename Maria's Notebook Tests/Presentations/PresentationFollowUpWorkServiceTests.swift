import CoreData
import Foundation
import Testing
@testable import Maria_s_Notebook

@Suite("Presentation Follow-Up Work")
@MainActor
final class PresentationFollowUpWorkServiceTests {
    private struct Fixture {
        let context: NSManagedObjectContext
        let lesson: CDLesson
        let presentationID: UUID
        let rows: [CDLessonPresentation]
    }

    private struct GuideFollowUpBundle: Equatable {
        let actionRaw: String?
        let reviewAt: Date?
        let supportRaw: String?
        let resolvedAt: Date?
        let resolutionRaw: String?
        let updatedAt: Date?

        init(_ row: CDLessonPresentation) {
            actionRaw = row.followUpActionRaw
            reviewAt = row.followUpReviewAt
            supportRaw = row.followUpSupportRaw
            resolvedAt = row.followUpResolvedAt
            resolutionRaw = row.followUpResolutionRaw
            updatedAt = row.followUpUpdatedAt
        }
    }

    private func makeFixture(rowCount: Int = 2) throws -> Fixture {
        let context = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        let lesson = CoreDataTestHelpers.seedLesson(
            in: context,
            name: "The Concept of a Multiple",
            area: "",
            sequence: ""
        )
        let lessonID = try #require(lesson.id)
        let presentationID = UUID()
        let rows = (0..<rowCount).map { index in
            let student = CoreDataTestHelpers.seedStudent(
                in: context,
                firstName: "Child \(index + 1)"
            )
            let row = CDLessonPresentation(context: context)
            row.studentID = student.id?.uuidString ?? ""
            row.lessonID = lessonID.uuidString
            row.presentationID = presentationID.uuidString
            PresentationFollowUpService.beginFollowing(
                row,
                at: Date(timeIntervalSinceReferenceDate: 803_000_000 + Double(index))
            )
            return row
        }
        try context.save()

        return Fixture(
            context: context,
            lesson: lesson,
            presentationID: presentationID,
            rows: rows
        )
    }

    @Test("A named request creates one linked Open Work item for each selected child")
    func createsExactOpenWorkForSelectedChildren() throws {
        let fixture = try makeFixture()
        let lessonID = try #require(fixture.lesson.id)
        let service = PresentationFollowUpWorkService(context: fixture.context)
        let guideFollowUpBefore = fixture.rows.map(GuideFollowUpBundle.init)

        let result = try service.createWork(
            title: "Biography on Stan Lee",
            kind: .report,
            for: fixture.rows,
            presentationID: fixture.presentationID,
            lessonID: lessonID
        )

        #expect(result.createdCount == 2)
        #expect(result.existingCount == 0)
        #expect(result.works.count == 2)
        #expect(Set(result.works.map(\.studentID)) == Set(fixture.rows.map(\.studentID)))

        for work in result.works {
            #expect(work.title == "Biography on Stan Lee")
            #expect(work.kind == .report)
            #expect(work.status == .active)
            #expect(work.isOpen)
            #expect(work.lessonID == lessonID.uuidString)
            #expect(work.presentationID == fixture.presentationID.uuidString)
            #expect(work.sourceContextType == .presentation)
            #expect(work.sourceContextID == fixture.presentationID.uuidString)

            let participants = (work.participants?.allObjects as? [CDWorkParticipantEntity]) ?? []
            #expect(participants.count == 1)
            #expect(participants.first?.studentID == work.studentID)
        }

        let linkedOpenWork = service.linkedOpenWork(
            for: fixture.rows,
            presentationID: fixture.presentationID,
            lessonID: lessonID
        )
        #expect(Set(linkedOpenWork.compactMap(\.id)) == Set(result.works.compactMap(\.id)))
        #expect(fixture.rows.map(GuideFollowUpBundle.init) == guideFollowUpBefore)
    }

    @Test("The rows passed by the editor are the exact child scope")
    func honorsChildScope() throws {
        let fixture = try makeFixture()
        let lessonID = try #require(fixture.lesson.id)
        let selectedRow = try #require(fixture.rows.first)
        let service = PresentationFollowUpWorkService(context: fixture.context)

        let result = try service.createWork(
            title: "Come up with four sentences and symbolize them",
            kind: .followUpAssignment,
            for: [selectedRow],
            presentationID: fixture.presentationID,
            lessonID: lessonID
        )

        let work = try #require(result.created.first)
        #expect(result.createdCount == 1)
        #expect(work.studentID == selectedRow.studentID)

        let allChildrenWork = service.linkedOpenWork(
            for: fixture.rows,
            presentationID: fixture.presentationID,
            lessonID: lessonID
        )
        #expect(allChildrenWork.count == 1)
        #expect(allChildrenWork.first?.studentID == selectedRow.studentID)
    }

    @Test("A repeated submission is reused while a different title or kind remains distinct")
    func preventsAccidentalDoubleSubmit() throws {
        let fixture = try makeFixture()
        let lessonID = try #require(fixture.lesson.id)
        let service = PresentationFollowUpWorkService(context: fixture.context)

        let first = try service.createWork(
            title: "Practice presentation",
            kind: .practiceLesson,
            for: fixture.rows,
            presentationID: fixture.presentationID,
            lessonID: lessonID
        )
        let repeated = try service.createWork(
            title: "  practice \n presentation  ",
            kind: .practiceLesson,
            for: fixture.rows,
            presentationID: fixture.presentationID,
            lessonID: lessonID
        )
        let differentTitle = try service.createWork(
            title: "Practice the presentation with a partner",
            kind: .practiceLesson,
            for: fixture.rows,
            presentationID: fixture.presentationID,
            lessonID: lessonID
        )
        let differentKind = try service.createWork(
            title: "Practice presentation",
            kind: .followUpAssignment,
            for: fixture.rows,
            presentationID: fixture.presentationID,
            lessonID: lessonID
        )

        #expect(first.createdCount == 2)
        #expect(repeated.createdCount == 0)
        #expect(repeated.existingCount == 2)
        #expect(Set(repeated.works.compactMap(\.id)) == Set(first.works.compactMap(\.id)))
        #expect(differentTitle.createdCount == 2)
        #expect(differentKind.createdCount == 2)

        let linked = service.linkedOpenWork(
            for: fixture.rows,
            presentationID: fixture.presentationID,
            lessonID: lessonID
        )
        #expect(linked.count == 6)
    }

    @Test("A failed save removes only this operation's new object graph")
    func failedSavePreservesUnrelatedPendingChanges() throws {
        let fixture = try makeFixture(rowCount: 1)
        let lessonID = try #require(fixture.lesson.id)
        let service = PresentationFollowUpWorkService(context: fixture.context)

        let unrelatedDraft = CoreDataTestHelpers.seedNote(
            in: fixture.context,
            body: "Keep this unsaved observation"
        )
        fixture.lesson.name = "An unrelated unsaved lesson edit"
        let insertedBefore = fixture.context.insertedObjects

        do {
            _ = try service.createWork(
                title: "Biography on Stan Lee",
                kind: .report,
                for: fixture.rows,
                presentationID: fixture.presentationID,
                lessonID: lessonID,
                persist: { false }
            )
            Issue.record("Expected the failed persistence operation to throw")
        } catch let error as PresentationFollowUpWorkService.ServiceError {
            #expect(error == .saveFailed)
        }

        #expect(unrelatedDraft.managedObjectContext === fixture.context)
        #expect(unrelatedDraft.isInserted)
        #expect(unrelatedDraft.body == "Keep this unsaved observation")
        #expect(fixture.lesson.name == "An unrelated unsaved lesson edit")
        #expect(fixture.lesson.isUpdated)
        #expect(fixture.context.insertedObjects == insertedBefore)

        let linked = service.linkedOpenWork(
            for: fixture.rows,
            presentationID: fixture.presentationID,
            lessonID: lessonID
        )
        #expect(linked.isEmpty)
    }

    @Test("A failed save restores sequence bookkeeping changed while linking work")
    func failedSaveRestoresExistingTrackState() throws {
        let fixture = try makeFixture(rowCount: 1)
        let lessonID = try #require(fixture.lesson.id)
        fixture.lesson.area = "Language"
        fixture.lesson.sequence = "Grammar"
        fixture.lesson.orderInSequence = 0

        let nextLesson = CoreDataTestHelpers.seedLesson(
            in: fixture.context,
            name: "The Adjective",
            area: "Language",
            sequence: "Grammar"
        )
        nextLesson.orderInSequence = 1

        let track = CDTrackEntity(context: fixture.context)
        track.title = "Language — Grammar"

        let existingStep = CDTrackStepEntity(context: fixture.context)
        existingStep.track = track
        existingStep.lessonTemplateID = lessonID
        existingStep.orderIndex = 99

        let staleStep = CDTrackStepEntity(context: fixture.context)
        staleStep.track = track
        staleStep.lessonTemplateID = UUID()
        staleStep.orderIndex = 42
        track.steps = NSSet(array: [existingStep, staleStep])
        try fixture.context.save()

        fixture.lesson.name = "Keep this unrelated pending title"
        let service = PresentationFollowUpWorkService(context: fixture.context)

        do {
            _ = try service.createWork(
                title: "Symbolize four sentences",
                kind: .followUpAssignment,
                for: fixture.rows,
                presentationID: fixture.presentationID,
                lessonID: lessonID,
                persist: { false }
            )
            Issue.record("Expected the failed persistence operation to throw")
        } catch let error as PresentationFollowUpWorkService.ServiceError {
            #expect(error == .saveFailed)
        }

        #expect(fixture.lesson.name == "Keep this unrelated pending title")
        #expect(fixture.lesson.isUpdated)
        #expect(existingStep.orderIndex == 99)
        #expect(!staleStep.isDeleted)
        #expect(staleStep.managedObjectContext === fixture.context)

        let remainingSteps = fixture.context.safeFetch(CDFetchRequest(CDTrackStepEntity.self))
        #expect(Set(remainingSteps.compactMap(\.id)) == Set([existingStep.id, staleStep.id].compactMap { $0 }))

        let linked = service.linkedOpenWork(
            for: fixture.rows,
            presentationID: fixture.presentationID,
            lessonID: lessonID
        )
        #expect(linked.isEmpty)
    }

    @Test("A sample-work template is copied into the linked work")
    func instantiatesSampleWorkTemplate() throws {
        let fixture = try makeFixture(rowCount: 1)
        let lessonID = try #require(fixture.lesson.id)
        let service = PresentationFollowUpWorkService(context: fixture.context)
        let sampleWork = CDSampleWorkEntity(context: fixture.context)
        sampleWork.lesson = fixture.lesson
        sampleWork.title = "Prepared biography"
        sampleWork.workKind = .report

        let sampleStep = CDSampleWorkStepEntity(context: fixture.context)
        sampleStep.sampleWork = sampleWork
        sampleStep.title = "Choose three important moments"
        sampleStep.instructions = "Use your notes from the timeline."
        sampleStep.orderIndex = 0
        sampleWork.addToSteps(sampleStep)
        try fixture.context.save()

        let sampleWorkID = try #require(sampleWork.id)
        let result = try service.createWork(
            title: "Biography on Stan Lee",
            kind: .report,
            for: fixture.rows,
            presentationID: fixture.presentationID,
            lessonID: lessonID,
            sampleWorkID: sampleWorkID
        )

        let work = try #require(result.created.first)
        let copiedStep = try #require(work.orderedSteps.first)
        #expect(work.sampleWorkID == sampleWorkID.uuidString)
        #expect(copiedStep.title == "Choose three important moments")
        #expect(copiedStep.instructions == "Use your notes from the timeline.")
    }

    @Test("Check Work schedules every separate linked task and reuses same-day check-ins")
    func schedulesEveryLinkedTaskWithoutSameDayDuplicates() throws {
        let fixture = try makeFixture()
        let lessonID = try #require(fixture.lesson.id)
        let service = PresentationFollowUpWorkService(context: fixture.context)
        let reviewAt = Date(timeIntervalSinceReferenceDate: 803_500_000)

        let sentenceWork = try service.createWork(
            title: "Come up with four sentences and symbolize them",
            kind: .followUpAssignment,
            for: fixture.rows,
            presentationID: fixture.presentationID,
            lessonID: lessonID
        )
        let biographyWork = try service.createWork(
            title: "Biography on Stan Lee",
            kind: .report,
            for: fixture.rows,
            presentationID: fixture.presentationID,
            lessonID: lessonID
        )
        PresentationFollowUpService.setAction(
            .checkWork,
            for: fixture.rows,
            reviewAt: reviewAt
        )

        let first = try service.scheduleCheckIns(
            for: fixture.rows,
            presentationID: fixture.presentationID,
            lessonID: lessonID
        )

        #expect(first.createdCount == 4)
        #expect(first.existingCount == 0)
        #expect(first.rowsWithoutLinkedWork.isEmpty)
        let allWorks = sentenceWork.works + biographyWork.works
        #expect(Set(first.items.compactMap { $0.work.id }) == Set(allWorks.compactMap(\.id)))
        for work in allWorks {
            let checkIns = (work.checkIns?.allObjects as? [CDWorkCheckIn]) ?? []
            let checkIn = try #require(checkIns.first)
            #expect(checkIns.count == 1)
            #expect(checkIn.status == .scheduled)
            #expect(checkIn.date == AppCalendar.startOfDay(reviewAt))
            #expect(checkIn.purpose == "Review \(work.title)")
        }

        // A time change within the same calendar day is still the same check-in.
        for row in fixture.rows {
            row.followUpReviewAt = reviewAt.addingTimeInterval(3_600)
        }
        let repeated = try service.scheduleCheckIns(
            for: fixture.rows,
            presentationID: fixture.presentationID,
            lessonID: lessonID
        )

        #expect(repeated.createdCount == 0)
        #expect(repeated.existingCount == 4)
        #expect(allWorks.allSatisfy {
            (($0.checkIns?.allObjects as? [CDWorkCheckIn]) ?? []).count == 1
        })
    }

    @Test("Check Work reuses a scheduled Open Work check-in created outside the relationship")
    func reusesAndReschedulesDetachedOpenWorkCheckIn() throws {
        let fixture = try makeFixture(rowCount: 1)
        let lessonID = try #require(fixture.lesson.id)
        let service = PresentationFollowUpWorkService(context: fixture.context)
        let workResult = try service.createWork(
            title: "Biography on Stan Lee",
            kind: .report,
            for: fixture.rows,
            presentationID: fixture.presentationID,
            lessonID: lessonID
        )
        let work = try #require(workResult.created.first)
        let workID = try #require(work.id)

        let firstReviewDay = AppCalendar.startOfDay(
            Date(timeIntervalSinceReferenceDate: 803_550_000)
        )
        let detachedCheckIn = CDWorkCheckIn(context: fixture.context)
        detachedCheckIn.workID = workID.uuidString
        detachedCheckIn.work = nil
        detachedCheckIn.date = firstReviewDay
        detachedCheckIn.status = .scheduled
        detachedCheckIn.purpose = "progressCheck"
        PresentationFollowUpService.setAction(
            .checkWork,
            for: fixture.rows,
            reviewAt: firstReviewDay
        )
        try fixture.context.save()

        let reused = try service.scheduleCheckIns(
            for: fixture.rows,
            presentationID: fixture.presentationID,
            lessonID: lessonID
        )

        #expect(reused.createdCount == 0)
        #expect(reused.existingCount == 1)
        #expect(reused.existing.first?.objectID == detachedCheckIn.objectID)
        #expect(detachedCheckIn.work === work)
        #expect(((work.checkIns?.allObjects as? [CDWorkCheckIn]) ?? []).contains {
            $0.objectID == detachedCheckIn.objectID
        })

        let secondReviewDay = try #require(
            AppCalendar.shared.date(byAdding: .day, value: 2, to: firstReviewDay)
        )
        fixture.rows.first?.followUpReviewAt = secondReviewDay
        let rescheduled = try service.scheduleCheckIns(
            for: fixture.rows,
            presentationID: fixture.presentationID,
            lessonID: lessonID
        )

        #expect(rescheduled.createdCount == 0)
        #expect(rescheduled.existingCount == 1)
        #expect(rescheduled.rescheduledCount == 1)
        #expect(detachedCheckIn.date == AppCalendar.startOfDay(secondReviewDay))

        let request = CDFetchRequest(CDWorkCheckIn.self)
        request.predicate = NSPredicate(format: "workID == %@", workID.uuidString)
        #expect(fixture.context.safeFetch(request).count == 1)
    }

    @Test("A failed save restores an existing Open Work check-in date")
    func failedRescheduleRestoresExistingCheckIn() throws {
        let fixture = try makeFixture(rowCount: 1)
        let lessonID = try #require(fixture.lesson.id)
        let service = PresentationFollowUpWorkService(context: fixture.context)
        let workResult = try service.createWork(
            title: "Symbolize four sentences",
            kind: .followUpAssignment,
            for: fixture.rows,
            presentationID: fixture.presentationID,
            lessonID: lessonID
        )
        let work = try #require(workResult.created.first)
        let originalDay = AppCalendar.startOfDay(
            Date(timeIntervalSinceReferenceDate: 803_560_000)
        )
        let newDay = try #require(
            AppCalendar.shared.date(byAdding: .day, value: 3, to: originalDay)
        )

        let checkIn = CDWorkCheckIn(context: fixture.context)
        checkIn.workID = try #require(work.id).uuidString
        checkIn.date = originalDay
        checkIn.status = .scheduled
        checkIn.purpose = "progressCheck"
        PresentationFollowUpService.setAction(
            .checkWork,
            for: fixture.rows,
            reviewAt: newDay
        )
        try fixture.context.save()

        let unrelatedDraft = CoreDataTestHelpers.seedNote(
            in: fixture.context,
            body: "Keep this pending observation"
        )

        do {
            _ = try service.scheduleCheckIns(
                for: fixture.rows,
                presentationID: fixture.presentationID,
                lessonID: lessonID,
                persist: { false }
            )
            Issue.record("Expected the failed persistence operation to throw")
        } catch let error as PresentationFollowUpWorkService.ServiceError {
            #expect(error == .saveFailed)
        }

        #expect(checkIn.date == originalDay)
        #expect(unrelatedDraft.isInserted)
        #expect(unrelatedDraft.body == "Keep this pending observation")
    }

    @Test("Cloud duplicates are shown and scheduled as one Open Work item")
    func collapsesDuplicateWorkIDs() throws {
        let fixture = try makeFixture(rowCount: 1)
        let lessonID = try #require(fixture.lesson.id)
        let service = PresentationFollowUpWorkService(context: fixture.context)
        let originalResult = try service.createWork(
            title: "Practice presentation",
            kind: .practiceLesson,
            for: fixture.rows,
            presentationID: fixture.presentationID,
            lessonID: lessonID
        )
        let original = try #require(originalResult.created.first)

        let duplicate = CDWorkModel(context: fixture.context)
        duplicate.id = original.id
        duplicate.title = original.title
        duplicate.kind = original.kind
        duplicate.studentID = original.studentID
        duplicate.lessonID = original.lessonID
        duplicate.presentationID = original.presentationID
        duplicate.status = .active
        duplicate.createdAt = original.createdAt?.addingTimeInterval(-1)
        try fixture.context.save()

        let linked = service.linkedOpenWork(
            for: fixture.rows,
            presentationID: fixture.presentationID,
            lessonID: lessonID
        )
        #expect(linked.count == 1)

        PresentationFollowUpService.setAction(
            .checkWork,
            for: fixture.rows,
            reviewAt: Date(timeIntervalSinceReferenceDate: 803_575_000)
        )
        let scheduled = try service.scheduleCheckIns(
            for: fixture.rows,
            presentationID: fixture.presentationID,
            lessonID: lessonID
        )
        #expect(scheduled.createdCount == 1)
        #expect(scheduled.items.count == 1)
    }

    @Test("Check Work reports a child with no linked task instead of inventing generic work")
    func reportsMissingLinkedWorkWithoutCreatingIt() throws {
        let fixture = try makeFixture()
        let lessonID = try #require(fixture.lesson.id)
        let selectedRow = try #require(fixture.rows.first)
        let rowWithoutWork = try #require(fixture.rows.last)
        let service = PresentationFollowUpWorkService(context: fixture.context)

        _ = try service.createWork(
            title: "Practice presentation",
            kind: .practiceLesson,
            for: [selectedRow],
            presentationID: fixture.presentationID,
            lessonID: lessonID
        )
        PresentationFollowUpService.setAction(
            .checkWork,
            for: fixture.rows,
            reviewAt: Date(timeIntervalSinceReferenceDate: 803_600_000)
        )

        let result = try service.scheduleCheckIns(
            for: fixture.rows,
            presentationID: fixture.presentationID,
            lessonID: lessonID
        )

        #expect(result.createdCount == 1)
        #expect(result.existingCount == 0)
        #expect(result.rowsWithoutLinkedWork.map(\.objectID) == [rowWithoutWork.objectID])

        let workRequest = CDFetchRequest(CDWorkModel.self)
        let everyWork = fixture.context.safeFetch(workRequest)
        #expect(everyWork.count == 1)
        #expect(everyWork.first?.studentID == selectedRow.studentID)
        #expect(everyWork.allSatisfy { $0.studentID != rowWithoutWork.studentID })
    }

    @Test("A failed check-in save removes only newly scheduled check-ins")
    func failedCheckInSavePreservesOtherPendingChanges() throws {
        let fixture = try makeFixture(rowCount: 1)
        let lessonID = try #require(fixture.lesson.id)
        let service = PresentationFollowUpWorkService(context: fixture.context)
        let workResult = try service.createWork(
            title: "Biography on Stan Lee",
            kind: .report,
            for: fixture.rows,
            presentationID: fixture.presentationID,
            lessonID: lessonID
        )
        let work = try #require(workResult.created.first)
        PresentationFollowUpService.setAction(
            .checkWork,
            for: fixture.rows,
            reviewAt: Date(timeIntervalSinceReferenceDate: 803_700_000)
        )
        try fixture.context.save()

        let unrelatedDraft = CoreDataTestHelpers.seedNote(
            in: fixture.context,
            body: "Keep this other pending note"
        )
        fixture.lesson.name = "Keep this other pending lesson edit"
        let insertedBefore = fixture.context.insertedObjects

        do {
            _ = try service.scheduleCheckIns(
                for: fixture.rows,
                presentationID: fixture.presentationID,
                lessonID: lessonID,
                persist: { false }
            )
            Issue.record("Expected the failed check-in persistence operation to throw")
        } catch let error as PresentationFollowUpWorkService.ServiceError {
            #expect(error == .saveFailed)
        }

        #expect(unrelatedDraft.managedObjectContext === fixture.context)
        #expect(unrelatedDraft.isInserted)
        #expect(unrelatedDraft.body == "Keep this other pending note")
        #expect(fixture.lesson.name == "Keep this other pending lesson edit")
        #expect(fixture.lesson.isUpdated)
        #expect(fixture.context.insertedObjects == insertedBefore)
        let remainingCheckIns = (work.checkIns?.allObjects as? [CDWorkCheckIn]) ?? []
        #expect(remainingCheckIns.isEmpty)
        #expect(fixture.rows.first?.followUpAction == .checkWork)
        #expect(fixture.rows.first?.followUpReviewAt != nil)
    }
}
