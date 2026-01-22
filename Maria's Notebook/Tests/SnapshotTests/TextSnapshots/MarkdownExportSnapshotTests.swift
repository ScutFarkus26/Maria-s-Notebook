#if canImport(Testing)
import Testing
import Foundation
import SwiftData
@testable import Maria_s_Notebook

/// Snapshot tests for markdown export formatting.
/// Tests verify the markdown output structure for Community Topics.
@Suite("Markdown Export Snapshots")
struct MarkdownExportSnapshotTests {

    // MARK: - Topic Export Tests

    @Test("Topic full content")
    @MainActor
    func topic_fullContent() throws {
        let container = try makeSnapshotTestContainer()

        let topic = CommunityTopic(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            title: "Classroom Noise Levels",
            issueDescription: "Students have reported difficulty concentrating during work periods due to excessive noise from other areas.",
            createdAt: SnapshotDates.reference,
            addressedDate: SnapshotDates.date(year: 2025, month: 1, day: 20),
            resolution: "Implemented quiet zones during focused work time. Teachers will signal transitions with a bell."
        )
        topic.tags = ["classroom", "environment", "focus"]

        // Add proposed solutions
        let solution1 = ProposedSolution(
            id: UUID(uuidString: "aaaaaaaa-1111-1111-1111-111111111111")!,
            title: "Quiet Zones",
            details: "Designate specific areas for silent work",
            proposedBy: "Ms. Smith",
            createdAt: SnapshotDates.reference,
            isAdopted: true,
            topic: topic
        )
        let solution2 = ProposedSolution(
            id: UUID(uuidString: "bbbbbbbb-1111-1111-1111-111111111111")!,
            title: "Sound Barriers",
            details: "Add acoustic panels between areas",
            proposedBy: "Mr. Jones",
            createdAt: SnapshotDates.reference,
            isAdopted: false,
            topic: topic
        )
        topic.proposedSolutions = [solution1, solution2]

        container.mainContext.insert(topic)
        try container.mainContext.save()

        let markdown = MarkdownExporter.markdown(for: topic)
        #expect(markdown.contains("Classroom Noise Levels"))
        assertTextSnapshot(markdown, named: "fullContent")
    }

    @Test("Topic title only")
    @MainActor
    func topic_titleOnly() throws {
        let container = try makeSnapshotTestContainer()

        let topic = CommunityTopic(
            id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            title: "New Topic",
            issueDescription: "",
            createdAt: SnapshotDates.reference,
            resolution: ""
        )

        container.mainContext.insert(topic)
        try container.mainContext.save()

        let markdown = MarkdownExporter.markdown(for: topic)
        #expect(markdown.contains("New Topic"))
        assertTextSnapshot(markdown, named: "titleOnly")
    }

    @Test("Topic with issue only")
    @MainActor
    func topic_withIssueOnly() throws {
        let container = try makeSnapshotTestContainer()

        let topic = CommunityTopic(
            id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
            title: "Unresolved Issue",
            issueDescription: "The playground equipment needs maintenance. Several swings have broken chains.",
            createdAt: SnapshotDates.reference,
            resolution: ""
        )

        container.mainContext.insert(topic)
        try container.mainContext.save()

        let markdown = MarkdownExporter.markdown(for: topic)
        #expect(markdown.contains("playground equipment"))
        assertTextSnapshot(markdown, named: "withIssueOnly")
    }

    @Test("Topic with resolution only")
    @MainActor
    func topic_withResolutionOnly() throws {
        let container = try makeSnapshotTestContainer()

        let topic = CommunityTopic(
            id: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!,
            title: "Resolved Topic",
            issueDescription: "",
            createdAt: SnapshotDates.reference,
            addressedDate: SnapshotDates.reference,
            resolution: "Issue was addressed through staff training and new protocols."
        )

        container.mainContext.insert(topic)
        try container.mainContext.save()

        let markdown = MarkdownExporter.markdown(for: topic)
        #expect(markdown.contains("staff training"))
        assertTextSnapshot(markdown, named: "withResolutionOnly")
    }

    @Test("Topic with multiple solutions")
    @MainActor
    func topic_withMultipleSolutions() throws {
        let container = try makeSnapshotTestContainer()

        let topic = CommunityTopic(
            id: UUID(uuidString: "55555555-5555-5555-5555-555555555555")!,
            title: "Lunch Line Congestion",
            issueDescription: "Students are waiting too long in the lunch line.",
            createdAt: SnapshotDates.reference,
            resolution: ""
        )

        let solutions = [
            ProposedSolution(
                id: UUID(uuidString: "aaaaaaaa-5555-5555-5555-555555555555")!,
                title: "Staggered Times",
                details: "Different grades eat at different times",
                proposedBy: "Parent Council",
                isAdopted: true,
                topic: topic
            ),
            ProposedSolution(
                id: UUID(uuidString: "bbbbbbbb-5555-5555-5555-555555555555")!,
                title: "Additional Line",
                details: "Open second serving line",
                proposedBy: "Cafeteria Staff",
                isAdopted: true,
                topic: topic
            ),
            ProposedSolution(
                id: UUID(uuidString: "cccccccc-5555-5555-5555-555555555555")!,
                title: "Pre-ordering",
                details: "Students order meals in advance",
                proposedBy: "Admin",
                isAdopted: false,
                topic: topic
            ),
        ]
        topic.proposedSolutions = solutions

        container.mainContext.insert(topic)
        try container.mainContext.save()

        let markdown = MarkdownExporter.markdown(for: topic)
        #expect(markdown.contains("Staggered Times"))
        assertTextSnapshot(markdown, named: "withMultipleSolutions")
    }

    @Test("Topic solution with details only")
    @MainActor
    func topic_solutionWithDetailsOnly() throws {
        let container = try makeSnapshotTestContainer()

        let topic = CommunityTopic(
            id: UUID(uuidString: "66666666-6666-6666-6666-666666666666")!,
            title: "Parking Issue",
            issueDescription: "Morning drop-off is chaotic.",
            createdAt: SnapshotDates.reference,
            resolution: ""
        )

        // Solution with no title, only details
        let solution = ProposedSolution(
            id: UUID(uuidString: "aaaaaaaa-6666-6666-6666-666666666666")!,
            title: "",
            details: "Add traffic cones to create dedicated lanes",
            proposedBy: "",
            isAdopted: false,
            topic: topic
        )
        topic.proposedSolutions = [solution]

        container.mainContext.insert(topic)
        try container.mainContext.save()

        let markdown = MarkdownExporter.markdown(for: topic)
        #expect(markdown.contains("traffic cones"))
        assertTextSnapshot(markdown, named: "solutionWithDetailsOnly")
    }

    @Test("Topic with meeting notes")
    @MainActor
    func topic_withMeetingNotes() throws {
        let container = try makeSnapshotTestContainer()

        let topic = CommunityTopic(
            id: UUID(uuidString: "77777777-7777-7777-7777-777777777777")!,
            title: "Field Trip Planning",
            issueDescription: "Need to decide on spring field trip destination.",
            createdAt: SnapshotDates.reference,
            resolution: "Zoo selected as destination for May 15th."
        )

        // Create notes linked to the topic via relationship
        let note1 = Note(
            id: UUID(uuidString: "aaaaaaaa-7777-7777-7777-777777777777")!,
            body: "Zoo is educational and age-appropriate",
            scope: .all
        )
        note1.reporterName = "Ms. Smith"
        note1.createdAt = SnapshotDates.date(year: 2025, month: 1, day: 10)
        note1.communityTopic = topic

        let note2 = Note(
            id: UUID(uuidString: "bbbbbbbb-7777-7777-7777-777777777777")!,
            body: "Budget allows for bus transportation",
            scope: .all
        )
        note2.reporterName = "Principal"
        note2.createdAt = SnapshotDates.date(year: 2025, month: 1, day: 11)
        note2.communityTopic = topic

        let note3 = Note(
            id: UUID(uuidString: "cccccccc-7777-7777-7777-777777777777")!,
            body: "Parent volunteers confirmed",
            scope: .all
        )
        note3.reporterName = ""
        note3.createdAt = SnapshotDates.date(year: 2025, month: 1, day: 12)
        note3.communityTopic = topic

        topic.unifiedNotes = [note1, note2, note3]

        container.mainContext.insert(topic)
        try container.mainContext.save()

        let markdown = MarkdownExporter.markdown(for: topic)
        #expect(markdown.contains("Zoo"))
        assertTextSnapshot(markdown, named: "withMeetingNotes")
    }

    @Test("Topic comprehensive")
    @MainActor
    func topic_comprehensive() throws {
        let container = try makeSnapshotTestContainer()

        let topic = CommunityTopic(
            id: UUID(uuidString: "88888888-8888-8888-8888-888888888888")!,
            title: "Technology Policy Update",
            issueDescription: "Current device policy is outdated. Students need clearer guidelines on: When devices can be used, Appropriate content, Consequences for misuse",
            createdAt: SnapshotDates.reference,
            addressedDate: SnapshotDates.date(year: 2025, month: 1, day: 20),
            resolution: "New policy approved with key points: Devices only during designated times, Educational apps only during school hours, Three-strike system for violations"
        )
        topic.tags = ["technology", "policy", "students"]

        let solutions = [
            ProposedSolution(
                title: "Device-Free Zones",
                details: "No devices in hallways and cafeteria",
                proposedBy: "Teacher Committee",
                isAdopted: true,
                topic: topic
            ),
            ProposedSolution(
                title: "Student Agreement",
                details: "Signed contract at year start",
                proposedBy: "Admin",
                isAdopted: true,
                topic: topic
            ),
        ]
        topic.proposedSolutions = solutions

        let note1 = Note(body: "Research shows reduced device time improves focus", scope: .all)
        note1.reporterName = "Counselor"
        note1.createdAt = SnapshotDates.date(year: 2025, month: 1, day: 5)
        note1.communityTopic = topic

        let note2 = Note(body: "Parents support clearer guidelines", scope: .all)
        note2.reporterName = "PTA Rep"
        note2.createdAt = SnapshotDates.date(year: 2025, month: 1, day: 6)
        note2.communityTopic = topic

        topic.unifiedNotes = [note1, note2]

        container.mainContext.insert(topic)
        try container.mainContext.save()

        let markdown = MarkdownExporter.markdown(for: topic)
        #expect(markdown.contains("Technology Policy"))
        assertTextSnapshot(markdown, named: "comprehensive")
    }
}

#endif
