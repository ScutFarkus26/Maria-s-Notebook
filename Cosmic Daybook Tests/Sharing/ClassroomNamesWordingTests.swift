import CloudKit
import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

// The lines that name people (Restock's who-lines, attendance marks, the
// front-desk email) look names up in the classroom's list by the stamp's record
// name: the name a person goes by now beats the one stamped, and on her phone
// the guide's typed name comes before Apple's and "your guide".
@Suite("Classroom names: wording")
@MainActor
struct ClassroomNamesWordingTests {

    private typealias Support = ClassroomNamesTestSupport

    /// Danny (the guide), Ana (stamped "Ana" back then, "Ana B" now) and Bea,
    /// who named herself after her first marks.
    private let names = ClassroomNames.Snapshot(
        names: ["_guide": "Danny", "_ana": "Ana B", "_bea": "Bea"],
        roles: ["_guide": .leadGuide, "_ana": .assistant, "_bea": .assistant],
        guideName: "Danny"
    )

    @Test("On her phone an old guide stamp with no ID reads his name, in Restock, attendance and the email")
    func guideStampOnHerPhone() throws {
        let herPhone = RestockAuthor(
            role: .assistant, recordName: "_ana", name: "Ana B", ownerRecordName: "_guide", names: names
        )
        #expect(herPhone.reads(changedByID: nil, name: "") == "Danny")
        #expect(herPhone.reads(changedByID: CKCurrentUserDefaultName, name: "") == "Danny")
        #expect(herPhone.reads(changedByID: "_guide", name: "") == "Danny")
        #expect(herPhone.reading(ClassroomNames.Snapshot()).reads(changedByID: nil, name: "") == "your guide")

        let context = try CoreDataTestHelpers.makeContext()
        let mark = Support.mark(by: .leadGuide, id: nil, name: nil, in: context)
        let onHerPhone = AttendanceRules.markerName(
            for: mark, myRecordName: "_ana", myName: "Ana B", guideName: "Apple Name", viewerRole: .assistant,
            names: names
        )
        #expect(onHerPhone == "Danny")
        let withoutList = AttendanceRules.markerName(
            for: mark, myRecordName: "_ana", myName: "Ana B", guideName: "Apple Name", viewerRole: .assistant
        )
        #expect(withoutList == "Apple Name")

        let send = Support.send(by: .leadGuide, id: CKCurrentUserDefaultName, name: nil, in: context)
        let sender = send.senderName(
            viewerRole: .assistant, myRecordName: "_ana", myName: "Ana B", guideName: "Apple Name", names: names
        )
        #expect(sender == "Danny")
        #expect(send.senderName(viewerRole: .assistant, myRecordName: "_ana", myName: "Ana B") == "your guide")
    }

    @Test("Her rename reaches her old entries on the guide's devices; your own still read as you")
    func renameReachesOldEntries() throws {
        let guidesMac = RestockAuthor(role: .leadGuide, recordName: "_guide", names: names)
        #expect(guidesMac.reads(changedByID: "_ana", name: "Ana") == "Ana B")
        #expect(guidesMac.reads(changedByID: "_bea", name: "") == "Bea")
        #expect(guidesMac.reads(changedByID: "_cal", name: "Cal") == "Cal", "no row: the stamped name")
        #expect(guidesMac.reads(changedByID: "_dee", name: "") == "an assistant")
        #expect(guidesMac.reads(changedByID: "_guide", name: "") == "You")

        let context = try CoreDataTestHelpers.makeContext()
        let hers = Support.mark(by: .assistant, id: "_ana", name: "Ana", in: context)
        let hersOnMac = AttendanceRules.markerName(
            for: hers, myRecordName: "_guide", myName: nil, guideName: "you", names: names
        )
        #expect(hersOnMac == "Ana B")
        let his = Support.mark(by: .leadGuide, id: "_guide", name: nil, in: context)
        let hisOnMac = AttendanceRules.markerName(
            for: his, myRecordName: "_guide", myName: nil, guideName: "you", names: names
        )
        #expect(hisOnMac == "you")

        let herSend = Support.send(by: .assistant, id: "_ana", name: "Ana", in: context)
        let herSendOnMac = herSend.senderName(viewerRole: .leadGuide, myRecordName: "_guide", myName: nil, names: names)
        #expect(herSendOnMac == "Ana B")
        let hisSend = Support.send(by: .leadGuide, id: "_guide", name: nil, in: context)
        let hisSendOnMac = hisSend.senderName(viewerRole: .leadGuide, myRecordName: "_guide", myName: nil, names: names)
        #expect(hisSendOnMac == "you")

        // On her phone: her own change is hers, and Bea goes by her current name.
        let herPhone = RestockAuthor(role: .assistant, recordName: "_ana", name: "Ana B", names: names)
        #expect(herPhone.reads(changedByID: "_ana", name: "Ana") == "You")
        #expect(herPhone.reads(changedByID: "_bea", name: "") == "Bea")
        let beasMark = Support.mark(by: .assistant, id: "_bea", name: nil, in: context)
        let beasOnHerPhone = AttendanceRules.markerName(
            for: beasMark, myRecordName: "_ana", myName: "Ana B", guideName: nil, viewerRole: .assistant, names: names
        )
        #expect(beasOnHerPhone == "Bea")
    }

    @Test("An unnamed assistant's mark reads 'an assistant' on the guide's screens, 'another assistant' on hers")
    func unnamedAssistantMark() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let dees = Support.mark(by: .assistant, id: "_dee", name: nil, in: context)
        let onMac = AttendanceRules.markerName(
            for: dees, myRecordName: "_guide", myName: nil, guideName: "you", names: names
        )
        #expect(onMac == "an assistant")
        let onHerPhone = AttendanceRules.markerName(
            for: dees, myRecordName: "_ana", myName: "Ana B", guideName: nil, viewerRole: .assistant, names: names
        )
        #expect(onHerPhone == "another assistant")
    }

    @Test("A staple's history names each person as they go by now; old lines read as written")
    func stapleHistoryLines() {
        // Stamped "Ana" back then, "Ana B" now; the guide's lines carry no name.
        #expect(RestockHistoryLine.text(reason: "Low · Ana", changedByID: "_ana", names: names) == "Low · Ana B")
        #expect(RestockHistoryLine.text(reason: "Out", changedByID: "_guide", names: names) == "Out · Danny")
        // No row for her: the stamped name stands.
        #expect(RestockHistoryLine.text(reason: "Low · Cal", changedByID: "_cal", names: names) == "Low · Cal")
        // Before schema 17 (no ID), or a stand-in: as written.
        #expect(RestockHistoryLine.text(reason: "Low · Ana", changedByID: "", names: names) == "Low · Ana")
        #expect(RestockHistoryLine.text(reason: "Low · Ana", changedByID: nil, names: names) == "Low · Ana")
        #expect(
            RestockHistoryLine.text(reason: "Restocked", changedByID: CKCurrentUserDefaultName, names: names)
                == "Restocked"
        )
        // A counted change's reason stays; an empty one stays empty for the sheet to word.
        #expect(RestockHistoryLine.text(reason: "Used for art", changedByID: nil, names: names) == "Used for art")
        #expect(RestockHistoryLine.text(reason: " ", changedByID: "_ana", names: names).isEmpty)
    }

    @Test("Before a device knows its record name, its own stamps still read as its own")
    func ownStampsWithoutRecordNameYet() {
        let newIPad = RestockAuthor(role: .leadGuide, names: names)
        #expect(newIPad.reads(changedByID: "_guide", name: "") == "You")
        #expect(newIPad.reads(changedByID: "_ana", name: "Ana") == "Ana B")
        let herNewPhone = RestockAuthor(role: .assistant, name: "Ana B", names: names)
        #expect(herNewPhone.reads(changedByID: "_ana", name: "") == "You")
    }
}
