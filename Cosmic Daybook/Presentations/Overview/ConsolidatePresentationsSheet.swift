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

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: AppTheme.Spacing.small) {
                    ForEach(group.presentations, id: \.objectID) { presentation in
                        ConsolidateLessonCard(
                            presentation: presentation,
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
        .padding(AppTheme.Spacing.compact)
        .surface(
            UIConstants.CornerRadius.medium,
            fill: Color.primary.opacity(UIConstants.OpacityConstants.veryFaint),
            style: .continuous
        )
    }

    private func duplicateStudentIDs(in group: DuplicateGroup) -> Set<UUID> {
        var counts: [UUID: Int] = [:]
        for presentation in group.presentations {
            for id in presentation.resolvedStudentIDs {
                counts[id, default: 0] += 1
            }
        }
        return Set(counts.compactMap { $0.value >= 2 ? $0.key : nil })
    }

    private var studentMap: [UUID: CDStudent] { dependencies.roster.byID }

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
    let lessonID: UUID
    let areaColor: Color
    let students: [UUID: CDStudent]
    let duplicateStudentIDs: Set<UUID>

    @State private var isDropHighlighted = false

    private var presentationID: UUID { presentation.id ?? UUID() }

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
                Label(stateLabel, systemImage: stateSymbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(presentation.resolvedStudentIDs.count)")
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
    }

    @ViewBuilder
    private var studentChips: some View {
        let ids = presentation.resolvedStudentIDs
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
                        onRemove: { remove(studentID: id) }
                    )
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.28, dampingFraction: 0.78), value: ids)
        }
    }

    private func remove(studentID: UUID) {
        let idString = studentID.uuidString
        var ids = presentation.studentIDs
        ids.removeAll { $0 == idString }
        presentation.studentIDs = ids
        presentation.updateDenormalizedKeys()
        presentation.modifiedAt = Date()
        let didEmpty = ids.isEmpty
        if didEmpty, let ctx = presentation.managedObjectContext {
            ctx.delete(presentation)
        }
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

// MARK: - Chip

private struct DraggableStudentChip: View {
    let student: CDStudent?
    let studentID: UUID
    let sourcePresentationID: UUID
    let lessonID: UUID
    let areaColor: Color
    let isDuplicate: Bool
    let onRemove: () -> Void

    private var label: String {
        if let student { return student.shortName }
        return "(Removed)"
    }

    private var fillColor: Color {
        isDuplicate
            ? AppColors.warning.opacity(UIConstants.OpacityConstants.accent)
            : areaColor.opacity(UIConstants.OpacityConstants.accent)
    }

    private var strokeColor: Color {
        isDuplicate
            ? AppColors.warning
            : areaColor.opacity(UIConstants.OpacityConstants.medium)
    }

    var body: some View {
        HStack(spacing: 4) {
            if isDuplicate {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundStyle(AppColors.warning)
            }
            Text(label)
                .font(.caption.weight(.medium))
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .capsuleFill(fillColor)
        .overlay(
            Capsule().stroke(strokeColor, lineWidth: isDuplicate ? 1.5 : 1)
        )
        .foregroundStyle(.primary)
        .contentShape(Capsule())
        .onDrag {
            let payload = DragPayload.encode(
                sourceID: sourcePresentationID,
                lessonID: lessonID,
                studentID: studentID
            )
            let provider = NSItemProvider(object: NSString(string: payload))
            provider.suggestedName = label
            return provider
        }
        .contextMenu {
            Button(role: .destructive, action: onRemove) {
                Label("Remove from this presentation", systemImage: "person.fill.xmark")
            }
        }
        .accessibilityLabel(isDuplicate ? "\(label), also in another presentation" : label)
    }
}
