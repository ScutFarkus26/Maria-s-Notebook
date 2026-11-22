import Foundation
import SwiftUI
import Testing
@testable import CosmicDaybook

/// Pictures of the lesson loop's screens, drawn from the real views with
/// `ImageRenderer` (`LessonTimePictures`): Today's Next card with "Given —
/// Quick Note" and its "Still practicing" line, the present-a-lesson picker's
/// rows and the Class Grid's Groups button. Saved when the run asks
/// (`TEST_RUNNER_LESSON_TIME_SHOT_DIR`); the plan keeps them in
/// `docs/Pictures/Lesson loop/`.
///
/// Not pictured: the quick note itself. `ImageRenderer` draws its text field
/// (and the lens's segmented picker) as a placeholder, so it is drawn here
/// only to check it renders, never saved.
extension LessonLoopScreenTests {

    /// One picture: its file name, the view and its width.
    struct Shot {
        let name: String
        let view: AnyView
        let width: CGFloat
    }

    @Test("Pictures: the Next card, the quick note, the picker rows and the Groups button")
    func pictures() throws {
        let shots = [
            Shot(name: "today-next-card-ipad", view: AnyView(nextCard), width: 620),
            Shot(name: "today-next-card-iphone", view: AnyView(nextCard), width: 375),
            Shot(name: "picker-rows", view: AnyView(pickerRows), width: 340),
            Shot(name: "class-grid-groups-button", view: AnyView(groupsButton), width: 200)
        ]
        #expect((LessonTimePictures.png(quickNote, scheme: .light, width: 440)?.count ?? 0) > 1_000)
        for scheme in [ColorScheme.dark, .light] {
            for shot in shots {
                let png = try LessonTimePictures.save(shot.view, named: shot.name, scheme: scheme, width: shot.width)
                #expect((png?.count ?? 0) > 1_000)
            }
        }
    }

    private var nextCard: some View {
        LessonListRow(
            lessonName: "Stamp Game Addition",
            startTime: nil,
            children: [
                .init(id: UUID(), name: "Maya S"), .init(id: UUID(), name: "Theo L"),
                .init(id: UUID(), name: "Ora K", isAbsent: true)
            ],
            hereText: "2 of 3 here",
            isPresented: false,
            onPresent: {},
            presentShortcut: nil,
            onGivenQuickNote: {},
            stillPracticing: "Still practicing: Maya S (Bead Addition)"
        )
        .todayNextHighlight(true)
        .padding()
    }

    private var quickNote: some View {
        LessonQuickNoteForm(
            subject: LessonQuickNoteSubject(
                presentationID: UUID(), lessonName: "Stamp Game Addition",
                childrenLine: "Maya S and Theo L", status: "Given today"
            ),
            onSave: { _ in true },
            onCancel: {}
        )
    }

    private var pickerRows: some View {
        let candidate = { (first: String, last: String) in
            StudentPickerCandidate(
                id: UUID(), firstName: first, lastName: last, birthday: nil, level: .upper,
                status: .enrolled, departedOn: nil
            )
        }
        let rows = [
            StudentPickerRow(candidate: candidate("Ada", "Lin"), record: nil, block: nil, placement: .ready),
            StudentPickerRow(
                candidate: candidate("Ben", "Ross"), record: nil, block: nil, placement: .ready,
                checkFirstReason: "1 piece of work still open", practicing: "Practicing Bead Addition"
            ),
            StudentPickerRow(
                candidate: candidate("Cy", "Hale"), record: nil, block: nil, placement: .everyoneElse,
                practicing: "Practicing Bead Addition and 1 more"
            )
        ]
        return VStack(alignment: .leading, spacing: 4) {
            ForEach(rows) { row in
                StudentPickerRowView(row: row, isSelected: row.isReady, onToggle: {})
            }
        }
        .padding(12)
    }

    private var groupsButton: some View {
        ChecklistGroupsButton(area: "Math", sequences: ["Addition"])
            .buttonStyle(.bordered)
            .padding()
    }
}
