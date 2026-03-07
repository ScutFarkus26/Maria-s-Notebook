// ObservationsView+List.swift
// List rendering, rows, and data loading for ObservationsView

import SwiftUI
import SwiftData

extension ObservationsView {
    // MARK: - Observations List

    var observationsList: some View {
        List {
            if filteredItems.isEmpty, !isLoading {
                ContentUnavailableView("No observations", systemImage: "note.text")
                    .listRowBackground(Color.clear)
                    .frame(maxWidth: .infinity, alignment: .center)
            } else {
                ForEach(filteredItems, id: \.id) { item in
                    observationRow(for: item)
                }
            }
        }
        .listStyle(.inset)
    }

    // MARK: - Observation Row

    @ViewBuilder
    func observationRow(for item: UnifiedObservationItem) -> some View {
        row(for: item)
            .contentShape(Rectangle())
            .overlay(alignment: .trailing) {
                if isSelecting {
                    Image(systemName: selectedItemIDs.contains(item.id) ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(selectedItemIDs.contains(item.id) ? Color.accentColor : .secondary)
                }
            }
            .onTapGesture {
                if isSelecting {
                    if selectedItemIDs.contains(item.id) {
                        selectedItemIDs.remove(item.id)
                    } else {
                        selectedItemIDs.insert(item.id)
                    }
                } else {
                    editItem(item)
                }
            }
    }

    // MARK: - Row Content

    @ViewBuilder
    // swiftlint:disable:next function_body_length
    func row(for item: UnifiedObservationItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "note.text").foregroundStyle(.tint)

                if !item.tags.isEmpty {
                    ForEach(item.tags.prefix(3), id: \.self) { tag in
                        TagBadge(tag: tag, compact: true)
                    }
                }

                // Show context badge if note is attached to a specific entity
                if let contextText = item.contextText {
                    Text(contextText)
                        .font(AppTheme.ScaledFont.captionSmallSemibold)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(Color.secondary.opacity(0.1))
                        )
                }

                Spacer()
                Text(item.date, style: .relative)
                    .font(AppTheme.ScaledFont.captionSmall)
                    .foregroundStyle(.secondary)
            }
            if let firstLine = firstLine(of: item.body) {
                Text(firstLine)
                    .font(AppTheme.ScaledFont.body)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
            }
            if !item.studentIDs.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(item.studentIDs.prefix(3), id: \.self) { sid in
                            if let s = studentsByID[sid] {
                                studentChip(displayName(for: s))
                            }
                        }
                    }
                }
            }
        }
        .padding(.vertical, 6)
    #if os(iOS)
        .swipeActions(edge: .trailing) {
            Button {
                editItem(item)
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            .tint(.blue)
        }
    #endif
        .contextMenu {
            Button {
                editItem(item)
            } label: {
                Label("Edit Note", systemImage: "pencil")
            }
        }
    }

    // MARK: - Edit

    func editItem(_ item: UnifiedObservationItem) {
        switch item.source {
        case .note(let note):
            noteBeingEdited = note
        }
    }

    // MARK: - Context Text

    // swiftlint:disable:next cyclomatic_complexity
    func contextText(for note: Note) -> String? {
        if let lesson = note.lesson { return "Lesson: \(lesson.name)" }
        if let work = note.work { return "Work: \(work.title)" }
        if note.lessonAssignment != nil { return "Presentation" }
        if note.attendanceRecord != nil { return "Attendance" }
        if note.workCheckIn != nil { return "Check-In" }
        if note.workCompletionRecord != nil { return "Completion" }
        if note.studentMeeting != nil { return "Meeting" }
        if note.projectSession != nil { return "Session" }
        if let communityTopic = note.communityTopic { return "Topic: \(communityTopic.title)" }
        if note.reminder != nil { return "Reminder" }
        if note.schoolDayOverride != nil { return "Override" }
        return nil
    }

    // MARK: - Row Helpers

    func studentChip(_ name: String) -> some View {
        Text(name)
            .font(AppTheme.ScaledFont.captionSmallSemibold)
            .foregroundStyle(Color.accentColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color.accentColor.opacity(0.12)))
    }

    func firstLine(of text: String) -> String? {
        let trimmed = text.trimmed()
        guard !trimmed.isEmpty else { return nil }
        if let newline = trimmed.firstIndex(of: "\n") {
            return String(trimmed[..<newline])
        }
        return trimmed
    }

    func displayName(for student: Student) -> String {
        let first = student.firstName.trimmed()
        let last = student.lastName.trimmed()
        let li = last.first.map { String($0).uppercased() } ?? ""
        return li.isEmpty ? first : "\(first) \(li)."
    }

    // MARK: - Data Loading

    func loadFirstPageIfNeeded() {
        if loadedItems.isEmpty && !isLoading {
            Task { await loadAllNotes() }
        }
    }

    func reloadAllNotes() {
        loadedItems = []
        lastCursorDate = nil
        hasMore = true
        Task { await loadAllNotes() }
    }

    @MainActor
    func loadAllNotes() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        loadedItems = ObservationsDataLoader.loadAllNotes(
            context: modelContext,
            contextTextProvider: { contextText(for: $0) }
        )
        hasMore = false
        loadStudentsIfNeeded(for: filteredItems)
    }

    var loadMoreRow: some View {
        EmptyView()
    }

    @MainActor
    func loadStudentsIfNeeded(for items: [UnifiedObservationItem]) {
        studentsByID = ObservationsDataLoader.loadStudents(
            for: items,
            existingCache: studentsByID,
            context: modelContext
        )
    }

    // swiftlint:disable:next cyclomatic_complexity
    func contextForNote(_ note: Note) -> UnifiedNoteEditor.NoteContext {
        if let lesson = note.lesson { return .lesson(lesson) }
        if let work = note.work { return .work(work) }
        if let pres = note.lessonAssignment { return .presentation(pres) }
        if let attendanceRecord = note.attendanceRecord { return .attendance(attendanceRecord) }
        if let workCheckIn = note.workCheckIn { return .workCheckIn(workCheckIn) }
        if let workCompletion = note.workCompletionRecord { return .workCompletion(workCompletion) }
        if let studentMeeting = note.studentMeeting { return .studentMeeting(studentMeeting) }
        if let projectSession = note.projectSession { return .projectSession(projectSession) }
        if let communityTopic = note.communityTopic { return .communityTopic(communityTopic) }
        if let reminder = note.reminder { return .reminder(reminder) }
        if let schoolDayOverride = note.schoolDayOverride { return .schoolDayOverride(schoolDayOverride) }
        return .general
    }
}
