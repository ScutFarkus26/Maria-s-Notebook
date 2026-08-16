//
//  LessonAssignmentHistoryView+Rows.swift
//  Maria's Notebook
//
//  Row rendering for LessonAssignmentHistoryView - extracted for maintainability
//

import SwiftUI
import CoreData

extension LessonAssignmentHistoryView {

    // MARK: - Main Content

    var mainContent: some View {
        VStack(spacing: 8) {
            filterBar

            Group {
                if loadedAssignments.isEmpty {
                    ContentUnavailableView(
                        "No Presentations Yet",
                        systemImage: "clock.arrow.circlepath",
                        description: Text("Present lessons to see them here.")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if filteredAssignments.isEmpty {
                    ContentUnavailableView(
                        "No Matching Presentations",
                        systemImage: "magnifyingglass",
                        description: Text("Try adjusting your filters.")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    assignmentsList
                }
            }
        }
    }

    var assignmentsList: some View {
        ScrollViewReader { reader in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(groupedByDay.enumerated()), id: \.element.day) { dayIndex, entry in
                        daySection(dayIndex: dayIndex, entry: entry)
                    }
                }
                .padding(16)
            }
            .task(id: focusedAssignmentRevealKey) {
                guard let focusedAssignmentID,
                      filteredAssignments.contains(where: { $0.id == focusedAssignmentID }) else {
                    return
                }
                await Task.yield()
                try? await Task.sleep(for: .milliseconds(50))
                guard !Task.isCancelled else { return }
                withAnimation { reader.scrollTo(focusedAssignmentID, anchor: .center) }
            }
        }
    }

    var focusedAssignmentRevealKey: String {
        guard let focusedAssignmentID else { return "none" }
        let isLoaded = loadedAssignments.contains { $0.id == focusedAssignmentID }
        return "\(focusedAssignmentID.uuidString)|\(isLoaded)"
    }

    @ViewBuilder
    func daySection(dayIndex: Int, entry: (day: Date, items: [CDLessonAssignment])) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(DateFormatters.mediumDate.string(from: entry.day))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.top, 12)

            ForEach(Array(entry.items.enumerated()), id: \.element.objectID) { itemIndex, la in
                historyEntry(
                    la,
                    dayIndex: dayIndex,
                    itemIndex: itemIndex,
                    itemsInDay: entry.items.count
                )
            }
        }
    }

    func historyEntry(
        _ assignment: CDLessonAssignment,
        dayIndex: Int,
        itemIndex: Int,
        itemsInDay: Int
    ) -> some View {
        row(for: assignment)
            .id(assignment.id ?? UUID())
            .onTapGesture { openAssignmentDetail(assignment) }
            .onAppear {
                if dayIndex == groupedByDay.count - 1,
                   itemIndex >= itemsInDay - 5 {
                    loadMoreAssignments()
                }
            }
    }

    @ViewBuilder
    // swiftlint:disable:next function_body_length
    func row(for la: CDLessonAssignment) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title(for: la))
                        .font(AppTheme.ScaledFont.bodySemibold)
                    HStack(spacing: 6) {
                        if let presentedAt = la.presentedAt {
                            Text(DateFormatters.shortTime.string(from: presentedAt))
                        }
                        Text("\u{2022}")
                        Text(studentNamesOrCount(for: la))
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            // Display notes inline if present
            if let notesSet = la.unifiedNotes, let notes = notesSet.allObjects as? [CDNote], !notes.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(
                        notes.sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) },
                        id: \.objectID
                    ) { note in
                        noteRow(note)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 10)
            }
        }
        .contentShape(Rectangle())
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(
                    focusedAssignmentID != nil && la.id == focusedAssignmentID
                        ? Color.accentColor.opacity(0.12)
                        : Color.primary.opacity(UIConstants.OpacityConstants.trace)
                )
        )
        .overlay {
            if focusedAssignmentID != nil && la.id == focusedAssignmentID {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.accentColor, lineWidth: 2)
            }
        }
        .contextMenu {
            Button {
                openAssignmentDetail(la)
            } label: {
                Label("View Details", systemImage: "eye")
            }

            if let lessonID = la.lessonIDUUID {
                #if os(macOS)
                Button {
                    openLessonInNewWindow(lessonID)
                } label: {
                    Label("View Lesson", systemImage: SFSymbol.Education.book)
                }
                #endif
            }

            Divider()

            Button(role: .destructive) {
                deleteAssignment(la)
            } label: {
                Label("Delete", systemImage: SFSymbol.Action.trash)
            }
        }
    }

    func openAssignmentDetail(_ assignment: CDLessonAssignment) {
        guard let assignmentID = assignment.id else { return }
        #if os(macOS)
        openWindow(id: "PresentationDetailWindow", value: assignmentID)
        #else
        selectedAssignment = assignment
        #endif
    }

    @ViewBuilder
    func noteRow(_ note: CDNote) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(note.body)
                .font(AppTheme.ScaledFont.caption)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 6) {
                // Tag badges
                if !note.tagsArray.isEmpty {
                    ForEach(note.tagsArray.prefix(2), id: \.self) { tag in
                        TagBadge(tag: tag, compact: true)
                    }
                }

                // Image indicator
                if note.imagePath != nil {
                    Image(systemName: "photo")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.primary.opacity(UIConstants.OpacityConstants.whisper))
        )
    }
}
