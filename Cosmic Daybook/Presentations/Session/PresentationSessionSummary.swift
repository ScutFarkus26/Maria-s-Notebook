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
        /// The follow-up work's title as typed; blank gives the lesson's default.
        var followUpDetail = ""
        /// Children newly ready for the next lesson alongside their work.
        var alsoReady: Set<UUID> = []
        /// Children ready on the record and no longer marked ready.
        var noLongerReady: Set<UUID> = []
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
            let detail = input.followUpDetail.trimmed()
            let title = detail.isEmpty ? "Follow up: \(input.lessonName)" : detail
            lines.append("Follow-up work for \(list(followUp)) — “\(title)”")
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
        lines += readinessLines(input)
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

    /// Who goes on to the next lesson, and who no longer does.
    private static func readinessLines(_ input: Input) -> [String] {
        var lines: [String] = []
        let ready = input.children
            .filter { input.pending[$0.id] == .readyForNextLesson || input.alsoReady.contains($0.id) }
            .map(\.name)
        if !ready.isEmpty {
            let subject = "\(list(ready)) \(ready.count == 1 ? "is" : "are")"
            if let next = input.nextLessonName {
                lines.append("\(subject) ready for the next lesson: \(next) goes On Deck")
            } else {
                lines.append("\(subject) confirmed ready for the next lesson")
            }
        }
        let unready = input.children.filter { input.noLongerReady.contains($0.id) }.map(\.name)
        if !unready.isEmpty {
            let verb = unready.count == 1 ? "isn't" : "aren't"
            lines.append("\(list(unready)) \(verb) marked ready for the next lesson any more")
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
