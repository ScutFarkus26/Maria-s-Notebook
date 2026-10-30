import SwiftUI
import CoreData

/// One work item's decision in a meeting: the outcomes are one-tap buttons,
/// and once one is chosen the card ticks itself off and offers a note.
///
/// Two rows, one choice between them (2026-10-30): keep going or finished,
/// then Mastered, Re-present or Rest. Ready for Next is a switch below them
/// that goes with any choice but Re-present.
struct WorkDecisionCard: View {
    @ObservedObject var work: CDWorkModel
    let title: String
    @Bindable var draft: MeetingDraftModel
    var onDetails: (() -> Void)?

    @Environment(\.managedObjectContext) private var viewContext
    @State private var isPickingRest = false
    @State private var restUntil = AppCalendar.addingDays(14, to: Date())

    private var workID: UUID? { work.id }
    private var isReviewed: Bool { workID.map(draft.reviewedWorkIDs.contains) ?? false }
    private var isRepresenting: Bool { workID.map(draft.representWorkIDs.contains) ?? false }
    private var isReady: Bool { workID.map(draft.readyWorkIDs.contains) ?? false }
    /// Re-present and Ready for Next need a lesson to plan; manual work has none.
    private var hasLesson: Bool { UUID(uuidString: work.lessonID) != nil }
    /// What Ready for Next puts On Deck. At the end of a sequence there is
    /// nothing, and the switch isn't offered (bug hunt 2026-10-09, #13).
    private var nextLessonName: String? { draft.nextLessonName(after: work.lessonID) }

    /// "Keep Practicing" for practice work, "Keep Working" for an assignment.
    static func keepGoingLabel(for kind: WorkKind) -> String {
        kind == .practiceLesson ? "Keep Practicing" : "Keep Working"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            outcomeButtons
            if hasLesson, isReady || nextLessonName != nil {
                readyForNextSwitch
            }
            if isReviewed, let workID {
                TextField("Note…", text: noteBinding(workID), axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .font(.subheadline)
            }
        }
        .padding(12)
        .surface(
            UIConstants.CornerRadius.control,
            fill: Color.primary.opacity(UIConstants.OpacityConstants.ghost),
            stroke: Color.primary.opacity(UIConstants.OpacityConstants.subtle),
            style: .continuous
        )
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: isReviewed ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isReviewed ? AppColors.success : AppColors.warning)
                .accessibilityLabel(isReviewed ? "Decided" : "Needs a decision")
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if let onDetails {
                Button(action: onDetails) {
                    Image(systemName: "arrow.up.right.square")
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open \(title)")
            }
        }
    }

    private var subtitle: String {
        var parts = [work.status.displayName]
        if let created = work.createdAt {
            let days = AppCalendar.shared.dateComponents([.day], from: created, to: Date()).day ?? 0
            parts.append("\(days) day\(days == 1 ? "" : "s")")
        }
        if work.isResting, let until = work.restingUntil {
            parts.append("resting till \(DateFormatters.shortMonthDay.string(from: until))")
        } else if let touched = work.lastTouchedAt {
            parts.append("last touched \(DateFormatters.shortMonthDay.string(from: touched))")
        }
        return parts.joined(separator: " · ")
    }

    private var outcomeButtons: some View {
        VStack(alignment: .leading, spacing: 6) {
            FlowLayout(spacing: 6) {
                statusButton(Self.keepGoingLabel(for: work.displayKind), status: .active)
                statusButton("Finished", status: .done)
                    .help("Closes this work with no verdict")
            }
            FlowLayout(spacing: 6) {
                statusButton("Mastered", status: .mastered)
                if hasLesson {
                    outcomeButton("Re-present", selected: isReviewed && isRepresenting) {
                        draft.represent(work, context: viewContext)
                    }
                    .help("Closes this work as Incomplete and plans the lesson again when you complete the meeting")
                }
                restButton
            }
        }
    }

    /// A choice that sets the work's status; Re-present and Rest have their own.
    private func statusButton(_ label: String, status: WorkStatus) -> some View {
        outcomeButton(
            label, selected: isReviewed && !work.isResting && !isRepresenting && work.status == status
        ) {
            draft.decide(work, status: status, context: viewContext)
        }
    }

    private var restButton: some View {
        outcomeButton(work.isResting ? "Resting" : "Rest…", selected: isReviewed && work.isResting) {
            restUntil = AppCalendar.addingDays(14, to: Date())
            isPickingRest = true
        }
        .popover(isPresented: $isPickingRest) {
            VStack(spacing: 12) {
                Text("Rest until…")
                    .font(.headline)
                DatePicker("Rest until", selection: $restUntil, in: Date()..., displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                    .frame(maxWidth: 300)
                Button("Let It Rest") {
                    draft.rest(work, until: restUntil, context: viewContext)
                    isPickingRest = false
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            .presentationCompactAdaptation(.popover)
        }
    }

    /// Ready for Next beside the choice, not one of them: it leaves the
    /// work's status alone, so it's drawn as a switch rather than a button.
    private var readyForNextSwitch: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(isOn: readyBinding) {
                HStack(spacing: 4) {
                    Text("Ready for Next")
                        .layoutPriority(1)
                    if let nextLessonName {
                        Text("· \(nextLessonName)")
                            .foregroundStyle(isReady ? AppColors.success : .secondary)
                            .lineLimit(1)
                    }
                }
            }
            .toggleStyle(ReadyForNextToggleStyle())
            .disabled(isRepresenting)
            .help(
                isRepresenting
                    ? "Re-present plans this lesson again, so there's no next lesson yet"
                    : "Puts the next lesson On Deck when you complete the meeting"
            )
            if isReady {
                Text("Goes On Deck when you complete the meeting")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var readyBinding: Binding<Bool> {
        Binding(
            get: { isReady },
            set: { draft.setReadyForNext($0, for: work) }
        )
    }

    private func outcomeButton(_ label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.subheadline)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .frame(minHeight: 32)
                .foregroundStyle(selected ? Color.white : Color.primary)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(selected ? Color.accentColor : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(selected ? Color.accentColor : Color.secondary.opacity(0.35))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func noteBinding(_ id: UUID) -> Binding<String> {
        Binding(
            get: { draft.workNotes[id] ?? "" },
            set: { draft.workNotes[id] = $0 }
        )
    }
}

/// A checkbox in a capsule: dashed while off, green while on, so it reads
/// as something added to the card's choice rather than one of them.
private struct ReadyForNextToggleStyle: ToggleStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: configuration.isOn ? "checkmark.square.fill" : "square")
                    .foregroundStyle(configuration.isOn ? AppColors.success : .secondary)
                configuration.label
            }
            .font(.subheadline)
            .foregroundStyle(Color.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(minHeight: 32)
            .background(
                Capsule().fill(configuration.isOn ? AppColors.success.opacity(0.15) : Color.clear)
            )
            .overlay(
                Capsule().strokeBorder(
                    configuration.isOn ? AppColors.success.opacity(0.6) : Color.secondary.opacity(0.5),
                    style: StrokeStyle(lineWidth: 1, dash: configuration.isOn ? [] : [4, 3])
                )
            )
            .contentShape(Capsule())
            .opacity(isEnabled ? 1 : 0.4)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(configuration.isOn ? [.isToggle, .isSelected] : .isToggle)
    }
}
