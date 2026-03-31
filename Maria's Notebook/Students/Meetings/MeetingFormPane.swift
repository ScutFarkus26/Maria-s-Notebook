// MeetingFormPane.swift
// Meeting form pane for creating/editing weekly meeting notes

import SwiftUI
import CoreData

// MARK: - Meeting Form Pane

struct MeetingFormPane: View {
    let student: CDStudent
    let meetings: [CDStudentMeeting]
    let meetingTemplates: [CDMeetingTemplate]
    var onComplete: (() -> Void)?

    @Environment(\.managedObjectContext) private var viewContext

    // Form state
    @State private var isCompleted: Bool = false
    @State private var reflectionText: String = ""
    @State private var focusText: String = ""
    @State private var requestsText: String = ""
    @State private var guideNotesText: String = ""
    @State private var nextMeetingDate: Date?
    @State private var showingAddLessonSheet: Bool = false

    // Get the active meeting template for placeholder prompts
    private var activeTemplate: CDMeetingTemplate? {
        meetingTemplates.first { $0.isActive }
    }

    private var reflectionPlaceholder: String {
        activeTemplate?.reflectionPrompt ?? "What went well? What was hard?"
    }

    private var focusPlaceholder: String {
        activeTemplate?.focusPrompt ?? "1-3 priorities for this week..."
    }

    private var requestsPlaceholder: String {
        activeTemplate?.requestsPrompt ?? "Lessons the student wants..."
    }

    private var guideNotesPlaceholder: String {
        activeTemplate?.guideNotesPrompt ?? "Observations only you can see..."
    }

    private var todayString: String {
        DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .none)
    }

    private var isCurrentEmpty: Bool {
        reflectionText.trimmed().isEmpty &&
        focusText.trimmed().isEmpty &&
        requestsText.trimmed().isEmpty &&
        guideNotesText.trimmed().isEmpty
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

                    Spacer()

                    Toggle("Completed", isOn: $isCompleted)
                        .toggleStyle(.switch)
                        .labelsHidden()

                    Text("Completed")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                // Form fields
                meetingField(title: "Student Reflection", text: $reflectionText, placeholder: reflectionPlaceholder)
                meetingField(title: "Focus for This Week", text: $focusText, placeholder: focusPlaceholder)
                meetingField(title: "Lesson Requests", text: $requestsText, placeholder: requestsPlaceholder)
                meetingField(title: "Guide Notes (private)", text: $guideNotesText, placeholder: guideNotesPlaceholder)

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

                    Button {
                        showingAddLessonSheet = true
                    } label: {
                        Label("Add CDLesson to Inbox", systemImage: "plus.circle")
                    }
                    .buttonStyle(.bordered)

                    Spacer()

                    Button {
                        saveAndContinue()
                    } label: {
                        Label("Save & Next", systemImage: "arrow.right")
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
        }
        .onChange(of: student.id) { _, _ in
            // Save current before switching
            saveCurrentToDefaults()
            // Load new student's draft
            loadCurrentFromDefaults()
        }
        .onChange(of: reflectionText) { _, _ in saveCurrentToDefaults() }
        .onChange(of: focusText) { _, _ in saveCurrentToDefaults() }
        .onChange(of: requestsText) { _, _ in saveCurrentToDefaults() }
        .onChange(of: guideNotesText) { _, _ in saveCurrentToDefaults() }
        .onChange(of: nextMeetingDate) { _, _ in saveCurrentToDefaults() }
        .onChange(of: isCompleted) { _, _ in saveCurrentToDefaults() }
    }

    // MARK: - Form Field

    private func meetingField(title: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)

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

    // MARK: - Persistence

    private var currentMeetingData: MeetingPersistenceService.CurrentMeetingData {
        MeetingPersistenceService.CurrentMeetingData(
            isCompleted: isCompleted,
            reflectionText: reflectionText,
            focusText: focusText,
            requestsText: requestsText,
            guideNotesText: guideNotesText,
            nextMeetingDate: nextMeetingDate
        )
    }

    private func loadCurrentFromDefaults() {
        guard let studentID = student.id else { return }
        let data = MeetingPersistenceService.loadCurrent(studentID: studentID)
        isCompleted = data.isCompleted
        reflectionText = data.reflectionText
        focusText = data.focusText
        requestsText = data.requestsText
        guideNotesText = data.guideNotesText
        nextMeetingDate = data.nextMeetingDate
    }

    private func saveCurrentToDefaults() {
        guard let studentID = student.id else { return }
        MeetingPersistenceService.saveCurrent(studentID: studentID, data: currentMeetingData)
    }

    private func clearForm() {
        isCompleted = false
        reflectionText = ""
        focusText = ""
        requestsText = ""
        guideNotesText = ""
        nextMeetingDate = nil
        if let studentID = student.id {
            MeetingPersistenceService.clearCurrent(studentID: studentID)
        }
    }

    private func saveAndContinue() {
        guard let studentID = student.id else { return }
        // Save to history
        if MeetingPersistenceService.saveToHistory(
            studentID: studentID,
            data: currentMeetingData,
            context: viewContext
        ) {
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
}
