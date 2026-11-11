// PresentationHowItWentView+NextLesson.swift
// The How It Went sheet's "Next lesson" row: when a child is newly Ready for
// next, where the lesson after this one goes. The Inbox to begin with, or a
// day with an optional start time, chosen here and written by Done
// (docs/Plans/Plan - Next lesson row when presenting.md).

import CoreData
import SwiftUI

extension PresentationHowItWentView {
    /// The newly ready children Done makes a plan for.
    var nextLessonRecipients: Set<UUID> {
        let ready = session.newlyReady(for: studentIDs)
        return nextLesson?.recipients(newlyReady: ready) ?? ready
    }

    /// Where the lesson goes while the guide has chosen nothing.
    var nextLessonStartingPlace: PresentationNextLessonPlace {
        nextLesson?.startingPlace(for: nextLessonRecipients) ?? .inbox
    }

    /// Where Done puts the next lesson: the guide's choice, or the starting place.
    var nextLessonPlace: PresentationNextLessonPlace {
        session.nextLessonPlace ?? nextLessonStartingPlace
    }

    /// Shown only while Done would make a new plan for the next lesson.
    @ViewBuilder
    var nextLessonRow: some View {
        let recipients = nextLessonRecipients
        if let nextLesson, !recipients.isEmpty {
            rowLayout(label: Text("Next lesson").font(.caption).foregroundStyle(.secondary)) {
                PresentationNextLessonRow(
                    session: session,
                    lessonName: nextLesson.lessonName,
                    recipientNames: students
                        .filter { $0.id.map(recipients.contains) ?? false }
                        .map(\.shortName),
                    startingPlace: nextLessonStartingPlace,
                    nextSchoolDay: quickDay
                )
            }
        }
    }
}

/// The lesson's name, the chips that say where it goes, and a line saying who
/// it is for. The choice lives on the session; nothing is written until Done.
struct PresentationNextLessonRow: View {
    @Bindable var session: PresentationSession
    let lessonName: String
    /// The children the plan is for, in display order.
    let recipientNames: [String]
    /// Where the lesson goes while the guide has chosen nothing.
    let startingPlace: PresentationNextLessonPlace
    let nextSchoolDay: Date?

    @Environment(\.managedObjectContext) private var viewContext
    @State private var showDatePicker = false
    @State private var pickedDay = AppCalendar.startOfDay(Date())
    @State private var timeTarget: TimeTarget?

    /// The day whose time is being picked, with the start times already used on it.
    struct TimeTarget: Identifiable {
        let day: Date
        let takenMinutes: Set<Int>
        var id: Date { day }
    }

    private var place: PresentationNextLessonPlace { session.nextLessonPlace ?? startingPlace }
    private var quickDay: Date? { nextSchoolDay.map(AppCalendar.startOfDay) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(lessonName)
                .font(AppTheme.ScaledFont.calloutSemibold)
                .fixedSize(horizontal: false, vertical: true)
            chips
            Text(Self.caption(
                names: recipientNames,
                place: place,
                fromYearPlan: session.nextLessonPlace == nil
            ))
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// "For Maya and Leo. Waits in the Inbox until you give it a day."
    static func caption(
        names: [String],
        place: PresentationNextLessonPlace,
        fromYearPlan: Bool,
        locale: Locale = .autoupdatingCurrent
    ) -> String {
        let who = "For \(PresentationSessionSummary.list(names))."
        guard let day = place.dayText(locale: locale) else {
            return "\(who) Waits in the Inbox until you give it a day."
        }
        if fromYearPlan { return "\(who) The year plan has it on \(day)." }
        return "\(who) Goes on the week for \(day)."
    }
}

// MARK: - Chips

private extension PresentationNextLessonRow {
    var chips: some View {
        FlowLayout(spacing: 6) {
            PresentationDecisionChip(title: "Inbox", look: place == .inbox ? .chosen : .plain) {
                session.nextLessonPlace = .inbox
            }
            .accessibilityLabel("Put it in the Inbox")
            if let quickDay {
                PresentationDecisionChip(
                    title: quickDay.formatted(.dateTime.weekday(.wide)),
                    look: place.day == quickDay ? .chosen : .plain
                ) {
                    session.nextLessonPlace = place.moved(to: quickDay)
                }
                .accessibilityLabel("Schedule for \(quickDay.formatted(.dateTime.weekday(.wide)))")
            }
            if let custom = place.day, custom != quickDay {
                PresentationDecisionChip(
                    title: custom.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()),
                    look: .chosen
                ) {
                    openDatePicker()
                }
                .accessibilityLabel(
                    "Scheduled for \(custom.formatted(.dateTime.weekday(.wide).month(.wide).day())). Change the day"
                )
            }
            PresentationDecisionChip(title: "Pick a Day…", look: .plain, action: openDatePicker)
                .popover(isPresented: $showDatePicker) { datePicker }
            if let day = place.day {
                timeChip(on: day)
            }
        }
    }

    func openDatePicker() {
        pickedDay = place.day ?? quickDay ?? AppCalendar.startOfDay(Date())
        showDatePicker = true
    }

    var datePicker: some View {
        VStack(spacing: 12) {
            DatePicker(
                "Schedule on",
                selection: $pickedDay,
                in: AppCalendar.startOfDay(Date())...,
                displayedComponents: .date
            )
            .datePickerStyle(.graphical)
            .labelsHidden()
            Button("Schedule on This Day") {
                session.nextLessonPlace = place.moved(to: pickedDay)
                showDatePicker = false
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(minWidth: 300)
    }

    /// "Set time", dashed, until a start time is chosen; then the time itself.
    func timeChip(on day: Date) -> some View {
        let time = place.clockTime
        return PresentationDecisionChip(
            title: time.map { LessonTimeText.chip($0) } ?? "Set time",
            look: time == nil ? .inherited : .chosen
        ) {
            timeTarget = TimeTarget(
                day: day,
                takenMinutes: ScheduledDateEdits.takenMinutes(on: day, excluding: nil, in: viewContext)
            )
        }
        .accessibilityLabel(time.map { "Start time, \(LessonTimeText.spoken($0)). Change it" } ?? "Set a start time")
        .lessonTimePicker(item: $timeTarget) { target in
            LessonTimePicker(
                lessonTitle: lessonName,
                current: place.clockTime,
                takenMinutes: target.takenMinutes,
                startingHalf: place.clockTime?.half ?? .morning,
                set: { hour, minute in
                    session.nextLessonPlace = place.settingTime(hour: hour, minute: minute)
                },
                remove: {
                    session.nextLessonPlace = place.removingTime
                }
            )
        }
    }
}
