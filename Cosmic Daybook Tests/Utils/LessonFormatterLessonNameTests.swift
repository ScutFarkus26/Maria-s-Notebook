import Foundation
import Testing
@testable import CosmicDaybook

/// The name a work or presentation row shows for its lesson (2026-10-14
/// review): the lesson's name, else the row's own title, else a plain phrase.
/// It used to fall back to "Lesson " and the first six characters of the
/// lesson's id, which mean nothing on screen.
@Suite("Lesson name fallback")
struct LessonFormatterLessonNameTests {

    @Test("The lesson's own name comes first, trimmed")
    func lessonNameFirst() {
        #expect(LessonFormatter.lessonName(
            "  Golden Beads ", orRowTitle: "Bead practice", missing: LessonFormatter.untitledWork
        ) == "Golden Beads")
    }

    @Test("With no lesson name, the row's own title")
    func rowTitleNext() {
        #expect(LessonFormatter.lessonName(
            nil, orRowTitle: " Bead practice ", missing: LessonFormatter.untitledWork
        ) == "Bead practice")
        #expect(LessonFormatter.lessonName(
            "   ", orRowTitle: "Stamp Game", missing: LessonFormatter.untitledLesson
        ) == "Stamp Game")
    }

    @Test("With neither, a plain phrase")
    func plainPhraseLast() {
        let work = LessonFormatter.lessonName(nil, orRowTitle: "", missing: LessonFormatter.untitledWork)
        let lesson = LessonFormatter.lessonName("", missing: LessonFormatter.untitledLesson)
        #expect(work == "Untitled work")
        #expect(lesson == "Untitled lesson")
    }
}
