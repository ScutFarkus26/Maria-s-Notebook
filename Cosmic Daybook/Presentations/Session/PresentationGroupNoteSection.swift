// PresentationGroupNoteSection.swift
// "What did you notice?": one note for the group, typed or dictated, which
// Split by Child can sort into a note on each child. The organizer only moves
// the guide's words; its follow-up guesses are ignored, so every decision on
// the sheet stays the guide's tap.

import SwiftUI

struct PresentationGroupNoteSection: View {
    @Bindable var session: PresentationSession
    let lesson: CDLesson
    let students: [CDStudent]

    @State private var organizer = CommandBarViewModel()
    @State private var splitMessage: String?

    private var studentIDs: [UUID] { students.compactMap(\.id) }

    var body: some View {
        content
            .onChange(of: organizer.speechService.transcript) { _, transcript in
                if !transcript.isEmpty { session.groupNote = transcript }
            }
            .onDisappear {
                if organizer.speechService.isRecording { organizer.speechService.stopRecording() }
            }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("What did you notice?")
                .font(AppTheme.ScaledFont.calloutSemibold)

            HStack(alignment: .top, spacing: 10) {
                TextField(
                    "Type or speak. Leave it blank if there's nothing to add.",
                    text: $session.groupNote,
                    axis: .vertical
                )
                .lineLimit(3...8)
                .textFieldStyle(.roundedBorder)

                Button {
                    organizer.speechService.toggleRecording(requiresOnDeviceRecognition: true)
                } label: {
                    Image(systemName: organizer.speechService.isRecording ? "stop.circle.fill" : "mic.fill")
                        .font(.title3)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel(organizer.speechService.isRecording ? "Stop dictation" : "Dictate")
            }

            HStack(spacing: 10) {
                Button {
                    splitByChild()
                } label: {
                    if organizer.isProcessing {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Split by Child", systemImage: "person.2.wave.2")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(session.groupNote.trimmed().isEmpty || organizer.isProcessing || students.count < 2)
                .help("Sort what you wrote into a note on each child. Nothing is decided for you.")

                if let splitMessage {
                    Text(splitMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if let speechError = organizer.speechService.error {
                    Text(speechError)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func splitByChild() {
        let text = session.groupNote.trimmed()
        guard !text.isEmpty, let lessonID = lesson.id else { return }
        let names = students.map(\.shortName).joined(separator: ", ")
        organizer.inputText = "I presented \(lesson.name) to \(names). \(text)"
        let studentData = students.compactMap { student -> StudentData? in
            guard let id = student.id else { return nil }
            return StudentData(
                id: id, firstName: student.firstName, lastName: student.lastName, nickname: student.nickname
            )
        }
        let lessonData = [LessonData(id: lessonID, name: lesson.name, area: lesson.area, sequence: lesson.sequence)]
        splitMessage = nil
        Task {
            await organizer.submit(students: studentData, lessons: lessonData)
            applySplit()
        }
    }

    /// Files each child's part of the note on her row; only the words are
    /// used — the organizer's follow-up guesses are ignored.
    private func applySplit() {
        defer { organizer.reset() }
        guard let proposal = organizer.captureProposal else {
            splitMessage = "Couldn't split this one. It stays as one note for the group."
            return
        }
        let ids = Set(studentIDs)
        var filed = 0
        for entry in proposal.studentEntries where ids.contains(entry.studentID) {
            let words = entry.observation.trimmed()
            guard !words.isEmpty else { continue }
            let existing = session.childNotes[entry.studentID]?.trimmed() ?? ""
            session.childNotes[entry.studentID] = existing.isEmpty ? words : existing + " " + words
            filed += 1
        }
        guard filed > 0 else {
            splitMessage = "Nothing was about one child in particular, so it stays as one note."
            return
        }
        session.groupNote = proposal.groupObservation.trimmed()
        splitMessage = filed == 1
            ? "Filed on 1 child below. Edit any line."
            : "Filed on \(filed) children below. Edit any line."
    }
}
