#if canImport(Testing)
import Testing
import Foundation
@testable import Maria_s_Notebook

@Suite("FollowUpInboxItem Tests")
struct FollowUpInboxItemTests {

    // MARK: - Kind Tests

    @Test("Kind.lessonFollowUp has correct label")
    func kindLessonFollowUpLabel() {
        let kind = FollowUpInboxItem.Kind.lessonFollowUp

        #expect(kind.label == "Lesson")
    }

    @Test("Kind.workCheckIn has correct label")
    func kindWorkCheckInLabel() {
        let kind = FollowUpInboxItem.Kind.workCheckIn

        #expect(kind.label == "Check-In")
    }

    @Test("Kind.workReview has correct label")
    func kindWorkReviewLabel() {
        let kind = FollowUpInboxItem.Kind.workReview

        #expect(kind.label == "Review")
    }

    @Test("Kind.lessonFollowUp has correct icon")
    func kindLessonFollowUpIcon() {
        let kind = FollowUpInboxItem.Kind.lessonFollowUp

        #expect(kind.icon == "text.book.closed")
    }

    @Test("Kind.workCheckIn has correct icon")
    func kindWorkCheckInIcon() {
        let kind = FollowUpInboxItem.Kind.workCheckIn

        #expect(kind.icon == "checklist")
    }

    @Test("Kind.workReview has correct icon")
    func kindWorkReviewIcon() {
        let kind = FollowUpInboxItem.Kind.workReview

        #expect(kind.icon == "eye")
    }

    // MARK: - Bucket Tests

    @Test("Bucket.overdue has correct rawValue")
    func bucketOverdueRawValue() {
        let bucket = FollowUpInboxItem.Bucket.overdue

        #expect(bucket.rawValue == 0)
    }

    @Test("Bucket.dueToday has correct rawValue")
    func bucketDueTodayRawValue() {
        let bucket = FollowUpInboxItem.Bucket.dueToday

        #expect(bucket.rawValue == 1)
    }

    @Test("Bucket.inbox has correct rawValue")
    func bucketInboxRawValue() {
        let bucket = FollowUpInboxItem.Bucket.inbox

        #expect(bucket.rawValue == 2)
    }

    @Test("Bucket.upcoming has correct rawValue")
    func bucketUpcomingRawValue() {
        let bucket = FollowUpInboxItem.Bucket.upcoming

        #expect(bucket.rawValue == 3)
    }

    @Test("Bucket.overdue title is 'Overdue'")
    func bucketOverdueTitle() {
        let bucket = FollowUpInboxItem.Bucket.overdue

        #expect(bucket.title == "Overdue")
    }

    @Test("Bucket.dueToday title is 'Due Today'")
    func bucketDueTodayTitle() {
        let bucket = FollowUpInboxItem.Bucket.dueToday

        #expect(bucket.title == "Due Today")
    }

    @Test("Bucket.inbox title is 'Needs Scheduling'")
    func bucketInboxTitle() {
        let bucket = FollowUpInboxItem.Bucket.inbox

        #expect(bucket.title == "Needs Scheduling")
    }

    @Test("Bucket.upcoming title is 'Upcoming'")
    func bucketUpcomingTitle() {
        let bucket = FollowUpInboxItem.Bucket.upcoming

        #expect(bucket.title == "Upcoming")
    }

    // MARK: - Bucket Comparison Tests

    @Test("Bucket comparison: overdue < dueToday")
    func bucketComparisonOverdueLessThanDueToday() {
        #expect(FollowUpInboxItem.Bucket.overdue < FollowUpInboxItem.Bucket.dueToday)
    }

    @Test("Bucket comparison: dueToday < inbox")
    func bucketComparisonDueTodayLessThanInbox() {
        #expect(FollowUpInboxItem.Bucket.dueToday < FollowUpInboxItem.Bucket.inbox)
    }

    @Test("Bucket comparison: inbox < upcoming")
    func bucketComparisonInboxLessThanUpcoming() {
        #expect(FollowUpInboxItem.Bucket.inbox < FollowUpInboxItem.Bucket.upcoming)
    }

    @Test("Bucket comparison: overdue is smallest")
    func bucketComparisonOverdueSmallest() {
        let all = FollowUpInboxItem.Bucket.allCases
        let smallest = all.min()

        #expect(smallest == .overdue)
    }

    @Test("Bucket comparison: upcoming is largest")
    func bucketComparisonUpcomingLargest() {
        let all = FollowUpInboxItem.Bucket.allCases
        let largest = all.max()

        #expect(largest == .upcoming)
    }

    // MARK: - FollowUpInboxItem Creation Tests

    @Test("FollowUpInboxItem stores all properties correctly")
    func itemStoresProperties() {
        let item = FollowUpInboxItem(
            id: "test:123",
            underlyingID: UUID(),
            childID: UUID(),
            childName: "Test Child",
            title: "Test Lesson",
            kind: .lessonFollowUp,
            statusText: "Overdue - 10d",
            ageDays: 10,
            bucket: .overdue
        )

        #expect(item.id == "test:123")
        #expect(item.childName == "Test Child")
        #expect(item.title == "Test Lesson")
        #expect(item.kind == .lessonFollowUp)
        #expect(item.statusText == "Overdue - 10d")
        #expect(item.ageDays == 10)
        #expect(item.bucket == .overdue)
    }

    @Test("FollowUpInboxItem allows nil childID")
    func itemAllowsNilChildID() {
        let item = FollowUpInboxItem(
            id: "test:123",
            underlyingID: UUID(),
            childID: nil,
            childName: "Group",
            title: "Group Lesson",
            kind: .lessonFollowUp,
            statusText: "Due Today",
            ageDays: 7,
            bucket: .dueToday
        )

        #expect(item.childID == nil)
        #expect(item.childName == "Group")
    }

    // MARK: - sortKey Tests

    @Test("sortKey includes bucket priority")
    func sortKeyIncludesBucket() {
        let overdueItem = FollowUpInboxItem(
            id: "test:1",
            underlyingID: UUID(),
            childID: nil,
            childName: "Alice",
            title: "Lesson",
            kind: .lessonFollowUp,
            statusText: "",
            ageDays: 10,
            bucket: .overdue
        )

        let upcomingItem = FollowUpInboxItem(
            id: "test:2",
            underlyingID: UUID(),
            childID: nil,
            childName: "Alice",
            title: "Lesson",
            kind: .lessonFollowUp,
            statusText: "",
            ageDays: 10,
            bucket: .upcoming
        )

        // Overdue should sort before upcoming
        #expect(overdueItem.sortKey < upcomingItem.sortKey)
    }

    @Test("sortKey sorts by age within same bucket")
    func sortKeyByAgeWithinBucket() {
        let olderItem = FollowUpInboxItem(
            id: "test:1",
            underlyingID: UUID(),
            childID: nil,
            childName: "Alice",
            title: "Lesson",
            kind: .lessonFollowUp,
            statusText: "",
            ageDays: 15,
            bucket: .overdue
        )

        let newerItem = FollowUpInboxItem(
            id: "test:2",
            underlyingID: UUID(),
            childID: nil,
            childName: "Alice",
            title: "Lesson",
            kind: .lessonFollowUp,
            statusText: "",
            ageDays: 8,
            bucket: .overdue
        )

        // Higher age should sort first (reversed for urgency)
        #expect(olderItem.sortKey < newerItem.sortKey)
    }

    @Test("sortKey sorts by child name within same bucket and age")
    func sortKeyByChildName() {
        let aliceItem = FollowUpInboxItem(
            id: "test:1",
            underlyingID: UUID(),
            childID: nil,
            childName: "Alice",
            title: "Lesson",
            kind: .lessonFollowUp,
            statusText: "",
            ageDays: 10,
            bucket: .overdue
        )

        let bobItem = FollowUpInboxItem(
            id: "test:2",
            underlyingID: UUID(),
            childID: nil,
            childName: "Bob",
            title: "Lesson",
            kind: .lessonFollowUp,
            statusText: "",
            ageDays: 10,
            bucket: .overdue
        )

        // Alice should sort before Bob
        #expect(aliceItem.sortKey < bobItem.sortKey)
    }

    @Test("sortKey is case insensitive for child name")
    func sortKeyCaseInsensitiveChildName() {
        let lowercaseItem = FollowUpInboxItem(
            id: "test:1",
            underlyingID: UUID(),
            childID: nil,
            childName: "alice",
            title: "Lesson",
            kind: .lessonFollowUp,
            statusText: "",
            ageDays: 10,
            bucket: .overdue
        )

        let uppercaseItem = FollowUpInboxItem(
            id: "test:2",
            underlyingID: UUID(),
            childID: nil,
            childName: "ALICE",
            title: "Lesson",
            kind: .lessonFollowUp,
            statusText: "",
            ageDays: 10,
            bucket: .overdue
        )

        // Should sort the same (both lowercase in sortKey)
        #expect(lowercaseItem.sortKey == uppercaseItem.sortKey)
    }

    // MARK: - Equatable Tests

    @Test("FollowUpInboxItem equality based on all fields")
    func itemEquality() {
        let id = UUID()
        let childID = UUID()

        let item1 = FollowUpInboxItem(
            id: "test:123",
            underlyingID: id,
            childID: childID,
            childName: "Alice",
            title: "Lesson",
            kind: .lessonFollowUp,
            statusText: "Status",
            ageDays: 10,
            bucket: .overdue
        )

        let item2 = FollowUpInboxItem(
            id: "test:123",
            underlyingID: id,
            childID: childID,
            childName: "Alice",
            title: "Lesson",
            kind: .lessonFollowUp,
            statusText: "Status",
            ageDays: 10,
            bucket: .overdue
        )

        #expect(item1 == item2)
    }

    @Test("FollowUpInboxItem inequality when ID differs")
    func itemInequalityDifferentID() {
        let item1 = FollowUpInboxItem(
            id: "test:123",
            underlyingID: UUID(),
            childID: nil,
            childName: "Alice",
            title: "Lesson",
            kind: .lessonFollowUp,
            statusText: "Status",
            ageDays: 10,
            bucket: .overdue
        )

        let item2 = FollowUpInboxItem(
            id: "test:456",
            underlyingID: UUID(),
            childID: nil,
            childName: "Alice",
            title: "Lesson",
            kind: .lessonFollowUp,
            statusText: "Status",
            ageDays: 10,
            bucket: .overdue
        )

        #expect(item1 != item2)
    }
}

@Suite("FollowUpInboxEngine.Constants Tests")
struct FollowUpInboxEngineConstantsTests {

    @Test("Default lessonFollowUpOverdueDays is 7")
    func defaultLessonOverdueDays() {
        let constants = FollowUpInboxEngine.Constants()

        #expect(constants.lessonFollowUpOverdueDays == 7)
    }

    @Test("Default workStaleOverdueDays is 5")
    func defaultWorkStaleOverdueDays() {
        let constants = FollowUpInboxEngine.Constants()

        #expect(constants.workStaleOverdueDays == 5)
    }

    @Test("Default reviewStaleDays is 3")
    func defaultReviewStaleDays() {
        let constants = FollowUpInboxEngine.Constants()

        #expect(constants.reviewStaleDays == 3)
    }

    @Test("Constants can be customized")
    func customConstants() {
        var constants = FollowUpInboxEngine.Constants()
        constants.lessonFollowUpOverdueDays = 14
        constants.workStaleOverdueDays = 10
        constants.reviewStaleDays = 7

        #expect(constants.lessonFollowUpOverdueDays == 14)
        #expect(constants.workStaleOverdueDays == 10)
        #expect(constants.reviewStaleDays == 7)
    }
}
#endif
