// MeetingFormPane.swift
// The meeting form, in the order a meeting runs: last week's focus, the
// child's reflection, lesson requests, the guide's private notes, next meeting.

import SwiftUI
import CoreData

// MARK: - Meeting Form

struct MeetingFormPane: View {
    @Bindable var draft: MeetingDraftModel
    /// The active template's prompts, shown as captions that stay visible while typing.
    let template: CDMeetingTemplate?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            FocusChecklistView(draft: draft)
                .padding(.bottom, 18)
            Divider()

            section(title: "Reflection", caption: template?.reflectionPrompt ?? "What went well? What was hard?") {
                editor(text: $draft.reflection, minHeight: 88)
            }
            Divider()

            section(title: "Lesson Requests", caption: "Matched lessons go to the inbox when you complete") {
                LessonRequestField(draft: draft)
            }
            Divider()

            privateNotes
            Divider()

            section(title: "Next Meeting", caption: nil) {
                NextMeetingChips(date: $draft.nextMeetingDate)
            }
        }
    }

    private var privateNotes: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "lock.fill")
                    .font(.caption)
                Text("Private Notes")
                    .font(.subheadline.weight(.semibold))
                Text("· only you see this")
                    .font(.subheadline)
            }
            .foregroundStyle(.secondary)
            .accessibilityElement(children: .combine)

            editor(
                text: $draft.guideNotes,
                minHeight: 52,
                placeholder: template?.guideNotesPrompt ?? "Observations only you can see…"
            )
        }
        .padding(.vertical, 18)
    }

    private func section<Content: View>(
        title: String,
        caption: String?,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                if let caption, !caption.isEmpty {
                    Text(caption)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 18)
    }

    private func editor(text: Binding<String>, minHeight: CGFloat, placeholder: String? = nil) -> some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: text)
                .scrollContentBackground(.hidden)
                .frame(minHeight: minHeight)
                .padding(6)
                .surface(
                    UIConstants.CornerRadius.control,
                    fill: Color.primary.opacity(UIConstants.OpacityConstants.trace),
                    style: .continuous
                )

            if let placeholder, text.wrappedValue.trimmed().isEmpty {
                Text(placeholder)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 14)
                    .allowsHitTesting(false)
            }
        }
    }
}

// MARK: - Next Meeting Chips

/// Most meetings are simply next week, so that's one tap.
struct NextMeetingChips: View {
    @Binding var date: Date?
    @State private var isPicking = false
    @State private var pickedDate = Date()

    private var nextWeek: Date { AppCalendar.startOfDay(AppCalendar.addingDays(7, to: Date())) }
    private var twoWeeks: Date { AppCalendar.startOfDay(AppCalendar.addingDays(14, to: Date())) }

    private var isCustom: Bool {
        guard let date else { return false }
        return !AppCalendar.isSameDay(date, nextWeek) && !AppCalendar.isSameDay(date, twoWeeks)
    }

    var body: some View {
        FlowLayout(spacing: 8) {
            chip("Next week · \(Self.label(nextWeek))", selected: isSelected(nextWeek)) {
                date = nextWeek
            }
            chip("2 weeks · \(Self.label(twoWeeks))", selected: isSelected(twoWeeks)) {
                date = twoWeeks
            }
            chip(isCustom ? date.map(Self.label) ?? "Pick a Day…" : "Pick a Day…", selected: isCustom) {
                pickedDate = date ?? Date()
                isPicking = true
            }
            .popover(isPresented: $isPicking) {
                VStack(spacing: 12) {
                    DatePicker("Next Meeting", selection: $pickedDate, in: Date()..., displayedComponents: .date)
                        .datePickerStyle(.graphical)
                        .labelsHidden()
                        .frame(maxWidth: 320)
                    Button("Set Day") {
                        date = AppCalendar.startOfDay(pickedDate)
                        isPicking = false
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
                .presentationCompactAdaptation(.popover)
            }
            chip("Not Yet", selected: date == nil) {
                date = nil
            }
        }
    }

    private func isSelected(_ day: Date) -> Bool {
        date.map { AppCalendar.isSameDay($0, day) } ?? false
    }

    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .foregroundStyle(selected ? Color.white : Color.primary)
                .background(Capsule().fill(selected ? Color.accentColor : Self.chipFill))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private static let chipFill = Color.primary.opacity(UIConstants.OpacityConstants.light)

    private static func label(_ date: Date) -> String {
        DateFormatters.shortMonthDay.string(from: date)
    }
}
