// ConsolidatePresentationsSheet.swift
// Surfaces lessons with more than one active (draft / scheduled) presentation
// and lets the guide drag individual student chips between the duplicates so
// they can be merged into a single presentation per lesson.

import SwiftUI
import CoreData
import UniformTypeIdentifiers

struct ConsolidatePresentationsSheet: View {
    /// The one lesson to merge, from that lesson's "Merge Groups…" button in
    /// the backlog; nil lists every lesson with more than one presentation.
    let lessonID: UUID?
    let onDismiss: () -> Void

    @FetchRequest private var activeAssignments: FetchedResults<CDLessonAssignment>

    init(lessonID: UUID? = nil, onDismiss: @escaping () -> Void) {
        self.lessonID = lessonID
        self.onDismiss = onDismiss
        let states = [LessonAssignmentState.draft.rawValue, LessonAssignmentState.scheduled.rawValue]
        // Scoped to the lesson in the store rather than after the fetch, so a
        // one-lesson sheet does not fault in every active presentation.
        let predicate = lessonID.map {
            NSPredicate(format: "stateRaw IN %@ AND lessonID == %@", states, $0.uuidString)
        } ?? NSPredicate(format: "stateRaw IN %@", states)
        _activeAssignments = FetchRequest(
            sortDescriptors: [
                NSSortDescriptor(key: "scheduledFor", ascending: true),
                NSSortDescriptor(key: "createdAt", ascending: true)
            ],
            predicate: predicate
        )
    }

    @Environment(\.dependencies) private var dependencies
    @TestStudentVisibility private var testStudents

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(lessonID == nil ? "Consolidate" : "Merge Groups")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done", action: onDismiss)
                    }
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        if duplicateGroups.isEmpty {
            ContentUnavailableView(
                lessonID == nil ? "No Duplicates" : "One Group",
                systemImage: "rectangle.stack.badge.minus",
                description: Text(lessonID == nil
                    ? "Every lesson has at most one active presentation."
                    : "Every child on this lesson is in one presentation now.")
            )
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: AppTheme.Spacing.large) {
                    ForEach(duplicateGroups, id: \.lessonID) { group in
                        groupSection(group)
                            .transition(.asymmetric(
                                insertion: .opacity,
                                removal: .scale(scale: 0.92).combined(with: .opacity)
                            ))
                    }
                }
                .padding(AppTheme.Spacing.medium)
                .animation(.spring(response: 0.4, dampingFraction: 0.78), value: duplicateGroups.map(\.lessonID))
            }
        }
    }

    // MARK: - Groups

    private struct DuplicateGroup {
        let lessonID: UUID
        let lesson: CDLesson?
        let presentations: [CDLessonAssignment]
    }

    private var duplicateGroups: [DuplicateGroup] {
        let lessonByID = dependencies.lessonCatalog.byID
        let grouped = Dictionary(grouping: activeAssignments) { $0.resolvedLessonID }
        return grouped
            .filter { $0.value.count >= 2 }
            .map { lessonID, presentations in
                DuplicateGroup(
                    lessonID: lessonID,
                    lesson: lessonByID[lessonID],
                    presentations: presentations.sorted { lhs, rhs in
                        switch (lhs.scheduledFor, rhs.scheduledFor) {
                        case let (l?, r?): return l < r
                        case (nil, _?): return false
                        case (_?, nil): return true
                        case (nil, nil):
                            return (lhs.createdAt ?? .distantPast) < (rhs.createdAt ?? .distantPast)
                        }
                    }
                )
            }
            .sorted { lhs, rhs in
                let lhsName = lhs.lesson?.name ?? ""
                let rhsName = rhs.lesson?.name ?? ""
                if lhsName == rhsName { return lhs.lessonID.uuidString < rhs.lessonID.uuidString }
                return lhsName.localizedCaseInsensitiveCompare(rhsName) == .orderedAscending
            }
    }

    // MARK: - Group section

    @ViewBuilder
    private func groupSection(_ group: DuplicateGroup) -> some View {
        let duplicates = duplicateStudentIDs(in: group)
        VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
            HStack(spacing: AppTheme.Spacing.verySmall) {
                Circle()
                    .fill(areaColor(for: group.lesson))
                    .frame(width: 8, height: 8)
                Text(group.lesson?.name ?? "Untitled Lesson")
                    .font(.headline)
                if !duplicates.isEmpty {
                    Label("\(duplicates.count) duplicate", systemImage: "exclamationmark.triangle.fill")
                        .labelStyle(.titleAndIcon)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(AppColors.warning)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .capsuleFill(AppColors.warning.opacity(UIConstants.OpacityConstants.accent))
                }
                Spacer()
                Text("\(group.presentations.count) presentations")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            groupCards(group, duplicates: duplicates)
        }
        .padding(AppTheme.Spacing.compact)
        .surface(
            UIConstants.CornerRadius.medium,
            fill: Color.primary.opacity(UIConstants.OpacityConstants.veryFaint),
            style: .continuous
        )
    }

    /// The lesson's groups side by side, numbered in the order shown.
    private func groupCards(_ group: DuplicateGroup, duplicates: Set<UUID>) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: AppTheme.Spacing.small) {
                ForEach(Array(group.presentations.enumerated()), id: \.element.objectID) { index, presentation in
                    ConsolidateLessonCard(
                        presentation: presentation,
                        groupNumber: index + 1,
                        groups: group.presentations,
                        lessonID: group.lessonID,
                        areaColor: areaColor(for: group.lesson),
                        students: studentMap,
                        duplicateStudentIDs: duplicates
                    )
                    .frame(width: 260)
                    .transition(.asymmetric(
                        insertion: .opacity,
                        removal: .scale(scale: 0.85).combined(with: .opacity)
                    ))
                }
            }
            .padding(.vertical, AppTheme.Spacing.verySmall)
            .animation(.spring(response: 0.35, dampingFraction: 0.75), value: group.presentations.compactMap(\.id))
        }
    }

    private func duplicateStudentIDs(in group: DuplicateGroup) -> Set<UUID> {
        let visible = studentMap
        var counts: [UUID: Int] = [:]
        for presentation in group.presentations {
            for id in presentation.resolvedStudentIDs where visible[id] != nil {
                counts[id, default: 0] += 1
            }
        }
        return Set(counts.compactMap { $0.value >= 2 ? $0.key : nil })
    }

    /// The children the chips may show: enrolled, and test students only when
    /// they are shown, as the backlog's own chips (bug hunt 2026-11-03 #17).
    private var studentMap: [UUID: CDStudent] {
        let visible = TestStudentsFilter.filterVisible(
            dependencies.roster.enrolled, show: testStudents.show, namesRaw: testStudents.namesRaw
        )
        return Dictionary(
            visible.compactMap { student in student.id.map { ($0, student) } },
            uniquingKeysWith: { first, _ in first }
        )
    }

    private func areaColor(for lesson: CDLesson?) -> Color {
        if let area = lesson?.area, !area.isEmpty {
            return AppColors.color(forArea: area)
        }
        return .accentColor
    }
}

// MARK: - Card

private struct ConsolidateLessonCard: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.appRouter) private var appRouter
    @Environment(\.dependencies) private var dependencies
    @Environment(SaveCoordinator.self) private var saveCoordinator

    @ObservedObject var presentation: CDLessonAssignment
    /// Its place among the lesson's groups here, as the header and the
    /// chips' "Move to Group N" name it.
    let groupNumber: Int
    /// Every group of the lesson in this sheet, in their numbered order.
    let groups: [CDLessonAssignment]
    let lessonID: UUID
    let areaColor: Color
    let students: [UUID: CDStudent]
    let duplicateStudentIDs: Set<UUID>

    @State private var isDropHighlighted = false
    /// A Remove waiting for the guide's yes (`PresentationDeletion.removeRequest`).
    @State private var pendingRemoval: [PresentationDeletion.Request] = []

    private var presentationID: UUID { presentation.id ?? UUID() }

    /// The children on the card that the chips show.
    private var shownStudentIDs: [UUID] {
        presentation.resolvedStudentIDs.filter { students[$0] != nil }
    }

    private var stateLabel: String {
        if presentation.state == .scheduled, let scheduled = presentation.scheduledFor {
            return scheduledLabel(for: scheduled)
        }
        if presentation.state == .scheduled {
            return "Scheduled"
        }
        return "Draft"
    }

    private var stateSymbol: String {
        presentation.state == .scheduled ? "calendar" : "hourglass"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
            HStack(spacing: AppTheme.Spacing.verySmall) {
                Label("Group \(groupNumber) · \(stateLabel)", systemImage: stateSymbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(shownStudentIDs.count)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .capsuleFill(Color.primary.opacity(UIConstants.OpacityConstants.light))
            }

            studentChips
        }
        .padding(AppTheme.Spacing.compact)
        .frame(maxWidth: .infinity, minHeight: 100, alignment: .topLeading)
        .surface(
            UIConstants.CornerRadius.medium,
            fill: Color.primary.opacity(UIConstants.OpacityConstants.trace),
            stroke: isDropHighlighted ? Color.accentColor : areaColor.opacity(UIConstants.OpacityConstants.accent),
            lineWidth: isDropHighlighted ? 2 : 1,
            style: .continuous
        )
        .onDrop(of: [UTType.text], delegate: PillDropDelegate(
            viewContext: viewContext,
            appRouter: appRouter,
            targetLessonID: lessonID,
            targetLessonAssignmentID: presentationID,
            enableMergeDrop: false,
            setHighlight: { isDropHighlighted = $0 },
            setMergeHighlight: { _ in },
            canAccept: { isDropHighlighted },
            onDidMutate: { reason in saveCoordinator.save(viewContext, reason: reason) },
            onMergeReceived: {},
            onSourceEmptied: { dependencies.toastService.showSuccess("Presentation removed") }
        ))
        .workspaceDeletionConfirmation(
            pending: $pendingRemoval,
            title: pendingRemoval.first?.title ?? "",
            confirmTitle: pendingRemoval.first?.confirmTitle ?? "Remove",
            message: pendingRemoval.first?.message ?? ""
        ) { requests in
            for request in requests {
                if let studentID = request.studentID { performRemove(studentID) }
            }
        }
    }

    @ViewBuilder
    private var studentChips: some View {
        let ids = shownStudentIDs
        if ids.isEmpty {
            Text("No students")
                .font(.caption)
                .foregroundStyle(.tertiary)
        } else {
            FlowLayout(spacing: 6) {
                ForEach(ids, id: \.self) { id in
                    DraggableStudentChip(
                        student: students[id],
                        studentID: id,
                        sourcePresentationID: presentationID,
                        lessonID: lessonID,
                        areaColor: areaColor,
                        isDuplicate: duplicateStudentIDs.contains(id),
                        moves: moves(for: id),
                        onMove: { move in moveChild(id, move: move) },
                        onRemove: { remove(studentID: id) }
                    )
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.28, dampingFraction: 0.78), value: ids)
        }
    }

    /// What a child's right-click offers: each other group she isn't
    /// already in, and a new group when hers has others in it.
    private func moves(for studentID: UUID) -> [BacklogChipMove] {
        let id = studentID.uuidString
        var moves: [BacklogChipMove] = groups.enumerated().compactMap { index, group in
            guard group.objectID != presentation.objectID, !group.isGiven,
                  !group.studentIDs.contains(id) else { return nil }
            return BacklogChipMove(target: group, groupNumber: index + 1)
        }
        if !presentation.isGiven, presentation.studentIDs.count > 1 {
            moves.append(BacklogChipMove(target: nil, groupNumber: nil))
        }
        return moves
    }

    private func moveChild(_ studentID: UUID, move: BacklogChipMove) {
        GroupChildMover(context: viewContext, saveCoordinator: saveCoordinator, toasts: dependencies.toastService)
            .move(studentID, name: students[studentID]?.shortName ?? "the child", from: presentation, move: move)
        appRouter.refreshPlanningInbox()
    }

    /// The chip's Remove: asks first when she is the last child on a plan
    /// with notes or marks, since the plan goes with her (bug hunt 2026-11-03 #3).
    private func remove(studentID: UUID) {
        guard let ctx = presentation.managedObjectContext else { return }
        let idString = studentID.uuidString
        let name = students[studentID]?.shortName ?? ""
        if let request = PresentationDeletion.removeRequest(idString, childName: name, from: presentation, in: ctx) {
            pendingRemoval = [request]
        } else {
            performRemove(idString)
        }
    }

    /// Takes her off as the Checklist's Remove Plan does: her promoted entry
    /// goes back to planned, her marks stay, and an emptied plan's notes stay
    /// on her (`PresentationDeletion.remove`).
    private func performRemove(_ idString: String) {
        guard let ctx = presentation.managedObjectContext else { return }
        let didEmpty = PresentationDeletion.remove(idString, from: presentation, in: ctx)
        saveCoordinator.save(viewContext, reason: "Remove student from presentation")
        if didEmpty {
            dependencies.toastService.showSuccess("Presentation removed")
        }
        appRouter.refreshPlanningInbox()
    }

    private func scheduledLabel(for date: Date) -> String {
        DateFormatters.mediumDate.string(from: date)
    }
}
