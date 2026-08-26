import CoreData
import Foundation
import Testing
@testable import Maria_s_Notebook

/// A wrong lesson → album link silently points the guide at the write-up for
/// a different level's lesson, so the scoring and the accept/undo path both
/// need to behave predictably.
@Suite("Lesson to album matching")
@MainActor
final class LessonAlbumMatcherTests {

    private func makeContext() throws -> NSManagedObjectContext {
        try CoreDataTestHelpers.makeInMemoryStack().viewContext
    }

    // MARK: Title scoring

    @Test("An exact title match scores 1")
    func identicalTitlesScorePerfectly() {
        #expect(LessonAlbumMatcher.titleSimilarity(
            "Parts of the Flower", "Parts of the Flower") == 1)
    }

    @Test("Case, accents, and punctuation don't matter")
    func scoringIsFolded() {
        #expect(LessonAlbumMatcher.titleSimilarity(
            "PARTS OF THE FLOWER", "parts of the flower.") == 1)
    }

    @Test("Filler words don't carry the match on their own")
    func fillerWordsAreIgnored() {
        // Nothing in common but "the"/"of" — must not read as a match.
        #expect(LessonAlbumMatcher.titleSimilarity("The Story of Numbers", "The Study of Rocks") < 0.5)
    }

    @Test("Reordered titles still match")
    func wordOrderDoesNotMatter() {
        let score = LessonAlbumMatcher.titleSimilarity(
            "Multiplication with the Checkerboard", "Checkerboard, Multiplication with")
        #expect(score == 1)
    }

    @Test("Extra qualifying words in the album outline still score well")
    func extraOutlineWordsAreTolerated() {
        let score = LessonAlbumMatcher.titleSimilarity(
            "The Checkerboard", "Checkerboard — First Presentation")
        #expect(score > LessonAlbumMatcher.suggestThreshold)
    }

    @Test("Unrelated lessons score zero")
    func unrelatedTitlesScoreZero() {
        #expect(LessonAlbumMatcher.titleSimilarity("Parts of the Flower", "Bead Chains") == 0)
    }

    @Test("An empty title never matches")
    func emptyTitleScoresZero() {
        #expect(LessonAlbumMatcher.titleSimilarity("", "Parts of the Flower") == 0)
    }

    // MARK: Link storage

    @Test("A lesson with no album link reads as unlinked")
    func unlinkedLessonHasNoLink() throws {
        let context = try makeContext()
        let lesson = CDLesson(context: context)
        lesson.name = "Parts of the Flower"
        #expect(lesson.albumLink == nil)
    }

    @Test("Accepting a candidate stores the album, page, outline title, and confidence")
    func applyStoresTheLink() throws {
        let context = try makeContext()
        let lesson = CDLesson(context: context)
        lesson.name = "Parts of the Flower"
        context.safeSave()
        let lessonID = try #require(lesson.id)

        let candidate = LessonAlbumMatcher.Candidate(
            lessonID: lessonID,
            lessonName: "Parts of the Flower",
            lessonArea: "Biology",
            albumID: "Biology Album.pdf",
            albumTitle: "Biology",
            subject: .biology,
            pageIndex: 41,
            outlineTitle: "Parts of the Flower",
            score: 0.93)

        LessonAlbumMatcher.apply([candidate], in: context)

        let link = try #require(lesson.albumLink)
        #expect(link.albumID == "Biology Album.pdf")
        #expect(link.pageIndex == 41)
        #expect(link.lessonTitle == "Parts of the Flower")
        #expect(lesson.albumLinkConfidence == 0.93)
    }

    @Test("Removing a link clears the confidence too")
    func unlinkClearsEverything() throws {
        let context = try makeContext()
        let lesson = CDLesson(context: context)
        lesson.name = "Parts of the Flower"
        lesson.albumLink = AlbumLink(albumID: "Biology Album.pdf", pageIndex: 41,
                                     lessonTitle: "Parts of the Flower")
        lesson.albumLinkConfidence = 0.93
        context.safeSave()

        LessonAlbumMatcher.unlink(lesson, in: context)

        #expect(lesson.albumLink == nil)
        #expect(lesson.albumLinkConfidence == 0)
    }

    @Test("Confidence decides whether a candidate is pre-accepted for the guide")
    func confidenceGatesAutoSelection() throws {
        let context = try makeContext()
        let lesson = CDLesson(context: context)
        context.safeSave()
        let lessonID = try #require(lesson.id)

        func candidate(score: Double) -> LessonAlbumMatcher.Candidate {
            LessonAlbumMatcher.Candidate(
                lessonID: lessonID, lessonName: "L", lessonArea: "Biology",
                albumID: "Biology Album.pdf", albumTitle: "Biology", subject: .biology,
                pageIndex: 1, outlineTitle: "L", score: score)
        }

        #expect(candidate(score: LessonAlbumMatcher.autoLinkThreshold).isConfident)
        #expect(candidate(score: 0.99).isConfident)
        #expect(!candidate(score: LessonAlbumMatcher.autoLinkThreshold - 0.01).isConfident)
    }

    // MARK: Fetching linked lessons

    @Test("Lessons in an album come back in page order, and only that album's")
    func lessonsInAlbumIsScopedAndSorted() throws {
        let context = try makeContext()
        for (name, album, page) in [("Seed", "Biology Album.pdf", 60),
                                    ("Flower", "Biology Album.pdf", 41),
                                    ("Checkerboard", "Math Album.pdf", 12)] {
            let lesson = CDLesson(context: context)
            lesson.name = name
            lesson.albumLink = AlbumLink(albumID: album, pageIndex: page, lessonTitle: name)
        }
        context.safeSave()

        let biology = CDLesson.lessonsInAlbum("Biology Album.pdf", context: context)
        #expect(biology.map(\.name) == ["Flower", "Seed"])
    }
}
