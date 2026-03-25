// ObservationModeViewModel.swift
// ViewModel for the observation mode recording interface.
// Creates standard Notes with Montessori-specific tags.

import Foundation
import SwiftData
import SwiftUI

@Observable
@MainActor
final class ObservationModeViewModel {
    // MARK: - Student Selection

    var selectedStudentIDs: Set<UUID> = []
    private(set) var allStudents: [Student] = []

    var selectedStudents: [Student] {
        allStudents.filter { selectedStudentIDs.contains($0.id) }
    }

    // MARK: - Observation Content

    var bodyText: String = ""
    var tags: [String] = []

    // MARK: - Timer

    var observationStartTime: Date?
    var isTimerRunning = false
    var elapsedSeconds: Int = 0
    private var timerTask: Task<Void, Never>?

    // MARK: - Prompt Rotation

    var currentPromptIndex: Int = 0
    private(set) var shuffledPrompts: [ObservationPrompt] = []

    var currentPrompt: ObservationPrompt? {
        guard !shuffledPrompts.isEmpty else { return nil }
        let index = currentPromptIndex % shuffledPrompts.count
        return shuffledPrompts[index]
    }

    // MARK: - State

    var showingStudentPicker = false
    private(set) var isSaving = false
    private(set) var lastSaveSucceeded = false

    // MARK: - Computed

    var canSave: Bool {
        !bodyText.trimmed().isEmpty
    }

    // MARK: - Lifecycle

    func loadData(context: ModelContext) {
        let descriptor = FetchDescriptor<Student>(sortBy: Student.sortByName)
        allStudents = context.safeFetch(descriptor).filter(\.isEnrolled)
        allStudents = TestStudentsFilter.filterVisible(allStudents)

        if shuffledPrompts.isEmpty {
            shuffledPrompts = ObservationPromptLibrary.prompts.shuffled()
        }
    }

    // MARK: - Timer

    func toggleTimer() {
        if isTimerRunning {
            stopTimer()
        } else {
            startTimer()
        }
    }

    func startTimer() {
        observationStartTime = Date()
        isTimerRunning = true
        timerTask?.cancel()
        timerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { break }
                self?.elapsedSeconds += 1
            }
        }
    }

    func stopTimer() {
        isTimerRunning = false
        timerTask?.cancel()
        timerTask = nil
    }

    // MARK: - Prompts

    func nextPrompt() {
        guard !shuffledPrompts.isEmpty else { return }
        currentPromptIndex = (currentPromptIndex + 1) % shuffledPrompts.count
    }

    func previousPrompt() {
        guard !shuffledPrompts.isEmpty else { return }
        currentPromptIndex = (currentPromptIndex - 1 + shuffledPrompts.count) % shuffledPrompts.count
    }

    func applySuggestedTags() {
        guard let prompt = currentPrompt else { return }
        for tag in prompt.suggestedTags where !tags.contains(tag) {
            tags.append(tag)
        }
    }

    // MARK: - Save

    func saveObservation(context: ModelContext) {
        guard canSave else { return }
        isSaving = true

        // Build observation body with timer info
        var fullBody = bodyText
        if elapsedSeconds > 0 {
            let minutes = elapsedSeconds / 60
            let seconds = elapsedSeconds % 60
            let timerLine = "\n\n⏱ Observation duration: \(minutes)m \(seconds)s"
            fullBody += timerLine
        }

        // Determine scope
        let scope: NoteScope
        let studentIDsList = Array(selectedStudentIDs)
        switch studentIDsList.count {
        case 0:
            scope = .all
        case 1:
            scope = .student(studentIDsList[0])
        default:
            scope = .students(studentIDsList)
        }

        // Create note
        let note = Note(
            body: fullBody,
            scope: scope,
            tags: tags,
            includeInReport: false,
            needsFollowUp: false
        )

        context.insert(note)
        note.syncStudentLinksIfNeeded(in: context)
        context.safeSave()

        isSaving = false
        lastSaveSucceeded = true

        // Reset state for next observation
        resetForNextObservation()
    }

    // MARK: - Reset

    func resetForNextObservation() {
        bodyText = ""
        tags = []
        elapsedSeconds = 0
        observationStartTime = nil
        isTimerRunning = false
        timerTask?.cancel()
        timerTask = nil
        lastSaveSucceeded = false
        // Keep selected students and prompts position
    }

    func resetAll() {
        resetForNextObservation()
        selectedStudentIDs = []
        currentPromptIndex = 0
        shuffledPrompts = ObservationPromptLibrary.prompts.shuffled()
    }

    nonisolated deinit {
        // timerTask will be cancelled when the ViewModel is deallocated
    }
}
