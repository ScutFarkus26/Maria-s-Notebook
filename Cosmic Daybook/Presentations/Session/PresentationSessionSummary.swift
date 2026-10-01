import Foundation

/// "When you press Done": what Done will write, in plain words, before
/// anything is written.
nonisolated enum PresentationSessionSummary {
    struct Child: Equatable, Sendable {
        let id: UUID
        let name: String
    }

    struct Input: Sendable {
        let children: [Child]
        /// Only the children whose decision changes.
        let pending: [UUID: CaptureFollowUp]
        /// Every child's decision.
        let decisions: [UUID: CaptureFollowUp]
        let checkIn: PresentationCheckIn
        let checkInChanged: Bool
        let noteCount: Int
        let lessonName: String
        let nextLessonName: String?
    }

    static func lines(_ input: Input) -> [String] {
        var lines: [String] = []
        func names(_ choice: CaptureFollowUp) -> [String] {
            input.children.filter { input.pending[$0.id] == choice }.map(\.name)
        }

        let practice = names(.practice)
        if !practice.isEmpty {
            lines.append("Practice work for \(list(practice)) in Children Working — “Practice: \(input.lessonName)”")
        }
        let followUp = names(.followUpWork)
        if !followUp.isEmpty {
            lines.append("Follow-up work for \(list(followUp)) — “Follow up: \(input.lessonName)”")
        }

        let working = input.children.filter { input.decisions[$0.id]?.createsWork == true }.map(\.name)
        let newWork = !practice.isEmpty || !followUp.isEmpty
        if !working.isEmpty, newWork || input.checkInChanged {
            if let day = input.checkIn.day {
                let date = day.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
                lines.append("A check-in on \(date) for \(list(working))")
            } else if newWork {
                lines.append("No check-in date: the work stays in view for the next work cycle")
            }
        }

        let represent = names(.represent)
        if !represent.isEmpty {
            lines.append("\(list(represent)) will see it again: a re-presentation goes On Deck")
        }
        let ready = names(.readyForNextLesson)
        if !ready.isEmpty {
            let subject = "\(list(ready)) \(ready.count == 1 ? "is" : "are")"
            if let next = input.nextLessonName {
                lines.append("\(subject) ready for the next lesson: \(next) goes On Deck")
            } else {
                lines.append("\(subject) confirmed ready for the next lesson")
            }
        }
        let watching = names(.continueObserving)
        if !watching.isEmpty {
            lines.append("\(list(watching)) \(watching.count == 1 ? "stays" : "stay") on your Following list")
        }

        if input.noteCount > 0 {
            let count = input.noteCount == 1 ? "1 note" : "\(input.noteCount) notes"
            lines.append("\(count), filed on this presentation")
        }
        return lines
    }

    /// "Maya", "Leo and Maya", "Ava, Leo and Maya".
    static func list(_ names: [String]) -> String {
        switch names.count {
        case 0: return ""
        case 1: return names[0]
        default: return names.dropLast().joined(separator: ", ") + " and " + (names.last ?? "")
        }
    }
}
