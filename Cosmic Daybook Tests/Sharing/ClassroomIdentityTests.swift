import CloudKit
import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

// Every device once saved CloudKit's stand-in `__defaultOwner__` as its own
// record name, so the guide's changes read "you" on an assistant's phone
// (docs/Plans/Plan - Who made a change.md). A stand-in is now no ID at all,
// wherever it was saved or stamped.
@Suite("Classroom identity: stand-in record names", .serialized)
@MainActor
struct ClassroomIdentityTests {

    private let standIn = CKCurrentUserDefaultName

    @Test("A stand-in, a blank or a placeholder names nobody")
    func realRecordName() {
        #expect(ClassroomIdentity.realRecordName(nil) == nil)
        #expect(ClassroomIdentity.realRecordName("") == nil)
        #expect(ClassroomIdentity.realRecordName("  ") == nil)
        #expect(ClassroomIdentity.realRecordName(standIn) == nil)
        #expect(ClassroomIdentity.realRecordName("unknown") == nil)
        #expect(ClassroomIdentity.realRecordName("self") == nil)
        #expect(ClassroomIdentity.realRecordName("_a1b2c3") == "_a1b2c3")
    }

    @Test("A stand-in saved by an older build reads as no record name")
    func savedStandInIsDropped() {
        let key = UserDefaultsKeys.classroomIdentityRecordName
        let previous = UserDefaults.standard.string(forKey: key)
        defer { UserDefaults.standard.set(previous, forKey: key) }

        UserDefaults.standard.set(standIn, forKey: key)
        #expect(ClassroomIdentity.currentUserRecordName == nil)

        ClassroomIdentity.currentUserRecordName = "_guide"
        #expect(ClassroomIdentity.currentUserRecordName == "_guide")
        ClassroomIdentity.currentUserRecordName = standIn
        #expect(UserDefaults.standard.string(forKey: key) == nil)
    }

    @Test("An Apple Account change forgets the saved record name at once, then reads the new one")
    func accountChangeReadsAgain() async {
        let key = UserDefaultsKeys.classroomIdentityRecordName
        let previous = UserDefaults.standard.string(forKey: key)
        defer { UserDefaults.standard.set(previous, forKey: key) }

        ClassroomIdentity.currentUserRecordName = "_lastAccount"
        var seenWhileReading: String?
        await ClassroomIdentity.accountChanged {
            seenWhileReading = ClassroomIdentity.currentUserRecordName
            ClassroomIdentity.currentUserRecordName = "_newAccount"
        }
        #expect(seenWhileReading == nil, "nothing is stamped with the last account's ID meanwhile")
        #expect(ClassroomIdentity.currentUserRecordName == "_newAccount")

        // Signed out or offline: the read finds nothing, and no ID stays.
        await ClassroomIdentity.accountChanged {}
        #expect(ClassroomIdentity.currentUserRecordName == nil)
    }

    // MARK: - Restock

    @Test("The guide's stand-in-stamped need reads 'your guide' on her phone and 'You' on his")
    func guideStampOnBothDevices() {
        let herPhone = RestockAuthor(role: .assistant, recordName: standIn, name: "Ana")
        let guidesMac = RestockAuthor(role: .leadGuide, recordName: standIn)
        #expect(herPhone.reads(changedByID: standIn, name: "") == "your guide")
        #expect(guidesMac.reads(changedByID: standIn, name: "") == "You")

        // Once each device knows its real name, old stamps still read right.
        let herPhoneNow = RestockAuthor(role: .assistant, recordName: "_ana", name: "Ana")
        let guidesMacNow = RestockAuthor(role: .leadGuide, recordName: "_guide")
        #expect(herPhoneNow.reads(changedByID: standIn, name: "") == "your guide")
        #expect(guidesMacNow.reads(changedByID: standIn, name: "") == "You")
    }

    @Test("Her stand-in-stamped change reads with her name on the guide's devices, and 'You' on hers")
    func assistantStamp() {
        let guidesMac = RestockAuthor(role: .leadGuide, recordName: "_guide")
        let herPhone = RestockAuthor(role: .assistant, recordName: "_ana", name: "Ana")
        #expect(guidesMac.reads(changedByID: standIn, name: "Ana") == "Ana")
        #expect(herPhone.reads(changedByID: standIn, name: "Ana") == "You")
    }

    @Test("Real record names still tell people apart")
    func realNames() {
        let herPhone = RestockAuthor(role: .assistant, recordName: "_ana", name: "Ana", ownerRecordName: "_guide")
        #expect(herPhone.reads(changedByID: "_ana", name: "Ana") == "You")
        #expect(herPhone.reads(changedByID: "_guide", name: "") == "your guide")
        #expect(herPhone.reads(changedByID: "_bea", name: "") == "another assistant")
        let guidesMac = RestockAuthor(role: .leadGuide, recordName: "_guide")
        #expect(guidesMac.reads(changedByID: "_guide", name: "") == "You")
        #expect(guidesMac.reads(changedByID: "_bea", name: "") == "an assistant")
    }

    @Test("An author never carries a stand-in, as its own name or the owner's")
    func authorDropsStandIns() {
        for placeholder in [standIn, "unknown", "self", ""] {
            let author = RestockAuthor(role: .assistant, recordName: placeholder, ownerRecordName: placeholder)
            #expect(author.recordName == nil)
            #expect(author.ownerRecordName == nil)
        }
    }

    @Test("Owner stand-ins on her membership row don't make the guide 'another assistant'")
    func assistantOwnerFromMembership() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let membership = CDClassroomMembership(context: context)
        membership.role = .assistant
        for placeholder in [standIn, "unknown", "self"] {
            membership.ownerIdentity = placeholder
            let author = RestockAuthor.assistant(in: context)
            #expect(author.ownerRecordName == nil)
            #expect(author.reads(changedByID: "_guide", name: "") == "your guide")
        }
        membership.ownerIdentity = "_guide"
        #expect(RestockAuthor.assistant(in: context).ownerRecordName == "_guide")
    }

    @Test("A need opened by an author rebuilt from a stand-in stamp carries no ID")
    func stampsNoStandIn() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let staple = try RestockTestSupport.staple("Paper Towels", in: context)
        // The way the restock backfill rebuilds the last setter from the staple.
        let setter = RestockAuthor(role: .leadGuide, recordName: standIn)
        RestockService.setLevel(staple, to: .out, by: setter, at: RestockTestSupport.at(60), in: context)
        let need = try #require(RestockService.openNeeds(for: staple, in: context).first)
        #expect(need.addedByID == nil)
        #expect(staple.levelChangedByID == nil)
    }

    // MARK: - Attendance and the front-desk email

    @Test("An assistant's stand-in-stamped mark reads with her name on the guide's devices")
    func attendanceMark() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let student = CDStudent(context: context)
        student.id = UUID()
        student.firstName = "Maya"
        student.lastName = "Stone"
        let record = CDAttendanceRecord(context: context)
        record.studentID = student.cloudKitKey
        record.date = Calendar.current.startOfDay(for: Date())
        record.status = .present
        record.recordedBy = CDClassroomMembership.ClassroomRole.assistant.rawValue
        record.recordedByID = standIn
        record.recordedByName = "Ana"
        let row = AttendanceRow(student: student, record: record, shortName: "Maya", day: record.date ?? Date())

        let onMac = AttendanceRules.markerName(for: row, myRecordName: standIn, myName: nil, guideName: nil)
        #expect(onMac == "Ana")
        let onHerPhone = AttendanceRules.markerName(
            for: row, myRecordName: standIn, myName: "Ana", guideName: nil, viewerRole: .assistant
        )
        #expect(onHerPhone == "you")
        let onBeasPhone = AttendanceRules.markerName(
            for: row, myRecordName: standIn, myName: "Bea", guideName: nil, viewerRole: .assistant
        )
        #expect(onBeasPhone == "Ana")
    }

    @Test("The guide's stand-in-stamped send reads 'your guide' on her phone")
    func emailSend() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let monday = try CoreDataTestHelpers.day("2026-10-12")
        let record = AttendanceEmailLog.recordSend(on: monday, role: .leadGuide, in: context)
        record.sentByID = standIn
        let send = AttendanceEmailLog.Send(record)
        #expect(send.senderName(viewerRole: .assistant, myRecordName: standIn, myName: "Ana") == "your guide")
        #expect(send.senderName(viewerRole: .leadGuide, myRecordName: standIn, myName: nil) == "you")
    }
}
