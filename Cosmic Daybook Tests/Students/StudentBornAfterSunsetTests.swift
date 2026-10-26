import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// Schema 21's "Born after sunset" switch goes through `StudentRepository`.
/// Changing only the switch stamps `modifiedAt`, which `ClassroomShareRelease`
/// reads to keep the newer of two copies; saving the same answer doesn't.
@Suite("Born after sunset: saving and copying a child")
@MainActor
struct StudentBornAfterSunsetTests {
    private let earlier = Date(timeIntervalSince1970: 1_750_000_000)

    private struct Seeded {
        let repository: StudentRepository
        let student: CDStudent
        let id: UUID
    }

    private func seeded(bornAfterSunset: Bool = false) throws -> Seeded {
        let context = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        let student = CoreDataTestHelpers.seedStudent(in: context, firstName: "Maya", lastName: "Stone")
        student.bornAfterSunset = bornAfterSunset
        student.modifiedAt = earlier
        #expect(CoreDataTestHelpers.save(context))
        let id = try #require(student.id)
        return Seeded(repository: StudentRepository(context: context), student: student, id: id)
    }

    @Test("Turning only the switch on stamps modifiedAt")
    func switchOnStamps() throws {
        let seed = try seeded()
        #expect(seed.repository.updateStudent(id: seed.id, bornAfterSunset: true))
        #expect(seed.student.bornAfterSunset)
        let stamped = try #require(seed.student.modifiedAt)
        #expect(stamped > earlier)
    }

    @Test("Turning only the switch off stamps modifiedAt")
    func switchOffStamps() throws {
        let seed = try seeded(bornAfterSunset: true)
        #expect(seed.repository.updateStudent(id: seed.id, bornAfterSunset: false))
        #expect(!seed.student.bornAfterSunset)
        let stamped = try #require(seed.student.modifiedAt)
        #expect(stamped > earlier)
    }

    @Test("Saving the same answer leaves modifiedAt alone")
    func sameAnswerDoesNotStamp() throws {
        let seed = try seeded(bornAfterSunset: true)
        #expect(seed.repository.updateStudent(id: seed.id, firstName: "Maya", bornAfterSunset: true))
        #expect(seed.student.modifiedAt == earlier)
    }

    @Test("A child saved before the switch existed reads as born by day, and saving that changes nothing")
    func childFromBeforeTheSwitch() throws {
        let seed = try seeded()
        // A record from a schema-20 device arrives with no value at all.
        seed.student.willChangeValue(forKey: "bornAfterSunset")
        seed.student.setPrimitiveValue(nil, forKey: "bornAfterSunset")
        seed.student.didChangeValue(forKey: "bornAfterSunset")
        seed.student.modifiedAt = earlier
        #expect(seed.student.value(forKey: "bornAfterSunset") == nil)
        #expect(!seed.student.bornAfterSunset)

        #expect(seed.repository.updateStudent(id: seed.id, bornAfterSunset: false))
        #expect(seed.student.modifiedAt == earlier)
    }

    @Test("A new child is born by day unless the switch says otherwise")
    func createStudent() throws {
        let context = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        let repository = StudentRepository(context: context)
        let birthday = try CoreDataTestHelpers.day("2016-03-24")
        let byDay = repository.createStudent(firstName: "Ezra", lastName: "Bloom", birthday: birthday)
        let evening = repository.createStudent(
            firstName: "Tamar", lastName: "Reed", birthday: birthday, bornAfterSunset: true
        )
        #expect(!byDay.bornAfterSunset)
        #expect(evening.bornAfterSunset)
        #expect(CoreDataTestHelpers.save(context))
    }

    @Test("Remove Last Year copies the switch, and a child with no value yet copies as born by day")
    func shareReleaseCopiesTheSwitch() throws {
        let context = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        let evening = CoreDataTestHelpers.seedStudent(in: context, firstName: "Tamar", lastName: "Reed")
        evening.bornAfterSunset = true
        let unset = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ezra", lastName: "Bloom")
        unset.setPrimitiveValue(nil, forKey: "bornAfterSunset")

        let eveningCopy = CDStudent(context: context)
        ClassroomShareRelease.copyAttributes(from: evening, to: eveningCopy)
        let unsetCopy = CDStudent(context: context)
        unsetCopy.bornAfterSunset = true
        ClassroomShareRelease.copyAttributes(from: unset, to: unsetCopy)

        #expect(eveningCopy.bornAfterSunset)
        #expect(!unsetCopy.bornAfterSunset)
        #expect(CoreDataTestHelpers.save(context))
    }
}
