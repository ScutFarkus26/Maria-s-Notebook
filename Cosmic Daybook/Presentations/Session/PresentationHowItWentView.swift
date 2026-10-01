// PresentationHowItWentView.swift
// Beat two of the presentation sheet: one note for the group, one decision per
// child, and what Done will write — in the same sheet that recorded it.
//
// The AI may sort the guide's words into each child's note (Split by Child);
// every decision stays a tap. Nothing here saves until Done, except Later,
// which files the notes and keeps the decisions as a draft.

import CoreData
import SwiftUI

struct PresentationHowItWentView: View {
    @Bindable var session: PresentationSession
    let lesson: CDLesson
    /// The children the presentation was recorded for, in display order.
    let students: [CDStudent]
    let presentedAt: Date?
    let nextLessonName: String?
    let canUndo: Bool
    let isSaving: Bool
    let onUndo: () -> Void
    let onEditDetails: () -> Void
    let onLater: () -> Void
    let onDone: () -> Void

    @Environment(\.managedObjectContext) private var viewContext
    @State private var nextSchoolDay: Date?
    @State private var showDatePicker = false
    @State private var pickedDay = AppCalendar.startOfDay(Date())

    private var studentIDs: [UUID] { students.compactMap(\.id) }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    PresentationGroupNoteSection(session: session, lesson: lesson, students: students)
                    decisionsCard
                    summaryCard
                }
                .padding(24)
                .frame(maxWidth: 760, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .dismissKeyboardOnScroll()
            Divider()
            footer
        }
        .task {
            nextSchoolDay = await SchoolCalendarService.shared.nextSchoolDay(after: Date(), using: viewContext)
        }
    }
}

// MARK: - Header and footer

private extension PresentationHowItWentView {
    var header: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: "checkmark")
                .font(.title3.weight(.bold))
                .foregroundStyle(AppColors.success)
                .frame(width: 40, height: 40)
                .background(AppColors.success.opacity(UIConstants.OpacityConstants.accent), in: Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(recordedLine)
                    .font(AppTheme.ScaledFont.captionSemibold)
                    .foregroundStyle(AppColors.success)
                Text(lesson.name)
                    .font(.title2.weight(.bold))
                Text(rosterLine)
                    .font(AppTheme.ScaledFont.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            if canUndo {
                Button(action: onUndo) {
                    Label("Undo", systemImage: "arrow.uturn.backward")
                }
                .buttonStyle(.bordered)
                .help("Take back the recording of this presentation")
            } else {
                Button("Details", action: onEditDetails)
                    .buttonStyle(.bordered)
                    .help("Edit the presentation's lesson, children, or notes")
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }

    var recordedLine: String {
        guard let presentedAt else { return "Recorded" }
        if AppCalendar.shared.isDateInToday(presentedAt) { return "Recorded · today" }
        return "Given " + presentedAt.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }

    var rosterLine: String {
        let names = PresentationSessionSummary.list(students.map(\.shortName))
        guard !session.keptOnPlanNames.isEmpty else { return names }
        let kept = PresentationSessionSummary.list(session.keptOnPlanNames)
        return "\(names) · \(kept) \(session.keptOnPlanNames.count == 1 ? "stays" : "stay") on the plan"
    }

    var footer: some View {
        HStack(spacing: 12) {
            Button("Later", action: onLater)
                .keyboardShortcut(.cancelAction)
                .help("Save the notes now and keep these decisions open in Following")
            #if os(macOS)
            Text("Later keeps these open in Following")
                .font(.caption)
                .foregroundStyle(.secondary)
            #endif
            Spacer()
            if isSaving { ProgressView().controlSize(.small) }
            Button(action: onDone) {
                Text("Done").bold().frame(minWidth: 80)
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(isSaving)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(.bar)
    }
}

// MARK: - Decisions

private extension PresentationHowItWentView {
    var decisionsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text(students.count == 1 ? "What's next" : "What's next for each child")
                    .font(AppTheme.ScaledFont.calloutSemibold)
                if students.count > 1 {
                    Text("Set it for everyone, then change only who differs.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(14)

            if students.count == 1, let only = students.first {
                // One child: her row is everyone's row.
                onlyChildRow(only)
            } else {
                everyoneRow
                ForEach(students) { student in
                    Divider()
                    childRow(student)
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: UIConstants.CornerRadius.large, style: .continuous)
                .strokeBorder(Color.primary.opacity(UIConstants.OpacityConstants.light))
        )
    }

    var everyoneRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            rowLayout(label: Text("Everyone").font(AppTheme.ScaledFont.bodySemibold)) {
                FlowLayout(spacing: 6) {
                    ForEach(CaptureFollowUp.presentationChoices) { choice in
                        PresentationDecisionChip(
                            title: choice.chipTitle,
                            look: session.everyone == choice ? .chosen : .plain
                        ) {
                            session.setEveryone(choice)
                        }
                    }
                }
            }
            checkInRow
        }
        .padding(14)
        .background(Color.accentColor.opacity(UIConstants.OpacityConstants.subtle))
    }

    @ViewBuilder
    var checkInRow: some View {
        if studentIDs.contains(where: { session.decision(for: $0).createsWork }) {
            rowLayout(label: Text("Check the work").font(.caption).foregroundStyle(.secondary)) {
                checkInChips
            }
        }
    }

    func onlyChildRow(_ student: CDStudent) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            rowLayout(label: childLabel(student)) {
                FlowLayout(spacing: 6) {
                    ForEach(CaptureFollowUp.presentationChoices) { choice in
                        PresentationDecisionChip(
                            title: choice.chipTitle,
                            look: session.everyone == choice ? .chosen : .plain
                        ) {
                            session.setEveryone(choice)
                        }
                    }
                }
            }
            checkInRow
            noteField(student)
        }
        .padding(14)
        .background(Color.accentColor.opacity(UIConstants.OpacityConstants.subtle))
    }

    func childLabel(_ student: CDStudent) -> some View {
        HStack(spacing: 8) {
            StudentAvatarView(student: student, size: 28)
            Text(student.shortName).font(AppTheme.ScaledFont.bodySemibold)
        }
    }

    func noteField(_ student: CDStudent) -> some View {
        let id = student.id ?? UUID()
        return TextField(
            "A note about \(student.firstName)…",
            text: Binding(
                get: { session.childNotes[id] ?? "" },
                set: { session.childNotes[id] = $0 }
            ),
            axis: .vertical
        )
        .lineLimit(1...4)
        .textFieldStyle(.roundedBorder)
        .font(AppTheme.ScaledFont.callout)
        .accessibilityLabel("Note about \(student.shortName)")
    }

    @ViewBuilder
    var checkInChips: some View {
        FlowLayout(spacing: 6) {
            PresentationDecisionChip(
                title: "Next work cycle",
                look: session.checkIn == .nextWorkCycle ? .chosen : .plain
            ) {
                session.checkIn = .nextWorkCycle
            }
            if let nextSchoolDay {
                PresentationDecisionChip(
                    title: nextSchoolDay.formatted(.dateTime.weekday(.wide)),
                    look: session.checkIn.day == AppCalendar.startOfDay(nextSchoolDay) ? .chosen : .plain
                ) {
                    session.checkIn = .on(nextSchoolDay)
                }
            }
            if let custom = session.checkIn.day, custom != nextSchoolDay.map(AppCalendar.startOfDay) {
                PresentationDecisionChip(
                    title: custom.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()),
                    look: .chosen
                ) {
                    pickedDay = custom
                    showDatePicker = true
                }
            }
            PresentationDecisionChip(title: "Pick a Day…", look: .plain) {
                pickedDay = session.checkIn.day ?? AppCalendar.startOfDay(Date())
                showDatePicker = true
            }
            .popover(isPresented: $showDatePicker) {
                VStack(spacing: 12) {
                    DatePicker(
                        "Check on",
                        selection: $pickedDay,
                        in: AppCalendar.startOfDay(Date())...,
                        displayedComponents: .date
                    )
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                    Button("Check on This Day") {
                        session.checkIn = .on(pickedDay)
                        showDatePicker = false
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
                .frame(minWidth: 300)
            }
        }
    }

    func childRow(_ student: CDStudent) -> some View {
        let id = student.id ?? UUID()
        let current = session.decision(for: id)
        return VStack(alignment: .leading, spacing: 8) {
            rowLayout(label: childLabel(student)) {
                FlowLayout(spacing: 6) {
                    ForEach(CaptureFollowUp.presentationChoices) { choice in
                        PresentationDecisionChip(
                            title: choice.chipTitle,
                            look: look(for: choice, current: current, overridden: session.isOverridden(id))
                        ) {
                            session.setDecision(choice, for: id)
                        }
                    }
                }
            }
            noteField(student)
        }
        .padding(14)
    }

    func look(
        for choice: CaptureFollowUp,
        current: CaptureFollowUp,
        overridden: Bool
    ) -> PresentationDecisionChip.Look {
        guard choice == current else { return .plain }
        return overridden ? .differs : .inherited
    }

    /// A label column beside the chips where there is room, above them where
    /// there is not.
    func rowLayout<Label: View, Content: View>(
        label: Label,
        @ViewBuilder content: () -> Content
    ) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                label.frame(width: 130, alignment: .leading)
                content().frame(minWidth: 420, alignment: .leading)
            }
            VStack(alignment: .leading, spacing: 8) {
                label
                content()
            }
        }
    }
}

// MARK: - What Done will do

private extension PresentationHowItWentView {
    var summaryLines: [String] {
        let decisions = Dictionary(uniqueKeysWithValues: studentIDs.map { ($0, session.decision(for: $0)) })
        let noteCount = (session.groupNote.trimmed().isEmpty ? 0 : 1)
            + studentIDs.filter { !(session.childNotes[$0]?.trimmed().isEmpty ?? true) }.count
        return PresentationSessionSummary.lines(.init(
            children: students.compactMap { student in
                student.id.map { PresentationSessionSummary.Child(id: $0, name: student.shortName) }
            },
            pending: session.pendingDecisions(for: studentIDs),
            decisions: decisions,
            checkIn: session.checkIn,
            checkInChanged: session.checkInChanged,
            noteCount: noteCount,
            lessonName: lesson.name,
            nextLessonName: nextLessonName
        ))
    }

    var summaryCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("When you press Done")
                .font(AppTheme.ScaledFont.captionSemibold)
                .foregroundStyle(.secondary)
            let lines = summaryLines
            if lines.isEmpty {
                Text("Nothing new to save. Done just closes.")
                    .font(AppTheme.ScaledFont.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(lines, id: \.self) { line in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("•").foregroundStyle(Color.accentColor)
                        Text(line).font(AppTheme.ScaledFont.callout)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            Color.primary.opacity(UIConstants.OpacityConstants.whisper),
            in: RoundedRectangle(cornerRadius: UIConstants.CornerRadius.large, style: .continuous)
        )
    }
}
