// NoteEditorHelpers.swift
// Helper methods for UnifiedNoteEditor - extracted for maintainability

import OSLog
import SwiftUI
import CoreData
import PhotosUI

#if os(macOS)
import AppKit
#else
import UIKit
#endif

// MARK: - UnifiedNoteEditor Helpers Extension

extension UnifiedNoteEditor {
    private static let logger = Logger.notes

    // MARK: - Computed Properties

    var contextTitle: String {
        switch context {
        case .general: return "Quick Note"
        case .lesson: return "Lesson Note"
        case .work: return "Work Note"
        case .presentation: return "Presentation Note"
        case .workCheckIn: return "Check-In Note"
        case .workCompletion: return "Completion Note"
        case .studentMeeting: return "Meeting Note"
        case .projectSession: return "Session Note"
        case .communityTopic: return "Topic Note"
        case .reminder: return "Reminder Note"
        case .schoolDayOverride: return "Override Note"
        case .goingOut: return "Going-Out Note"
        }
    }

    var shouldShowStudentSelection: Bool {
        switch context {
        case .workCompletion, .studentMeeting:
            return false
        case .presentation(let pres):
            // Planned presentations: notes are for the presentation, not specific students
            return pres.isPresented
        default:
            return true
        }
    }

    var preSelectedStudents: Set<UUID> {
        switch context {
        case .workCompletion(let record):
            if let studentID = UUID(uuidString: record.studentID) {
                return [studentID]
            }
        case .studentMeeting(let meeting):
            if let studentID = UUID(uuidString: meeting.studentID) {
                return [studentID]
            }
        case .presentation(let pres):
            // Only pre-select students for already-presented lessons
            return pres.isPresented ? Set(pres.resolvedStudentIDs) : []
        case .work(let work):
            let parts = (work.participants?.allObjects as? [CDWorkParticipantEntity]) ?? []
            return Set(parts.compactMap { UUID(uuidString: $0.studentID) })
        default:
            break
        }
        return []
    }

    var canSave: Bool {
        if !shouldShowStudentSelection {
            return !bodyText.trimmed().isEmpty
        }
        return !selectedStudentIDs.isEmpty && !bodyText.trimmed().isEmpty
    }

    nonisolated var cardBackgroundColor: Color {
        #if os(macOS)
        return Color(nsColor: .windowBackgroundColor)
        #else
        return Color(uiColor: .systemBackground)
        #endif
    }

    nonisolated var notesBackgroundColor: Color {
        #if os(macOS)
        return Color(nsColor: .controlBackgroundColor).opacity(UIConstants.OpacityConstants.statusBg)
        #else
        return Color(uiColor: .secondarySystemBackground).opacity(UIConstants.OpacityConstants.statusBg)
        #endif
    }

    // MARK: - Setup

    func setupInitialState() {
        selectedStudentIDs = preSelectedStudents

        if let note = initialNote {
            bodyText = note.body
            tags = (note.tags as? [String]) ?? []
            includeInReport = note.includeInReport
            needsFollowUp = note.needsFollowUp
            imagePath = note.imagePath
            // Store original image path for cleanup if image changes
            originalImagePath = note.imagePath

            switch note.scope {
            case .student(let id):
                selectedStudentIDs = [id]
            case .students(let ids):
                selectedStudentIDs = Set(ids)
            case .all:
                break
            }
        }
    }

    // MARK: - Photo Handling

    /// Deletes the previous image if it differs from the original (to prevent orphaned files)
    private func cleanupPreviousImageIfNeeded(newPath: String?) {
        // If we have an existing imagePath that's different from both:
        // 1. The new path we're setting
        // 2. The original path (which belongs to the existing note)
        // Then we need to delete it to prevent orphaned files
        if let existingPath = imagePath,
           !existingPath.isEmpty,
           existingPath != newPath,
           existingPath != originalImagePath {
            do {
                try PhotoStorageService.deleteImage(filename: existingPath)
            } catch {
                Self.logger.error("[\(#function)] Failed to delete previous image: \(error)")
            }
        }
    }

    func handlePhotoChange(_ newItem: PhotosPickerItem?) {
        Task {
            if let newItem {
                do {
                    if let data = try await newItem.loadTransferable(type: Data.self) {
                        await attachPickedPhoto(data, from: newItem)
                    }
                } catch {
                    Self.logger.error("[\(#function)] Failed to load photo data: \(error)")
                }
            } else {
                // User cleared the image
                cleanupPreviousImageIfNeeded(newPath: nil)
                selectedImage = nil
                imagePath = nil
            }
        }
    }

    /// Stores a picked photo and shows its preview. ImageIO transcodes the photo off
    /// the main thread (`PhotoStorageService.savePickedPhoto`) into the same file
    /// decoding it into an `NSImage` / `UIImage` wrote, and the editor keeps a
    /// preview sized for its thumbnail instead of the decoded photo.
    private func attachPickedPhoto(_ data: Data, from item: PhotosPickerItem) async {
        let scale = DisplayScale.current
        let result = await PhotoStorageService.savePickedPhoto(
            data, previewSide: NotePhotoPreview.editorSide, scale: scale
        )
        // A newer pick, or a clear, replaced this one while it was being saved.
        guard selectedPhoto == item else {
            if case .saved(let filename, _) = result {
                deleteUnusedPhoto(filename)
            }
            return
        }
        switch result {
        case .notAnImage:
            return
        case .saved(let filename, let preview):
            // Clean up any intermediate image that might have been selected
            cleanupPreviousImageIfNeeded(newPath: filename)
            imagePath = filename
            selectedImage = preview.map { NotePhotoPreview.image($0, scale: scale) }
        case .failed(_, let error):
            #if DEBUG
            Self.logger.error("Failed to save image: \(error)")
            #endif
            selectedImage = nil
            #if os(macOS)
            selectedPhoto = nil
            #endif
        }
    }

    private func deleteUnusedPhoto(_ filename: String) {
        do {
            try PhotoStorageService.deleteImage(filename: filename)
        } catch {
            Self.logger.error("[\(#function)] Failed to delete superseded image: \(error)")
        }
    }

    #if os(iOS)
    func handleCameraImage(_ image: UIImage) {
        selectedImage = image
        do {
            let newPath = try PhotoStorageService.saveImage(image)
            // Clean up any intermediate image that might have been selected
            cleanupPreviousImageIfNeeded(newPath: newPath)
            imagePath = newPath
            showPreview(ofSavedPhoto: newPath)
        } catch {
            #if DEBUG
            Self.logger.error("Failed to save image: \(error)")
            #endif
            selectedImage = nil
        }
    }

    /// Swaps the full-size capture in the thumbnail for a preview that size, read
    /// from the saved file off the main thread, so the editor stops holding the
    /// decoded camera image.
    private func showPreview(ofSavedPhoto filename: String) {
        let scale = DisplayScale.current
        Task {
            let preview = await PhotoStorageService.preview(
                ofSavedPhoto: filename, side: NotePhotoPreview.editorSide, scale: scale
            )
            // Only while that photo is still the one attached
            guard let preview, imagePath == filename else { return }
            selectedImage = NotePhotoPreview.image(preview, scale: scale)
        }
    }
    #endif

    // MARK: - Name Analysis

    func analyzeTextForNames(_ text: String) async {
        detectedStudentIDs.removeAll()
        guard !text.isEmpty else { return }

        let studentData = students.compactMap { student -> StudentData? in
            guard let id = student.id else { return nil }
            return StudentData(
                id: id,
                firstName: student.firstName,
                lastName: student.lastName,
                nickname: student.nickname
            )
        }

        let result = await tagger.findStudentMatches(in: text, studentData: studentData)

        detectedStudentIDs = result.exact.union(result.fuzzy)

        let newAutoSelects = result.autoSelect.subtracting(selectedStudentIDs)
        if !newAutoSelects.isEmpty {
            selectedStudentIDs.formUnion(newAutoSelects)
        }
    }

    // MARK: - Initials Expansion

    func expandInitialsInBodyText() {
        let studentData = students.compactMap { student -> StudentData? in
            guard let id = student.id else { return nil }
            return StudentData(
                id: id, firstName: student.firstName, lastName: student.lastName, nickname: student.nickname
            )
        }
        bodyText = NoteInitialsExpander.expanding(bodyText, students: studentData)
    }

}

// MARK: - Initials Expansion

/// Expand Initials: replaces clear initials that belong to exactly one child
/// ("JD", "J.D.") with that child's short name ("Jonah D"). The rules for what
/// counts as initials are the tagger's (`PatternMatchHelpers.initialsMatches`),
/// so "OK", "PE", "TV", "a.m." and ordinary words stay as typed.
enum NoteInitialsExpander {
    nonisolated static func expanding(_ text: String, students: [StudentData]) -> String {
        guard !text.isEmpty else { return text }

        var studentsByInitials: [String: [StudentData]] = [:]
        for student in students {
            guard let key = PatternMatchHelpers.initialsKey(
                first: student.firstName, last: student.lastName
            ) else { continue }
            studentsByInitials[key, default: []].append(student)
        }

        // Matches come in text order and never overlap; rebuild the text around them.
        var newText = ""
        var cursor = text.startIndex
        let firstNames = Set(students.map { $0.firstName.folded() })
        for match in PatternMatchHelpers.initialsMatches(in: FoldedText(text), firstNames: firstNames) {
            guard let candidates = studentsByInitials[match.key],
                  candidates.count == 1,
                  let student = candidates.first else { continue }
            newText += text[cursor..<match.range.lowerBound]
            newText += StudentFormatter.displayName(firstName: student.firstName, lastName: student.lastName)
            cursor = match.range.upperBound
        }
        newText += text[cursor...]
        return newText
    }
}

// MARK: - Photo Action Chip Style

extension View {
    /// Shared pill styling for the photo action buttons (Take Photo / Choose Photo).
    nonisolated func photoActionChipStyle(background: Color) -> some View {
        self
            .font(AppTheme.ScaledFont.body)
            .foregroundStyle(.primary)
            .padding(.horizontal, AppTheme.Spacing.compact)
            .padding(.vertical, AppTheme.Spacing.small)
            .background(
                RoundedRectangle(cornerRadius: UIConstants.CornerRadius.medium, style: .continuous)
                    .fill(background)
            )
            .overlay(
                RoundedRectangle(cornerRadius: UIConstants.CornerRadius.medium, style: .continuous)
                    .stroke(
                        Color.secondary.opacity(UIConstants.OpacityConstants.light),
                        lineWidth: UIConstants.StrokeWidth.thin
                    )
            )
    }
}
