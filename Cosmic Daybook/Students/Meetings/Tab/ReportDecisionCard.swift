import SwiftUI
import CoreData

/// One report in a meeting (2026-10-30): where it stands, as a row of stage
/// chips, with Rest and the day she presents to the class. Tapping a stage,
/// the one she's at included, is the card's decision, as a status choice is
/// on a `WorkDecisionCard`.
struct ReportDecisionCard: View {
    @ObservedObject var report: CDWorkModel
    let title: String
    @Bindable var draft: MeetingDraftModel
    var onDetails: (() -> Void)?

    @Environment(\.managedObjectContext) private var viewContext
    @State private var isPickingRest = false
    @State private var restUntil = AppCalendar.addingDays(14, to: Date())
    @State private var isPickingDay = false
    @State private var presentOn = AppCalendar.addingDays(7, to: Date())

    private var reportID: UUID? { report.id }
    private var isReviewed: Bool { reportID.map(draft.reviewedWorkIDs.contains) ?? false }
    private var stages: [String] { ReportStages.titles(of: report) }
    private var current: Int? { ReportStages.currentStage(of: report) }
    private var presentDay: Date? { ReportStages.presentDay(of: report) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            stageChips
            HStack(spacing: 6) {
                restButton
                // The day is offered from Writing on, or once one is set.
                if report.status.isOpen, presentDay != nil || (current ?? 0) >= min(2, stages.count - 1) {
                    presentDayButton
                }
            }
            if isReviewed, let reportID {
                TextField("Note…", text: noteBinding(reportID), axis: .vertical)
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
                    .fixedSize(horizontal: false, vertical: true)
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
        var parts: [String] = []
        let partners = partnerNames
        if !partners.isEmpty { parts.append("with \(partners)") }
        if let created = report.createdAt {
            let days = AppCalendar.shared.dateComponents([.day], from: created, to: Date()).day ?? 0
            parts.append("\(days) day\(days == 1 ? "" : "s")")
        }
        if report.isResting, let until = report.restingUntil {
            parts.append("resting till \(DateFormatters.shortMonthDay.string(from: until))")
        } else if let presentDay {
            parts.append("presents to the class \(DateFormatters.shortMonthDay.string(from: presentDay))")
        } else if ReportStages.hasBeenPresented(report), let done = report.completedAt {
            parts.append("presented \(DateFormatters.shortMonthDay.string(from: done))")
        }
        return parts.joined(separator: " · ")
    }

    /// The other children writing it, "Leora F and Maya S".
    private var partnerNames: String {
        let names = WorkGrouping.studentIDs(of: report)
            .filter { $0 != draft.studentID }
            .compactMap { viewContext.object(CDStudent.self, id: $0)?.shortName }
        return ListFormatter.localizedString(byJoining: names)
    }

    private var stageChips: some View {
        FlowLayout(spacing: 6) {
            ForEach(Array(stages.enumerated()), id: \.offset) { index, name in
                stageChip(index: index, name: name)
            }
        }
    }

    private func stageChip(index: Int, name: String) -> some View {
        // Presented reads as every stage passed.
        let presented = current == nil
        let passed = presented || index < (current ?? 0)
        let isCurrent = index == current
        let chosen = isReviewed && !report.isResting && (isCurrent || (presented && index == stages.count - 1))
        return Button {
            draft.setStage(index, of: report, context: viewContext)
        } label: {
            HStack(spacing: 4) {
                if passed && !chosen {
                    Image(systemName: "checkmark")
                        .font(.caption2.weight(.bold))
                }
                Text(name)
            }
            .font(.subheadline)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(minHeight: 32)
            .foregroundStyle(chosen ? Color.white : (passed ? AppColors.success : Color.primary))
            .background(
                Capsule().fill(
                    chosen ? Color.accentColor : (passed ? AppColors.success.opacity(0.15) : Color.clear)
                )
            )
            .overlay(
                Capsule().strokeBorder(
                    chosen ? Color.accentColor
                        : (isCurrent ? Color.accentColor.opacity(0.6) : Color.secondary.opacity(0.35)),
                    lineWidth: isCurrent && !chosen ? 1.5 : 1
                )
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(stageAccessibilityLabel(name: name, passed: passed, isCurrent: isCurrent))
        .accessibilityAddTraits(chosen ? .isSelected : [])
        .help(index == stages.count - 1
              ? "She has presented it: closes the report as Finished"
              : "She's at \(name)")
    }

    private func stageAccessibilityLabel(name: String, passed: Bool, isCurrent: Bool) -> String {
        if isCurrent { return "\(name), where she is now" }
        return passed ? "\(name), done" : name
    }

    private var restButton: some View {
        smallButton(report.isResting ? "Resting" : "Rest…", selected: isReviewed && report.isResting) {
            restUntil = AppCalendar.addingDays(14, to: Date())
            isPickingRest = true
        }
        .popover(isPresented: $isPickingRest) {
            datePopover(title: "Rest until…", selection: $restUntil, action: "Let It Rest") {
                draft.rest(report, until: restUntil, context: viewContext)
                isPickingRest = false
            }
        }
    }

    private var presentDayButton: some View {
        smallButton(
            presentDay.map { "Presents \(DateFormatters.shortMonthDay.string(from: $0))" } ?? "Presents on…",
            selected: false
        ) {
            presentOn = presentDay ?? AppCalendar.addingDays(7, to: Date())
            isPickingDay = true
        }
        .popover(isPresented: $isPickingDay) {
            datePopover(
                title: "Presents to the class on…", selection: $presentOn, action: "Set the Day",
                clear: presentDay == nil ? nil : { savePresentDay(nil) }
            ) {
                savePresentDay(presentOn)
            }
        }
    }

    private func savePresentDay(_ day: Date?) {
        if !ReportStages.savePresentDay(day, for: report, context: viewContext) {
            ToastService.shared.showError("Couldn't save the day she presents. Try again.")
        }
        isPickingDay = false
    }

    private func datePopover(
        title: String, selection: Binding<Date>, action: String,
        clear: (() -> Void)? = nil, perform: @escaping () -> Void
    ) -> some View {
        VStack(spacing: 12) {
            Text(title)
                .font(.headline)
            DatePicker(title, selection: selection, in: Date()..., displayedComponents: .date)
                .datePickerStyle(.graphical)
                .labelsHidden()
                .frame(maxWidth: 300)
            HStack {
                if let clear {
                    Button("No Day", role: .destructive, action: clear)
                }
                Button(action, action: perform)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .presentationCompactAdaptation(.popover)
    }

    private func smallButton(_ label: String, selected: Bool, action: @escaping () -> Void) -> some View {
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
