import SwiftUI
import CoreData

/// One work item's decision in a meeting: the outcomes are one-tap buttons,
/// and once one is chosen the card ticks itself off and offers a note.
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
    /// Ready for Next needs a next lesson to put On Deck: at the end of a
    /// sequence it would close the work and plan nothing (bug hunt
    /// 2026-10-09, #13). Still shown when already chosen, so it can be undone.
    private var offersReadyForNext: Bool { isReady || draft.hasNextLesson(after: work.lessonID) }

    private enum Outcome: CaseIterable {
        case keepWorking, practice, mastered

        var label: String {
            switch self {
            case .keepWorking: "Keep Working"
            case .practice: "Practice"
            case .mastered: "Mastered"
            }
        }

        var status: WorkStatus {
            switch self {
            case .keepWorking: .active
            case .practice: .keepPracticing
            case .mastered: .mastered
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            outcomeButtons
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
        FlowLayout(spacing: 6) {
            ForEach(Outcome.allCases, id: \.self) { outcome in
                outcomeButton(
                    outcome.label,
                    selected: isReviewed && !work.isResting && !isRepresenting && !isReady
                        && work.status == outcome.status
                ) {
                    draft.decide(work, status: outcome.status, context: viewContext)
                }
            }
            if hasLesson {
                outcomeButton("Re-present", selected: isReviewed && isRepresenting) {
                    draft.represent(work, context: viewContext)
                }
                .help("Closes this work as Incomplete and plans the lesson again when you complete the meeting")
                if offersReadyForNext {
                    outcomeButton("Ready for Next", selected: isReviewed && isReady) {
                        draft.readyForNext(work, context: viewContext)
                    }
                    .help(
                        "Closes this work without marking it mastered and puts the next lesson On Deck "
                            + "when you complete the meeting"
                    )
                }
            }
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
