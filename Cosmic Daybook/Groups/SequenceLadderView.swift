//
//  SequenceLadderView.swift
//  Cosmic Daybook
//
//  One sub-area of the curriculum as a ladder, pushed from the Groups page.
//
//  The steps run top to bottom, each with the children standing on it (the
//  tiers are `SequenceLadderStepRow`'s). The header counts the children who
//  have not started the sequence and who have finished it, and its arrows
//  step through the area's sequences in the guide's own order. Everything is
//  built from the snapshot the Groups page already holds, so the page and the
//  ladder never disagree about who is ready.
//

import CoreData
import SwiftUI

struct SequenceLadderView: View {
    let area: String
    let snapshot: ReadyQueueSnapshot
    let schoolDaysSince: (Date) -> Int

    /// The sequence on show; starts as the one the page pushed.
    @State private var sequence: String
    /// Children confirmed here (`SequenceLadderStepRow.confirmKey`), so a row
    /// says so before the snapshot is rebuilt.
    @State private var confirmed: Set<String> = []

    @Environment(\.managedObjectContext) private var viewContext
    @Environment(SaveCoordinator.self) private var saveCoordinator
    private var ageSettings: StudentAgePaletteReader

    init(
        area: String,
        sequence: String,
        snapshot: ReadyQueueSnapshot,
        schoolDaysSince: @escaping (Date) -> Int
    ) {
        self.area = area
        self.snapshot = snapshot
        self.schoolDaysSince = schoolDaysSince
        _sequence = State(initialValue: sequence)
        ageSettings = StudentAgePaletteReader(.lessons)
    }

    var body: some View {
        let ladder = SequenceLadder.build(
            area: area, sequence: sequence, from: snapshot, schoolDaysSince: schoolDaysSince
        )
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header(ladder)
                if let ladder {
                    steps(ladder)
                    people(ladder)
                } else {
                    unknown
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle(area)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    // MARK: - Header

    private func header(_ ladder: SequenceLadder?) -> some View {
        HStack(alignment: .center, spacing: 8) {
            stepButton(systemImage: "chevron.left", label: "Previous sequence", offset: -1)
            VStack(spacing: 4) {
                // The area is the navigation title, so it is not repeated here.
                Text(ladder?.sequence ?? sequence)
                    .font(.title2.weight(.semibold))
                    .multilineTextAlignment(.center)
                if let ladder {
                    counts(ladder)
                }
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            stepButton(systemImage: "chevron.right", label: "Next sequence", offset: 1)
        }
    }

    private func counts(_ ladder: SequenceLadder) -> some View {
        HStack(spacing: 14) {
            Label("\(ladder.notStarted.count) not started", systemImage: "circle.dashed")
            Label("\(ladder.finished.count) finished", systemImage: "checkmark.seal")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .labelStyle(.titleAndIcon)
    }

    private func stepButton(systemImage: String, label: String, offset: Int) -> some View {
        let target = sibling(offset)
        return Button {
            if let target { sequence = target }
        } label: {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(target == nil ? Color.secondary.opacity(0.4) : Color.accentColor)
        .disabled(target == nil)
        .accessibilityLabel(label)
        .help(label)
    }

    // MARK: - Sequences in the area

    /// The area's sequences in the guide's saved order, as the rest of the app shows them.
    private var orderedSequences: [String] {
        FilterOrderStore.loadSequenceOrder(for: area, existing: snapshot.order.sequences(inArea: area))
    }

    /// The sequence `offset` places from the current one; nil at either end or when the current one is unknown.
    private func sibling(_ offset: Int) -> String? {
        let all = orderedSequences
        let wanted = sequence.trimmed()
        guard let index = all.firstIndex(where: { $0.trimmed().caseInsensitiveCompare(wanted) == .orderedSame }),
              all.indices.contains(index + offset) else { return nil }
        return all[index + offset]
    }

    // MARK: - Content

    private func steps(_ ladder: SequenceLadder) -> some View {
        let palette = ageSettings.palette
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(ladder.steps) { step in
                SequenceLadderStepRow(
                    step: step,
                    isLast: step.id == ladder.steps.last?.id,
                    palette: palette,
                    confirmed: confirmed,
                    onConfirm: confirm
                )
            }
        }
    }

    /// Who has not started and who has finished, by name. The header only counts them.
    @ViewBuilder
    private func people(_ ladder: SequenceLadder) -> some View {
        if !ladder.notStarted.isEmpty || !ladder.finished.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                if !ladder.notStarted.isEmpty {
                    nameList("Not started", ladder.notStarted)
                }
                if !ladder.finished.isEmpty {
                    nameList("Finished", ladder.finished)
                }
            }
            .padding(.top, 4)
        }
    }

    private func nameList(_ title: String, _ children: [ReadyRoster.Child]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption.weight(.semibold))
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
            Text(children.map(\.name).joined(separator: ", "))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var unknown: some View {
        ContentUnavailableView(
            "No Such Sequence",
            systemImage: "list.number",
            description: Text("\(sequence) is not a sequence in \(area). It may have been renamed or removed.")
        )
        .frame(maxWidth: .infinity)
    }

    // MARK: - Confirm

    /// Confirms the child on the lesson below her frontier, and saves.
    private func confirm(_ rung: SequenceLadder.Rung) {
        guard let assignmentID = rung.confirmAssignmentID,
              let uuid = rung.child.uuid,
              let assignment = viewContext.object(with: assignmentID) as? CDLessonAssignment else { return }
        assignment.confirmStudent(uuid)
        if saveCoordinator.save(viewContext, reason: "Confirm lesson"),
           let key = SequenceLadderStepRow.confirmKey(for: rung) {
            confirmed.insert(key)
        }
    }
}

// The `#Preview` closure is expanded and type-checked in every compiler job
// for the module; a private view is checked once, in this file's job.
private struct SequenceLadderViewPreview: View {
    private static let today = Date()
    private static let stack = CoreDataStack.preview
    private static let snapshot = makeSnapshot()

    /// Math › Laws with a child on every kind of rung, and Math › Fractions to step to.
    @MainActor
    private static func makeSnapshot() -> ReadyQueueSnapshot {
        let context = stack.viewContext
        func lesson(_ name: String, _ sequence: String, _ order: Int64) -> CDLesson {
            let lesson = CDLesson(context: context)
            lesson.name = name
            lesson.area = "Math"
            lesson.sequence = sequence
            lesson.orderInSequence = order
            return lesson
        }
        let laws = ["Commutative Law", "Distributive Law", "Associative Law", "Identity"]
            .enumerated().map { lesson($1, "Laws", Int64($0 + 1) * 10) }
        let fractions = ["Fraction Skittles", "Equivalence"]
            .enumerated().map { lesson($1, "Fractions", Int64($0 + 1) * 10) }
        let settings = CDLessonSequenceSettings(context: context)
        settings.area = "Math"
        settings.sequence = "Laws"
        settings.requiresPractice = true
        settings.requiresTeacherConfirmation = false

        let kids = seedClass(laws: laws, in: context)
        let ids = Set(kids.compactMap { $0.id?.uuidString })
        let index = PresentationRecordIndex(students: ids, in: context)
        return ReadyQueueSnapshot(students: kids, lessons: laws + fractions, index: index, in: context)
    }

    /// Ada and Ben are ready (Ben's practice is open), Cy is unconfirmed, Dee is
    /// planned, Eve has finished, and Fay and Gil have not started.
    @MainActor
    private static func seedClass(laws: [CDLesson], in context: NSManagedObjectContext) -> [CDStudent] {
        let kids = ["Ada Bell", "Ben Cole", "Cy Dunn", "Dee Eng", "Eve Ford", "Fay Gold", "Gil Hart"].map { name in
            let student = CDStudent(context: context)
            let parts = name.split(separator: " ")
            student.firstName = String(parts[0])
            student.lastName = String(parts[1])
            return student
        }
        func day(_ offset: Int) -> Date {
            AppCalendar.shared.date(byAdding: .day, value: offset, to: today) ?? today
        }
        func give(_ students: [CDStudent], _ lesson: CDLesson, daysAgo: Int, confirmed: Bool) {
            let given = PresentationFactory.makePresented(
                lesson: lesson, students: students, presentedAt: day(-daysAgo), context: context
            )
            guard confirmed else { return }
            for id in students.compactMap(\.id) { given.confirmStudent(id) }
        }
        give([kids[0], kids[1], kids[3]], laws[0], daysAgo: 12, confirmed: true)
        give([kids[2]], laws[0], daysAgo: 20, confirmed: true)
        give([kids[2]], laws[1], daysAgo: 6, confirmed: false)
        for lesson in laws { give([kids[4]], lesson, daysAgo: 60, confirmed: true) }
        if let ben = kids[1].id, let first = laws[0].id {
            let work = CDWorkModel(context: context)
            work.title = "Commutative practice"
            work.studentID = ben.uuidString
            work.lessonID = first.uuidString
            work.statusRaw = "active"
        }
        _ = PresentationFactory.makeScheduled(
            lesson: laws[1], students: [kids[3]], scheduledFor: day(3), context: context
        )
        return kids
    }

    var body: some View {
        NavigationStack {
            SequenceLadderView(
                area: "Math", sequence: "Laws", snapshot: Self.snapshot,
                schoolDaysSince: { date in
                    AppCalendar.shared.dateComponents([.day], from: date, to: Self.today).day ?? 0
                }
            )
        }
        .previewEnvironment(using: Self.stack)
    }
}

#Preview {
    SequenceLadderViewPreview()
}
