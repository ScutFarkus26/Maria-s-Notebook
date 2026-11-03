// WorkLogSheet.swift
// The sheet behind a pill on the Scheduled strip: one row per child, her
// status, and a note, logged together.
//
// Replaces the "N Students" sheet, which drew each child's status as five
// dots that could only be looked at and saved a note on every keystroke.
// Nothing here writes until "Log Check": the rows are drafts, and the caller
// hands them to `WorkLogService`, which also marks the day's check-ins done
// so the pill leaves the strip the way a recorded presentation does.
//
// Typed notes are the one thing here that can't be got back, so Cancel, a
// swipe down and the open-work arrow ask before throwing them away (bug hunt
// 2026-10-12 #41). On the Mac `dismissalConfirmationDialog` also asks about a
// programmatic dismiss, and both Log Check and the arrow end in one (the
// arrow's caller clears the sheet's item), so each sets `isClosing` and acts
// only once the view has redrawn with the question off, as `CommandBarSheet`
// does.

import CoreData
import SwiftUI

struct WorkLogSheet: View {
    @Environment(\.dismiss) private var dismiss

    let group: CalendarCheckInGroup
    /// Receives one entry per child; the caller logs, saves, toasts.
    let onLog: ([WorkLogService.Entry]) -> Void
    let onOpenWork: (UUID) -> Void

    @State private var drafts: [Draft]
    /// Set just before the sheet closes on purpose, so the discard question
    /// doesn't ask about a log or an open the guide chose.
    @State private var isClosing = false
    /// What to do once `isClosing` has been drawn.
    @State private var pendingClose: Closing?
    /// What Discard would go on to do, while Cancel's or the arrow's question is up.
    @State private var confirmingDiscard: Closing?

    /// How the sheet is closing on purpose.
    private enum Closing: Equatable {
        case cancel
        case log
        case openWork(UUID)
    }

    private static let discardTitle = "Discard your notes?"
    private static let discardMessage = "The notes you typed haven't been logged."

    /// Notes that closing now would throw away.
    private var hasNotesToLose: Bool {
        !isClosing && drafts.contains { !$0.note.trimmed().isEmpty }
    }

    struct Draft: Identifiable {
        let id: UUID
        let work: CDWorkModel
        let name: String
        let initialStatus: WorkStatus
        var status: WorkStatus
        var note: String = ""

        var entry: WorkLogService.Entry {
            let trimmed = note.trimmed()
            return WorkLogService.Entry(
                work: work,
                status: status == initialStatus ? nil : status,
                note: trimmed.isEmpty ? nil : trimmed
            )
        }
    }

    init(
        group: CalendarCheckInGroup,
        onLog: @escaping ([WorkLogService.Entry]) -> Void,
        onOpenWork: @escaping (UUID) -> Void
    ) {
        self.group = group
        self.onLog = onLog
        self.onOpenWork = onOpenWork
        _drafts = State(initialValue: Self.makeDrafts(for: group))
    }

    /// One draft per row under the pill, named from the row's own child —
    /// `studentNames` drops empty names, so it cannot be zipped by position.
    private static func makeDrafts(for group: CalendarCheckInGroup) -> [Draft] {
        var seen: Set<NSManagedObjectID> = []
        return group.checkIns.compactMap { checkIn in
            guard let work = checkIn.resolvedWork(), seen.insert(work.objectID).inserted else { return nil }
            let name = WorkGrouping.owner(of: work)
                .flatMap { work.managedObjectContext?.object(CDStudent.self, id: $0) }
                .map(\.shortName) ?? "Student"
            return Draft(
                id: checkIn.id ?? UUID(),
                work: work,
                name: name,
                initialStatus: work.status,
                status: work.status
            )
        }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                header
                Divider()
                ScrollView {
                    VStack(spacing: AppTheme.Spacing.compact) {
                        if drafts.count > 1 {
                            everyoneRow
                        }
                        ForEach($drafts) { $draft in
                            childRow($draft)
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
            .navigationTitle(drafts.count == 1 ? "Log Check" : "Log \(drafts.count) Checks")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { closeAskingFirst(.cancel) }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Log Check") { close(.log) }
                        .disabled(drafts.isEmpty)
                }
            }
            .confirmationDialog(
                Self.discardTitle,
                isPresented: Binding(
                    get: { confirmingDiscard != nil },
                    set: { if !$0 { confirmingDiscard = nil } }
                ),
                titleVisibility: .visible,
                presenting: confirmingDiscard
            ) { closing in
                Button("Discard", role: .destructive) {
                    confirmingDiscard = nil
                    close(closing)
                }
                Button("Keep Editing", role: .cancel) { confirmingDiscard = nil }
            } message: { _ in
                Text(Self.discardMessage)
            }
        }
        // A swipe down (or, on the Mac, any dismiss) asks first too;
        // `isClosing` lets a chosen close through.
        .dismissalConfirmationDialog(Self.discardTitle, shouldPresent: hasNotesToLose) {
            Button("Discard", role: .destructive) {}
            Button("Keep Editing", role: .cancel) {}
        } message: {
            Text(Self.discardMessage)
        }
        // Acts only once the view has redrawn with `isClosing` set, so the
        // question above is already off when the sheet goes.
        .onChange(of: pendingClose) { _, closing in
            guard let closing else { return }
            switch closing {
            case .cancel:
                dismiss()
            case .log:
                onLog(drafts.map(\.entry))
                dismiss()
            case .openWork(let workID):
                dismiss()
                onOpenWork(workID)
            }
        }
        #if os(macOS)
        .frame(minWidth: 520, minHeight: 360)
        .presentationSizingFitted()
        #else
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        #endif
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(group.lessonTitle)
                .font(.title2.weight(.semibold))
            HStack(spacing: 6) {
                if !group.purpose.isEmpty {
                    Label(CheckInReason.displayName(forStoredPurpose: group.purpose), systemImage: "checkmark.circle")
                        .foregroundStyle(.secondary)
                    Text("·").foregroundStyle(.tertiary)
                }
                Text(group.sortDate, style: .date)
                    .foregroundStyle(.secondary)
            }
            .font(.subheadline)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 14)
    }

    /// One pill row that sets every child below it. Lit only while they all
    /// agree, so a mixed sheet never claims one status for everyone.
    private var everyoneRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Everyone")
                .font(AppTheme.ScaledFont.captionSemibold)
                .foregroundStyle(.secondary)
            let shared = drafts.allSatisfy { $0.status == drafts[0].status } ? drafts[0].status : nil
            statusPills(selected: shared) { status in
                for index in drafts.indices { drafts[index].status = status }
            }
        }
        .padding(.horizontal, UIConstants.contentHorizontalPadding)
        .padding(.vertical, AppTheme.Spacing.compact)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, UIConstants.dropZoneInnerPadding)
    }

    private func childRow(_ draft: Binding<Draft>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(draft.wrappedValue.name)
                    .font(AppTheme.ScaledFont.bodySemibold)
                Spacer()
                Button {
                    guard let id = draft.wrappedValue.work.id else { return }
                    closeAskingFirst(.openWork(id))
                } label: {
                    Image(systemName: "arrow.forward.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Open the work")
            }
            statusPills(selected: draft.wrappedValue.status) { status in
                draft.wrappedValue.status = status
            }
            TextField("Note about \(draft.wrappedValue.name)…", text: draft.note, axis: .vertical)
                .font(AppTheme.ScaledFont.caption)
                .lineLimit(2...4)
                .textFieldStyle(.roundedBorder)
        }
        .padding(.horizontal, UIConstants.contentHorizontalPadding)
        .padding(.vertical, AppTheme.Spacing.compact)
        .background(Color.primary.opacity(UIConstants.OpacityConstants.veryFaint))
        .clipRounded(UIConstants.CornerRadius.medium, style: .continuous)
        .padding(.horizontal, UIConstants.dropZoneInnerPadding)
    }

    // MARK: - Closing

    /// Cancel and the open-work arrow: asks first when typed notes would be lost.
    private func closeAskingFirst(_ closing: Closing) {
        if hasNotesToLose {
            confirmingDiscard = closing
        } else {
            close(closing)
        }
    }

    /// Turns the discard question off, then closes once that is drawn.
    private func close(_ closing: Closing) {
        isClosing = true
        pendingClose = closing
    }

    private func statusPills(selected: WorkStatus?, onSelect: @escaping (WorkStatus) -> Void) -> some View {
        FlowLayout(spacing: 6) {
            ForEach(WorkStatus.pickable) { status in
                SelectablePillButton(
                    item: status,
                    isSelected: selected == status,
                    color: status.color,
                    icon: status.iconName,
                    label: status.displayName
                ) {
                    adaptiveWithAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        onSelect(status)
                    }
                }
            }
        }
    }
}
