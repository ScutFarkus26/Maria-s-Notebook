// MeetingFormPane.swift
// Meeting form pane for creating/editing weekly meeting notes

import SwiftUI
import SwiftData

// MARK: - Meeting Form Pane

struct MeetingFormPane: View {
    let student: Student
    let meetings: [StudentMeeting]
    let meetingTemplates: [MeetingTemplate]
    var onComplete: (() -> Void)?

    @Environment(\.modelContext) private var modelContext

    // Form state
    @State private var isCompleted: Bool = false
    @State private var reflectionText: String = ""
    @State private var focusText: String = ""
    @State private var requestsText: String = ""
    @State private var guideNotesText: String = ""
    @State private var showingAddLessonSheet: Bool = false

    // Get the active meeting template for placeholder prompts
    private var activeTemplate: MeetingTemplate? {
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
                        Label("Add Lesson to Inbox", systemImage: "plus.circle")
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
                            .fill(Color.primary.opacity(0.04))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.primary.opacity(0.08))
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
            guideNotesText: guideNotesText
        )
    }

    private func loadCurrentFromDefaults() {
        let data = MeetingPersistenceService.loadCurrent(studentID: student.id)
        isCompleted = data.isCompleted
        reflectionText = data.reflectionText
        focusText = data.focusText
        requestsText = data.requestsText
        guideNotesText = data.guideNotesText
    }

    private func saveCurrentToDefaults() {
        MeetingPersistenceService.saveCurrent(studentID: student.id, data: currentMeetingData)
    }

    private func clearForm() {
        isCompleted = false
        reflectionText = ""
        focusText = ""
        requestsText = ""
        guideNotesText = ""
        MeetingPersistenceService.clearCurrent(studentID: student.id)
    }

    private func saveAndContinue() {
        // Save to history
        if MeetingPersistenceService.saveToHistory(
            studentID: student.id,
            data: currentMeetingData,
            context: modelContext
        ) {
            clearForm()
            onComplete?()
        }
    }
}
