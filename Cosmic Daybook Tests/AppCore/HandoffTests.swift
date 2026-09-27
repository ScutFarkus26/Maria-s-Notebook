import Foundation
import Testing
@testable import CosmicDaybook

/// Pins what Handoff carries between devices and where it lands.
@MainActor
@Suite("Handoff")
struct HandoffTests {

    @Test("A student, a lesson and an album page each come back as the destination they described")
    func roundTrip() throws {
        let studentID = UUID()
        let student = NSUserActivity(activityType: Handoff.ActivityType.student)
        Handoff.describeStudent(student, id: studentID, name: "Maya S")
        #expect(Handoff.destination(from: student) == .student(studentID))
        #expect(student.title == "Maya S")

        let lessonID = UUID()
        let lesson = NSUserActivity(activityType: Handoff.ActivityType.lesson)
        Handoff.describeLesson(lesson, id: lessonID, name: "Golden Bead Addition")
        #expect(Handoff.destination(from: lesson) == .lesson(lessonID))

        let page = NSUserActivity(activityType: Handoff.ActivityType.albumPage)
        Handoff.describeAlbumPage(page, albumID: "Biology Album.pdf", title: "Biology", pageIndex: 41)
        #expect(Handoff.destination(from: page) == .albumPage(albumID: "Biology Album.pdf", pageIndex: 41))
        #expect(page.title == "Biology, page 42")
    }

    @Test("Handoff only: never search, Siri suggestions or public indexing, since titles name children")
    func eligibility() {
        let activity = NSUserActivity(activityType: Handoff.ActivityType.student)
        Handoff.describeStudent(activity, id: UUID(), name: "Maya S")
        #expect(activity.isEligibleForHandoff)
        #expect(!activity.isEligibleForSearch)
        #if !os(macOS)
        #expect(!activity.isEligibleForPrediction)
        #endif
        #expect(!activity.isEligibleForPublicIndexing)
        #expect(activity.requiredUserInfoKeys == [Handoff.Key.id])
    }

    @Test("Malformed or foreign activities lead nowhere")
    func malformed() {
        let noID = NSUserActivity(activityType: Handoff.ActivityType.lesson)
        noID.userInfo = [Handoff.Key.id: "not a uuid"]
        #expect(Handoff.destination(from: noID) == nil)

        let badPage = NSUserActivity(activityType: Handoff.ActivityType.albumPage)
        badPage.userInfo = [Handoff.Key.album: "Biology Album.pdf", Handoff.Key.page: -1]
        #expect(Handoff.destination(from: badPage) == nil)

        let foreign = NSUserActivity(activityType: "com.example.other")
        foreign.userInfo = [Handoff.Key.id: UUID().uuidString]
        #expect(Handoff.destination(from: foreign) == nil)
    }

    @Test("Every activity type is declared in NSUserActivityTypes, or Handoff never offers it")
    func declaredInInfoPlist() throws {
        let declared = try #require(Bundle.main.object(forInfoDictionaryKey: "NSUserActivityTypes") as? [String])
        #expect(Set(declared).isSuperset(of: [
            Handoff.ActivityType.student, Handoff.ActivityType.lesson, Handoff.ActivityType.albumPage
        ]))
    }

    @Test("A continued lesson or album page goes through the same router requests the app's own jumps use")
    func routing() {
        let router = AppRouter()
        let lessonID = UUID()
        router.continueHandoff(to: .lesson(lessonID))
        #expect(router.pendingLessonID == lessonID)

        router.continueHandoff(to: .albumPage(albumID: "Biology Album.pdf", pageIndex: 3))
        #expect(router.albumPageRequest?.albumID == "Biology Album.pdf")
        #expect(router.albumPageRequest?.pageIndex == 3)

        let studentID = UUID()
        router.continueHandoff(to: .student(studentID))
        #expect(router.navigationDestination == .openStudentDetail(studentID))
    }
}
