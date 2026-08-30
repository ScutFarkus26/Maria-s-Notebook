import Foundation
import Testing
@testable import Maria_s_Notebook

/// Suggested Next is the one pill whose contents come out of a score rather
/// than a filter, so the sentence under each card is the whole of the guide's
/// ability to check it. A sentence that says the wrong thing — or nothing —
/// is worse than no suggestion at all.
@Suite("Suggestion rationale wording")
struct SuggestionRationaleTests {

    @Test("A never-taught child leads the reason, without a day count")
    func neverTaughtLeads() {
        let rationale = SuggestionRationale(
            waitingChild: "Avigail G.",
            waitingSchoolDays: nil,
            inboxSchoolDays: 12
        )
        #expect(rationale.phrases.first == "Avigail G. has never been taught")
        #expect(!rationale.summary.contains("school days ago"))
    }

    @Test("A waiting child is worded the way the Waiting Longest rail words it")
    func waitPhrasingMatchesTheRail() {
        let many = SuggestionRationale(waitingChild: "Tzofia G.", waitingSchoolDays: 121)
        #expect(many.phrases.first == "Tzofia G. was last taught 121 school days ago")

        let one = SuggestionRationale(waitingChild: "Tzofia G.", waitingSchoolDays: 1)
        #expect(one.phrases.first == "Tzofia G. was last taught 1 school day ago")

        let today = SuggestionRationale(waitingChild: "Tzofia G.", waitingSchoolDays: 0)
        #expect(today.phrases.first == "Tzofia G. was taught today")
    }

    @Test("Children already booked replace the wait phrase rather than adding to it")
    func alreadyBookedReplacesTheWait() {
        let rationale = SuggestionRationale(
            waitingChild: "Etty K.",
            waitingSchoolDays: 40,
            everyoneAlreadyScheduled: true,
            inboxSchoolDays: 3
        )
        #expect(rationale.phrases == [
            "everyone here is already booked",
            "3 school days in the inbox"
        ])
    }

    @Test("A fresh lesson does not claim time in the inbox")
    func zeroInboxAgeIsSilent() {
        let rationale = SuggestionRationale(waitingChild: "Ora P.", waitingSchoolDays: 9)
        #expect(rationale.phrases == ["Ora P. was last taught 9 school days ago"])
    }

    @Test("Open work is mentioned only while it is still a reason to pick this")
    func openWorkIsMentionedOnlyWhenLow() {
        func phrases(openWork: Int) -> [String] {
            SuggestionRationale(fewestOpenWork: openWork).phrases
        }
        #expect(phrases(openWork: 0) == ["no open work"])
        #expect(phrases(openWork: 1) == ["1 open work item"])
        #expect(phrases(openWork: 2) == ["2 open work items"])
        #expect(phrases(openWork: 3).isEmpty)
    }

    @Test("Every factor reads as one line, strongest first")
    func fullSentenceOrder() {
        let rationale = SuggestionRationale(
            waitingChild: "Leshem P.",
            waitingSchoolDays: nil,
            inboxSchoolDays: 1,
            fewestOpenWork: 0,
            changesArea: true
        )
        #expect(rationale.summary ==
                "Leshem P. has never been taught · 1 school day in the inbox · no open work · a change of area")
    }

    @Test("A pick with no standout factor still says something")
    func emptyRationaleStillExplains() {
        #expect(SuggestionRationale().summary == "highest ranked of what is left")
    }
}
