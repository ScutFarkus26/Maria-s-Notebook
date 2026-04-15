// MeetingFormPane.swift
// Meeting form pane with focus checklist and work review persistence

import SwiftUI
import CoreData

// MARK: - Meeting Form Pane

struct MeetingFormPane: View {
    let student: CDStudent
    let meetings: [CDStudentMeeting]
    let meetingTemplates: [CDMeetingTemplate]
    var overdueWorkCount: Int = 0
    @Binding var workReviewDrafts: [UUID: String]
    @Binding var reviewedWorkIDs: Set<UUID>
    var onComplete: (() -> Void)?

    @Environment(\.managedObjectContext) private var viewContext

    // Form state
    @State private var reflectionText: String = ""
    @State private var requestsText: String = ""
    @State private var guideNotesText: String = ""
    @State private var nextMeetingDate: Date?
    @State private var showingAddLessonSheet: Bool = false

    // Focus checklist state
    @State private var pendingFocusItems: [PendingFocusItem] = []
    @State private var resolvedFocusItemIDs: Set<UUID> = []
    @State private var droppedFocusItemIDs: Set<UUID> = []
    @State private var activeFocusItems: [CDStudentFocusItem] = []

    // Get the active meeting template for placeholder prompts
    private var activeTemplate: CDMeetingTemplate? {
        meetingTemplates.first { $0.isActive }
    }

    private var reflectionPlaceholder: String {
        activeTemplate?.reflectionPrompt ?? "What went well? What was hard?"
    }

    private var requestsPlaceholder: String {
        activeTemplate?.requestsPrompt ?? "Lessons the student wants..."
    }

    private var guideNotesPlaceholder: String {
        activeTemplate?.guideNotesPrompt ?? "Observations only you can see..."
    }

    private var previousFocusText: String? {
        let text = meetings.first?.focus.trimmed() ?? ""
        return text.isEmpty ? nil : text
    }

    private var reflectionHints: [MeetingFieldHint] {
        var hints: [MeetingFieldHint] = []
        if let focus = previousFocusText {
            hints.append(MeetingFieldHint(text: "Last focus: \(focus)", color: .secondary))
        }
        if overdueWorkCount > 0 {
            hints.append(MeetingFieldHint(
                text: "Has \(overdueWorkCount) overdue item\(overdueWorkCount == 1 ? "" : "s")",
                color: AppColors.warning.opacity(0.8)
            ))
        }
        return hints
    }

    private var todayString: String {
        DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .none)
    }

    private var isCurrentEmpty: Bool {
        reflectionText.trimmed().isEmpty &&
        requestsText.trimmed().isEmpty &&
        guideNotesText.trimmed().isEmpty &&
        pendingFocusItems.allSatisfy { $0.text.trimmed().isEmpty } &&
        resolvedFocusItemIDs.isEmpty &&
        droppedFocusItemIDs.isEmpty &&
        reviewedWorkIDs.isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Weekly Meeting")
                            .font(.title2.weight(.semibold))

                        Label(todayString, systemImage: "calendar")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                }

                // Form fields
                meetingField(title: "Student Reflection", text: $reflectionText, placeholder: reflectionPlaceholder, hints: reflectionHints)

                // Focus checklist (replaces free-text focus field)
                FocusChecklistView(
                    existingItems: activeFocusItems,
                    pendingNewItems: $pendingFocusItems,
                    resolvedItemIDs: $resolvedFocusItemIDs,
                    droppedItemIDs: $droppedFocusItemIDs
                )

                meetingField(title: "Lesson Requests", text: $requestsText, placeholder: requestsPlaceholder) {
                    Spacer()
                    Button {
                        showingAddLessonSheet = true
                    } label: {
                        Label("Add to Inbox", systemImage: "plus.circle")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                }
                meetingField(title: "Guide Notes (private)", text: $guideNotesText, placeholder: guideNotesPlaceholder)

                // Work review summary
                if !reviewedWorkIDs.isEmpty {
                    reviewedWorkSummary
                }

                // Schedule Next Meeting
                OptionalDatePicker(
                    toggleLabel: "Schedule Next Meeting",
                    dateLabel: "Next Meeting",
                    date: $nextMeetingDate,
                    displayedComponents: [.date]
                )

                // Action buttons
                HStack {
                    Button {
                        clearForm()
                    } label: {
                        Text("Clear")
                    }
                    .buttonStyle(.bordered)

                    Spacer()

                    Button {
                        saveCurrentToDefaults()
                    } label: {
                        Text("Save Draft")
                    }
                    .buttonStyle(.bordered)
                    .disabled(isCurrentEmpty)

                    Button {
                        saveAndContinue()
                    } label: {
                        Label("Complete & Next", systemImage: "checkmark.circle")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isCurrentEmpty)
                }
            }
            .padding(24)
        }
        .sheet(isPresented: $showingAddLessonSheet) {
            AddLessonToInboxSheet(student: student)
        }
        .onAppear {
            loadCurrentFromDefaults()
            loadActiveFocusItems()
        }
        .onChange(of: student.id) { _, _ in
            // Save current before switching
            saveCurrentToDefaults()
            // Load new student's draft
            loadCurrentFromDefaults()
            loadActiveFocusItems()
        }
        .onChange(of: reflectionText) { _, _ in saveCurrentToDefaults() }
        .onChange(of: requestsText) { _, _ in saveCurrentToDefaults() }
        .onChange(of: guideNotesText) { _, _ in saveCurrentToDefaults() }
        .onChange(of: nextMeetingDate) { _, _ in saveCurrentToDefaults() }
    }

    // MARK: - Reviewed Work Summary

    private var reviewedWorkSummary: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Work Reviewed")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)

            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(AppColors.success)
                    .font(.caption)

                Text("\(reviewedWorkIDs.count) item\(reviewedWorkIDs.count == 1 ? "" : "s") reviewed in this meeting")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Form Field

    private func meetingField<TrailingLabel: View>(
        title: String,
        text: Binding<String>,
        placeholder: String,
        hints: [MeetingFieldHint] = [],
        @ViewBuilder trailingLabel: () -> TrailingLabel = { EmptyView() }
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                trailingLabel()
            }

            ForEach(hints) { hint in
                Text(hint.text)
                    .font(.caption)
                    .foregroundStyle(hint.color)
                    .lineLimit(2)
            }

            ZStack(alignment: .topLeading) {
                TextEditor(text: text)
                    .font(.body)
                    .frame(minHeight: 80)
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.primary.opacity(UIConstants.OpacityConstants.trace))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.primary.opacity(UIConstants.OpacityConstants.subtle))
                    )

                if text.wrappedValue.trimmed().isEmpty {
                    Text(placeholder)
                        .font(.body)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .allowsHitTesting(false)
                }
            }
        }
    }

    // MARK: - Focus Items

    private func loadActiveFocusItems() {
        guard let studentID = student.id else { return }
        activeFocusItems = FocusItemService.fetchActive(studentID: studentID, context: viewContext)
    }

    // MARK: - Persistence

    private var currentMeetingData: MeetingPersistenceService.CurrentMeetingData {
        MeetingPersistenceService.CurrentMeetingData(
            isCompleted: false,
            reflectionText: reflectionText,
            focusText: "", // Focus is now managed via checklist
            requestsText: requestsText,
            guideNotesText: guideNotesText,
            nextMeetingDate: nextMeetingDate,
            pendingFocusTexts: pendingFocusItems.map(\.text),
            resolvedFocusIDs: resolvedFocusItemIDs.map(\.uuidString),
            droppedFocusIDs: droppedFocusItemIDs.map(\.uuidString)
        )
    }

    private func loadCurrentFromDefaults() {
        guard let studentID = student.id else { return }
        let data = MeetingPersistenceService.loadCurrent(studentID: studentID)
        reflectionText = data.reflectionText
        requestsText = data.requestsText
        guideNotesText = data.guideNotesText
        nextMeetingDate = data.nextMeetingDate

        // Restore focus checklist draft state
        pendingFocusItems = (data.pendingFocusTexts ?? []).map { PendingFocusItem(text: $0) }
        resolvedFocusItemIDs = Set((data.resolvedFocusIDs ?? []).compactMap { UUID(uuidString: $0) })
        droppedFocusItemIDs = Set((data.droppedFocusIDs ?? []).compactMap { UUID(uuidString: $0) })
    }

    private func saveCurrentToDefaults() {
        guard let studentID = student.id else { return }
        MeetingPersistenceService.saveCurrent(studentID: studentID, data: currentMeetingData)
    }

    private func clearForm() {
        reflectionText = ""
        requestsText = ""
        guideNotesText = ""
        nextMeetingDate = nil
        pendingFocusItems = []
        resolvedFocusItemIDs = []
        droppedFocusItemIDs = []
        workReviewDrafts = [:]
        reviewedWorkIDs = []
        if let studentID = student.id {
            MeetingPersistenceService.clearCurrent(studentID: studentID)
        }
    }

    private func saveAndContinue() {
        guard let studentID = student.id else { return }

        // Build focus text snapshot for backward compatibility
        let resolvedItems = activeFocusItems.filter { resolvedFocusItemIDs.contains($0.id ?? UUID()) }
        let carryForwardItems = activeFocusItems.filter {
            guard let id = $0.id else { return false }
            return !resolvedFocusItemIDs.contains(id) && !droppedFocusItemIDs.contains(id)
        }
        let focusSnapshot = FocusItemService.snapshotText(
            activeItems: carryForwardItems,
            resolvedItems: resolvedItems,
            newTexts: pendingFocusItems.map(\.text)
        )

        // Save meeting to history
        let completedData = MeetingPersistenceService.CurrentMeetingData(
            isCompleted: true,
            reflectionText: reflectionText,
            focusText: focusSnapshot,
            requestsText: requestsText,
            guideNotesText: guideNotesText,
            nextMeetingDate: nextMeetingDate
        )

        guard let meeting = MeetingPersistenceService.saveToHistory(
            studentID: studentID,
            data: completedData,
            context: viewContext
        ) else { return }

        let meetingID = meeting.id ?? UUID()

        // Persist work reviews
        MeetingReviewService.persistReviews(
            meetingID: meetingID,
            meeting: meeting,
            drafts: workReviewDrafts,
            reviewedIDs: reviewedWorkIDs,
            context: viewContext
        )

        // Persist focus item changes
        // 1. Resolve checked items
        for item in activeFocusItems {
            guard let itemID = item.id else { continue }
            if resolvedFocusItemIDs.contains(itemID) {
                FocusItemService.resolve(item, inMeetingID: meetingID)
            } else if droppedFocusItemIDs.contains(itemID) {
                FocusItemService.drop(item, inMeetingID: meetingID)
            }
        }

        // 2. Create new focus items
        let existingCount = activeFocusItems.count
        for (index, pending) in pendingFocusItems.enumerated() {
            let trimmed = pending.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            FocusItemService.create(
                studentID: studentID,
                text: trimmed,
                meetingID: meetingID,
                sortOrder: existingCount + index,
                context: viewContext
            )
        }

        // Save all changes
        do {
            try viewContext.save()
        } catch {
            // Already logged in individual services
        }

        // Schedule next meeting if date was set
        if let date = nextMeetingDate {
            MeetingScheduler.scheduleMeeting(
                studentID: studentID,
                date: date,
                context: viewContext
            )
        }

        clearForm()
        onComplete?()
    }
}

// MARK: - Meeting Field Hint

private struct MeetingFieldHint: Identifiable {
    let id = UUID()
    let text: String
    let color: Color
}
